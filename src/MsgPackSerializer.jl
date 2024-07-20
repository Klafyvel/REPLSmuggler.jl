"""
The default serializer for REPLSmuggler.jl
"""
module MsgPackSerializer

using MsgPack
using REPLSmuggler
using REPLSmuggler.Protocols

function Protocols.serialize(protocol::Protocols.Protocol{MsgPack}, msg::Protocols.AbstractMsgPackRPC)
    io = protocol.io
    pack(io, msg)
end

function Protocols.deserialize(protocol::Protocols.Protocol{MsgPack})
    io = protocol.io
    unpack(io, Protocols.Request)
end

MsgPack.msgpack_type(::Type{Protocols.MsgType}) = MsgPack.IntegerType()
MsgPack.to_msgpack(::MsgPack.StringType, key::Protocols.MsgType) = UInt8(key)
MsgPack.from_msgpack(::Type{Protocols.MsgType}, msg::Integer) = Protocols.MsgType(msg)

MsgPack.msgpack_type(::Type{T}) where {T <: Protocols.AbstractMsgPackRPC} = MsgPack.ArrayType()
MsgPack.to_msgpack(::MsgPack.ArrayType, msg::Protocols.AbstractMsgPackRPC) = Protocols.astuple(msg)
MsgPack.from_msgpack(::Type{T}, array::AbstractArray) where {T <: Protocols.AbstractMsgPackRPC} = T(array)


end
