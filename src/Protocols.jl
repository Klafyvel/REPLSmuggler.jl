"""
Definition of the protocol used by REPLSmuggler.jl. It is based on MsgPack-RPC,
see here:
- https://github.com/msgpack/msgpack/blob/master/spec.md
- https://github.com/msgpack-rpc/msgpack-rpc/blob/master/spec.md

The actual (de)serialization from and to MsgPack objects is handled by MsgPack.jl
through a lightweight wrapper defined in MsgPackSerializer.jl.

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
- `interrupt`: Interrupt the current evaluation.
  No parameter.
- `exit`: Stop the current session.
  No parameter.

## Responses of the server.

The result field is a string of what would be printed in the REPL. It is empty if
an error occured. 

If an error occured, then the error field is a three-elements array structured as follow:
- `exception::String`: Name of the exception, *e.g.* `"ValueError"`,
- `exception_text::String`: Text, *e.g.* `"This value cannot be < 0."`,
- `stacktrace::Vector{Tuple{String, UInt32, String}}`: The stacktrace, with each 
  row being `(file, line, function)`.

## Notifications by the server.

Currently, the following notifications can be sent by the server. If a notification received by the client is unknown, it should simply be ignored without erroring.

- `handshake`: Sent at the begining of a session, mainly to ensure the correct
  version of the protocol is being used.
  Parameters:
  - `myname::String`: Name of the server. Will typically be `REPLSmuggler`, but
    could be replaced if other implementations of the protocol were to exist.
  - `version::String`: A [sementic versioning](https://semver.org/) version number
    telling the client which version of the protocol is being used by the server.

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

"Name of the protocol implementation."
const PROTOCOL_MAGIC = "REPLSmuggler"
"Protocol version."
const PROTOCOL_VERSION = v"0.1"

"MsgPackRPC message types."
const MsgType = UInt8
const REQUEST = 0x00
const RESPONSE = 0x01
const NOTIFICATION = 0x02

"Used internally to report protocol exceptions."
struct ProtocolException <: Exception
    msgid::Union{UInt32,Nothing}
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
        try
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
    Request(array[2:end]...)
end
astuple(r::Request) = (
    REQUEST,
    r.msgid,
    r.method,
    r.params
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
        e.stacktrace
    ),
    nothing
)
struct ResultResponse <: AbstractResponse
    msgid::UInt32
    result::String
end
astuple(r::ResultResponse) = (
    RESPONSE,
    r.msgid,
    nothing,
    r.result
)

"Represents a notification."
struct Notification <: AbstractMsgPackRPC
    method::String
    params::Vector
end
function Notification(array)
    if length(array) != 2
        throw(ProtocolException("Invalid notification of length $(length(array))."))
    end
    Notification(array...)
end
astuple(notification::Notification) = (
    NOTIFICATION,
    notification.method,
    notification.params
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
    Error(msgid, error, stackframe)
"""
function Error(msgid, error::T, stackframe) where {T}
    frames = [
        (frame.file, frame.line, frame.func)
        for frame in stackframe
    ]
    ErrorResponse(
        msgid,
        string(T), string(error), frames,
    )
end
function Error(exc::ProtocolException)
    ErrorResponse(
        something(exc.msgid, 0),
        "ProtocolException", exc.msg, [],
    )
end

"""
    Result(msgid, result)
"""
Result(msgid, result) = ResultResponse(
    msgid,
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
    f(Val(Symbol(request.method)), args..., request.msgid, request.params...; kwargs...)
end
end
