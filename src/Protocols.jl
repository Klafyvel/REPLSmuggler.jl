"""
Definition of the protocol used by REPLSmuggler.jl. It is based on MsgPack-RPC,
see here:
- https://github.com/msgpack/msgpack/blob/master/spec.md
- https://github.com/msgpack-rpc/msgpack-rpc/blob/master/spec.md

The actual (de)serialization from and to MsgPack objects is handled by MsgPack.jl
through a lightweight wrapper defined in `MsgPackSerializer`.

The protocol consists of requests messages and their corresponding response messages. There can also be notification messages.

As per the specification, a request is serialized to an array of four elements,
that could be written in Julia as follow:

    [type::UInt8, msgid::UInt32, method::String, params::Vector{Any}]

Where `type = 0x00`. For convenience, we define a structure and teach `MsgPack.jl`
to serialize it.

A response message should be serialized as:

    [type::UInt8, msgid::UInt32, error::Any, result::Any]

Where `type = 0x01`. `msgid` is the identifier of the corresponding request.

Finally, a notification has the form:

    [type::UInt8, method::String, params::Vector{Any}]

Where `type = 0x02`.

## Defined methods for requests.

We allow the client to run the following methods. If a method is unknown by the
server, it will raise an error.

- `eval`: Evaluate a chunk of code.
  Parameters:
  - `file::String`
  - `line::UInt32`
  - `code::String`
- `configure`: Configure the current session.
  Parameters:
  - `settings::Dict{String, Any}`
  Settings do not have to be given in the request if you are not changing them. 
  Currently, the following settings are supported:
    - `evalbyblocks::Bool` should the session evaluate entries by block rather than
  by toplevel statements?
    - `showdir::String`: directory to store images.
    - `enableimages::String`: Should we display objects displayable as images be showed as images?
    - `iocontext::Dict{String,Any}`: IOContext options for `show`.
- `interrupt`: Interrupt the current evaluation.
  No parameter.
- `exit`: Stop the current session.
  No parameter.

## Responses of the server.

The result field is empty if an error occured. Otherwise it contains three elements:
- `linenumber::UInt32`: Line that produced the output,
- `mime::String`: MIME of the answer. If it is `text/plain` the output should be displayed as is. The other supported MIME types are listed in [`IMAGE_MIME`](@ref) and are meant to display image results.
- `output`: The output. If `mime` is `text/plain` this is a `String` to be displayed, otherwise it is a path to an image (`String`) corresponding to the MIME type.

If an error occured, then the error field is a three-elements array structured as follow:
- `exception::String`: Name of the exception, *e.g.* `"ValueError"`,
- `exception_text::String`: Text, *e.g.* `"This value cannot be < 0."`,
- `stacktrace::Vector{Tuple{String, UInt32, String}}`: The stacktrace, with each 
  row being `(file, line, function, module)`. Module can be `nil`.

## Notifications by the server.

Currently, the following notifications can be sent by the server. If a notification received by the client is unknown, it should simply be ignored without erroring.

- `handshake`: Sent at the begining of a session, mainly to ensure the correct
  version of the protocol is being used.
  Parameters:
  - `myname::String`: Name of the server. Will typically be `REPLSmuggler`, but
    could be replaced if other implementations of the protocol were to exist.
  - `version::String`: A [sementic versioning](https://semver.org/) version number
    telling the client which version of the protocol is being used by the server.
- `diagnostic`: Sent following the evaluation of some code by the user from the 
   REPL. For example, this could be used via a direct call to display a diagnostic
   on a specific line, or to report an exception from some code evaluated by the 
   user, or report diagnostic from other packages such as `JET.jl`. This is very
   similar to how an exception would be handled when executing code.
   Parameters:
   - `title::String`: Short title for the diagnostic.
   - `diagnostic::String`: The diagnostic that is to be displayed.
   - `stacktrace::Vector{Tuple{String, UInt32, String}}`: The stacktrace, with
   each row being `(file, line, function)`.

## Typical session:

- The client connects to the server.
- The server sends a `handshake` notification.
- The client checks it is running the correct version of the protocol.
- The client runs requests (`eval`, `interrupts`...)
- The server responds to the requests.
- The client runs `exit`.
- The server stops all the running code and close the session.

Note that any interrupt of the connection (*i.e.* closing the socket) is equivalent
to sending an `exit` request.

"""
module Protocols

using ..REPLSmuggler: stringify_error

"Name of the protocol implementation."
const PROTOCOL_MAGIC = "REPLSmuggler"
"Protocol version."
const PROTOCOL_VERSION = v"0.5"

"Supported image MIME types."
const IMAGE_MIME = [
    MIME("image/png"),
    MIME("image/jpg"),
    MIME("image/jpeg"),
    MIME("image/gif"),
    MIME("image/webp"),
    MIME("image/avif"),
]

"MsgPackRPC message types."
const MsgType = UInt8
const REQUEST = 0x00
const RESPONSE = 0x01
const NOTIFICATION = 0x02

"Used internally to report protocol exceptions."
struct ProtocolException <: Exception
    msgid::Union{UInt32, Nothing}
    msg::String
end
ProtocolException(s::AbstractString) = ProtocolException(nothing, s)
Base.showerror(io::IO, e::ProtocolException) = print(io, "Msg[$(e.msgid)]: $(e.msg)")

"Represents a MsgPackRPC message. `type` needs not to be stored explicitely."
abstract type AbstractMsgPackRPC end

"""
    astuple(message)

Returns a vector from the message that can be serialized.
"""
function astuple end

function isvalidrequest(method, params)
    if method == "eval" && length(params) == 3
        return true
    elseif method == "configure" && length(params) == 1
        return true
    elseif method ∈ ("interrupt", "exit") && length(params) == 0
        return true
    else
        return false
    end
end

"Represents a request."
struct Request <: AbstractMsgPackRPC
    msgid::UInt32
    method::String
    params::Vector
    function Request(msgid, method, params)
        if !isvalidrequest(method, params)
            throw(ProtocolException(msgid, "Invalid method `$method` with $(length(params)) parameters."))
        end
        return try
            new(msgid, method, params)
        catch e
            throw(ProtocolException(msgid, "Invalid request: $e."))
        end
    end
end
function Request(array)
    if length(array) != 4
        throw(ProtocolException("Invalid request of length $(length(array)): $array"))
    end
    return Request(array[2:end]...)
end
astuple(r::Request) = (
    REQUEST,
    r.msgid,
    r.method,
    r.params,
)

"Represents a response."
abstract type AbstractResponse <: AbstractMsgPackRPC end
struct ErrorResponse <: AbstractResponse
    msgid
    exception
    exception_text
    stacktrace
end
astuple(e::ErrorResponse) = (
    RESPONSE,
    e.msgid,
    (
        e.exception,
        e.exception_text,
        e.stacktrace,
    ),
    nothing,
)
struct ResultResponse{T} <: AbstractResponse
    msgid::UInt32
    line::UInt32
    mime::MIME{T}
    result
end
astuple(r::ResultResponse) = (
    RESPONSE,
    r.msgid,
    nothing,
    (
        r.line,
        string(r.mime),
        r.result,
    ),
)
Base.show(io::IO, ::MIME"text/plain", r::ResultResponse) = show(io, "ResultResponse($(r.msgid), $(r.line), $(r.mime), ...)")

"Represents a notification."
struct Notification <: AbstractMsgPackRPC
    method::String
    params::Vector
end
function Notification(array)
    if length(array) != 2
        throw(ProtocolException("Invalid notification of length $(length(array))."))
    end
    return Notification(array...)
end
astuple(notification::Notification) = (
    NOTIFICATION,
    notification.method,
    notification.params,
)

struct Protocol{T}
    io
end
Protocol(T, io) = Protocol{T}(io)

"""
    serialize(protocol, message)

Serialize an `AbstractMsgPackRPC`. Must be implemented by the serializer, *e.g.*
`MsgPackSerializer.jl`.
"""
function serialize end
"""
    serialize(protocol)

De-serialize an `AbstractMsgPackRPC`. Must be implemented by the serializer, *e.g.*
`MsgPackSerializer.jl`.
"""
function deserialize end

"""
    Handshake()

Create a hand-shake notification.
"""
Handshake() = Notification("handshake", [PROTOCOL_MAGIC, string(PROTOCOL_VERSION)])

"""
    Diagnostic(title, diagnostic, stackframe)

See protocol's definition and build `stackframe` accordingly.
"""
function Diagnostic(title, diagnostic, stackframe)
    return Notification(
        "diagnostic",
        [title, diagnostic, stackframe],
    )
end

"""
    Error(msgid, error, stackframe)
"""
function Error(msgid, error::T, stackframe) where {T}
    frames = [(frame.file, frame.line, frame.func, isnothing(frame.parentmodule) ? nothing : string(frame.parentmodule)) for frame in stackframe]
    return ErrorResponse(
        msgid,
        string(T), stringify_error(error), frames,
    )
end
function Error(exc::ProtocolException)
    return ErrorResponse(
        something(exc.msgid, 0),
        "ProtocolException", exc.msg, [],
    )
end

"""
    Result(msgid, line, [mime=MIME("text/plain"),] result)
"""
Result(msgid, line, result) = ResultResponse(
    trunc(UInt32, msgid),
    trunc(UInt32, line),
    MIME("text/plain"),
    result,
)
Result(msgid, line, mime, result) = ResultResponse(
    trunc(UInt32, msgid),
    trunc(UInt32, line),
    mime,
    result,
)

"""
    dispatchonmessage(protocol, f, args...; kwargs)

Deserialize a request, and send it to the correct method of `f`. `f` should
define methods with a first parameter being of type `Val{:method}` where `method`
can be: `"eval"`, `"interrupt"`, or `"exit"`. `f` is called as:

    f(Val(method), args..., request.msgid, request.params...; kwargs...)

A [`ProtocolException`](@ref) might be raised if the request is malformed.
"""
function dispatchonmessage(protocol::Protocol, f, args...; kwargs...)
    request = deserialize(protocol)
    return f(Val(Symbol(request.method)), args..., request.msgid, request.params...; kwargs...)
end
end
