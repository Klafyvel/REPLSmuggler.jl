module REPLSmuggler

using BaseDirs

export smuggle

const PROJECT = BaseDirs.Project("REPLSmuggler")

# Nouns related to smuggling
const SMUGGLING_NOUNS = ["contraband", "clandestine_operation", "smuggler", "bootlegging", "illicit_trade", "covert_transport", "underworld", "black_market", "contraband_goods", "smuggling_route"]

# Adjectives related to smuggling
const SMUGGLING_ADJECTIVES = ["covert", "stealthy", "illicit", "underground", "secretive", "clandestine", "smuggled", "contraband", "sneaky", "illegitimate"]

yer_name() = rand(SMUGGLING_ADJECTIVES) * "_" * rand(SMUGGLING_NOUNS)

include("Protocols.jl")
using .Protocols

include("History.jl")
using .History

include("Server.jl")
using .Server


"""
Store the current server.
"""
CURRENT_SMUGGLER = nothing

function smuggle(specific_smuggler, serializer)
    global CURRENT_SMUGGLER
    CURRENT_SMUGGLER = Smuggler(specific_smuggler, serializer, Set{Session}(), History.get_history_provider())
    serve_repl(CURRENT_SMUGGLER)
end

include("SocketSmugglers.jl")
using .SocketSmugglers

include("MsgPackSerializer.jl")
using MsgPack
using .MsgPackSerializer

"""
    basepath()

Return a path where REPLSmuggler can store its socket, depending on the OS.

* For Linux: `/run/user/<uid>/julia/replsmuggler/`
* For Windows: `\\\\.\\pipe\\`
* For MacOS: `~/Library/Application Support/julia/replsmuggler/`

"""
basepath() = if Sys.isunix()
    BaseDirs.User.runtime(REPLSmuggler.PROJECT)
elseif Sys.iswindows()
    replace("😭😭.😭pipe😭", "😭" => "\\")
else
    error("Can't create a UNIX Socket or equivalent on your platform.")
end

"""
    smuggle([name]; basepath=basepath(), serializer=MsgPack)

Start a server using a UNIX sockets with a random name and `MsgPack.jl` as a
serializer. The socket will be stored in `joinpath(basepath, name)`. If `name`
is not provided, REPLSmuggler will try randomly generated names until a 
non-already-existing socket name is found.

For example, on linux, you could find the socket in `/run/user/1000/julia/replsmuggler/clandestine_underworld`
if the name was chosen to be `clandestine_underworld`.

The socket name is displayed in the REPL, and the server is accessible through
[`CURRENT_SMUGGLER`](@ref).

See also [basepath](@ref).
"""
smuggle(name::AbstractString; basepath = basepath(), serializer = MsgPack) = smuggle(SocketSmuggler(joinpath(basepath, name)), serializer)
function smuggle(; basepath = basepath(), serializer = MsgPack)
    name = yer_name()
    while ispath(joinpath(basepath, name))
        name = yer_name()
    end
    smuggle(SocketSmuggler(joinpath(basepath, name)), serializer)
end

"""
    smuggle(title, diagnostic, filename, line, function)

Smuggle a diagnostic in file `filename`, function `function`, at line `line`.

!!! warning

    The notification will be sent to all connected sessions.
"""
function smuggle(title, diagnostic, filename, line, func)
    if isnothing(CURRENT_SMUGGLER)
        error("No smuggling route. First call `smuggle()` and connect with your editor to open one.")
    end
    for session in Server.sessions(CURRENT_SMUGGLER)
        put!(
            session.responsechannel,
            Protocols.Diagnostic(title, diagnostic, [(filename, line, func)]),
        )
    end
end

"""
    smuggle(exception, stackframes=stacktrace(Base.catch_stacktrace()))

Smuggle an exception. Can be used to report on exceptions thrown by code evaluated
by the user in the REPL.

!!! warning

    The notification will be sent to all connected sessions.

# Examples
```julia
try
    error("foo")
catch exc
    smuggle(exc)
end
```
"""
function smuggle(exc::T, stackframes = stacktrace(Base.catch_backtrace())) where {T <: Exception}
    if isnothing(CURRENT_SMUGGLER)
        error("No smuggling route. First call `smuggle()` and connect with your editor to open one.")
    end
    frames = [
        (frame.file, frame.line, frame.func)
        for frame in stackframes
    ]
    for session in Server.sessions(CURRENT_SMUGGLER)
        put!(session.responsechannel, Protocols.Diagnostic(string(T), string(exc), frames))
    end
end

end
