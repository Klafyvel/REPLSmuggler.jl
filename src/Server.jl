"""
Implementation of the server for REPLSmuggler.jl -the brain of REPSmuggler.jl.

The handling of the communication protocol is done by [`Protocols`](@ref).

The implementation is heavily inspired by the server from [RemoteREPL.jl](https://github.com/c42f/RemoteREPL.jl).
"""
module Server

using REPL

using ..Protocols

export Session, Smuggler, serve_repl

function io end


"""
The session of a client.
"""
struct Session{T}
    "Where the incoming requests are buffered."
    entrychannel::Channel
    "Where the outgoing requests are buffered."
    responsechannel::Channel
    """A session might store additional parameters here. Currently supported:
    - `evalbyblocks::Bool`: Controls evaluation of code chunks by block or by statements.
    - `showdir::String`: Path to a directory to store images.
    - `enableimages::Bool`: enable images display?
    - `iocontext::Dict{Symbol,Any}`: IOContext options for `show`.
    """
    sessionparams::Dict
    "The module where the code should be evaluated (currently: Main)"
    evaluatein::Module
    "The actual structure where the data are coming from. Example: a `Base.PipeEndpoint`."
    smugglerspecific::T
    "The specific [`Protocols.Protocol`](@ref) used in this session."
    protocol::Protocols.Protocol
end
Session(specific, serializer) = Session(
    Channel(1),
    Channel(1),
    Dict("evalbyblocks" => false, "showdir" => tempdir(), "enableimages"=>true, "iocontext"=>Dict{Symbol, Any}()),
    Main,
    specific,
    Protocols.Protocol(serializer, io(specific)),
)
function Base.show(io::IO, ::Session{T}) where {T}
    print(io, "Session{$T}()")
end
Base.isopen(s::Session) = isopen(s.smugglerspecific)
function Base.close(s::Session)
    close(s.entrychannel)
    close(s.responsechannel)
    close(s.smugglerspecific)
end
Protocols.dispatchonmessage(s::Session, args...; kwargs...) = Protocols.dispatchonmessage(s.protocol, args...; kwargs...)

"Store the sessions of a server."
struct Smuggler{T, U}
    "Specific to the currently used Server. Example: a [`SocketSmugglers.SocketSmuggler`](@ref)."
    vessel::T
    "The serializer used in this server. For example: [`MsgPack`](https://github.com/JuliaIO/MsgPack.jl)."
    serializer::U
    "All the currently open sessions."
    sessions::Set{Session}
end
Base.show(io::IO, s::Smuggler{T, U}) where {T, U} = print(io, "Smuggler($T, $(s.serializer))")
"Get the vessel."
vessel(s::Smuggler) = s.vessel
"Get the sessions."
sessions(s::Smuggler) = s.sessions
Base.isopen(s::Smuggler) = isopen(vessel(s))
"""
Has to be implemented for each specific server. See for example `SocketSmugglers`.

Should return the specific of a session used to build a [`Session`](@ref).
"""
function waitsession(::T) where {T}
    error("You must implement `REPLSmuggler.waitsession` for type $T")
end
"""
    getsession(smuggler)

Return a [`Session`](@ref) through a call to [`waitsession`](@ref).
"""
function getsession(smuggler::Smuggler)
    s = Session(waitsession(smuggler), smuggler.serializer)
    push!(smuggler.sessions, s)
    s
end
function Base.close(smuggler::Smuggler, session::Session)
    close(session)
    pop!(smuggler.sessions, session)
end
function Base.close(s::Smuggler)
    for session in sessions(s)
        close(session)
    end
    empty!(sessions(s))
    close(vessel(s))
end

# Like `sprint()`, but uses IOContext properties `ctx_properties`
#
# This is used to stringify results before sending to the client. This is
# beneficial because:
#   * It allows us to show the user-defined types which exist only on the
#     remote server
#   * It allows us to limit the amount of data transmitted (eg, large arrays
#     are truncated when the :limit IOContext property is set)
function sprint_ctx(f, session)
    io = IOBuffer()
    ctx = IOContext(io, :module => session.evaluatein)
    f(ctx)
    String(take!(io))
end

include("eval.jl")

"""
    evaluate_entries(session)

Repeatedly evaluate the code put to the input channel of the `session`.
"""
function evaluate_entries(session)
    while true
        try
            msgid, file, line, value = take!(session.entrychannel)
            evaluate_entry(session, msgid, file, line, value)
        catch exc
            if exc isa InvalidStateException && !isopen(session.entrychannel)
                break
            elseif exc isa InterruptException
                # Ignore any interrupts which are sent while we're not
                # evaluating a command.
                continue
            else
                rethrow()
            end
        end
    end
end

"""
Fed to [`Protocols.dispatchonmessage`](@ref) to respond accordingly to incoming
requests.
"""
function treatrequest end

function treatrequest(::Val{:interrupt}, session, repl_backend, msgid)
    @debug "Scheduling an interrupt." session repl_backend
    schedule(repl_backend, InterruptException(); error = true)
    put!(session.responsechannel, Protocols.Result(msgid, "Done."))
end
function treatrequest(::Val{:eval}, session, repl_backend, msgid, file, line, code)
    @debug "Adding an entry." msgid file line session repl_backend
    put!(session.entrychannel, (msgid, file, line, code))
end
function treatrequest(::Val{:exit}, session, repl_backend, msgid)
    @debug "Scheduling an interrupt." session repl_backend
    schedule(repl_backend, InterruptException(); error = true)
    @debug "Exiting" session repl_backend
    close(session)
    put!(session.responsechannel, Protocols.Result(msgid, "Done."))
end
function treatrequest(::Val{:configure}, session, repl_backend, msgid, settings)
    @debug "Configuring" session repl_backend settings
    if isempty(settings)
        return
    end
    for k in keys(session.sessionparams)
        if haskey(settings, k)
            if k == "iocontext"
                if haskey(settings[k], "displaysize")
                    settings[k]["displaysize"] = tuple(Int.(settings[k]["displaysize"])...)
                end
                settings[k] = Dict([Symbol(k)=>v for (k,v) in settings[k]])
            end
            session.sessionparams[k] = settings[k]
        end
    end
end
"""
Dispatch repeatedly the incoming requests of a session.
"""
function deserialize_requests(session::Session, repl_backend)
    while isopen(session)
        try
            Protocols.dispatchonmessage(session, treatrequest, session, repl_backend)
        catch exc
            if exc isa Protocols.ProtocolException
                @error exc
                put!(session.responsechannel, Protocols.Error(exc))
            elseif !isopen(session)
                break
            else
                put!(session.responsechannel, Protocols.Error(Protocols.ProtocolException("Server Error.")))
                rethrow()
            end
        end
    end
end
"""
Send repeatedly the responses of a given session.
"""
function serialize_responses(session)
    try
        while true
            response = take!(session.responsechannel)
            @debug "Response is" response
            Protocols.serialize(session.protocol, response)
        end
    catch
        if isopen(session)
            rethrow()
        end
    end
end

"""
Serve one session, starting three loops to evaluate the entries, serialize the
responses and deserialize the requests.
"""
function serve_repl_session(session)
    put!(session.responsechannel, Protocols.Handshake())
    @sync begin
        repl_backend = @async try
            evaluate_entries(session)
        catch exc
            @error "RemoteREPL backend crashed" exception = exc, catch_backtrace()
        finally
            close(session)
        end

        @async try
            serialize_responses(session)
        catch exc
            @error "RemoteREPL responder crashed" exception = exc, catch_backtrace()
        finally
            close(session)
        end

        try
            deserialize_requests(session, repl_backend)
        catch exc
            @error "RemoteREPL frontend crashed" exception = exc, catch_backtrace()
            rethrow()
        finally
            close(session)
        end
    end
end

"""
Serve sessions to clients connecting to a server.
"""
function serve_repl(smuggler::Smuggler)
    @async try
        while isopen(smuggler)
            session = getsession(smuggler)
            @async try
                serve_repl_session(session)
            catch exception
                if !(exception isa EOFError && !isopen(session))
                    @warn "Something went wrong evaluating client command" exception = exception, catch_backtrace()
                end
            finally
                println()
                @info "REPL client exited" session
                println()
                close(smuggler, session)
            end
            println()
            @info "New client connected" session
            println()
        end
    catch exception
        if exception isa Base.IOError && !isopen(smuggler)
            # Ok - server was closed
            return
        end
        @error "Unexpected server failure" smuggler exception = exception, catch_backtrace()
        rethrow()
    finally
        close(smuggler)
    end
end

end
