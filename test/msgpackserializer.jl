using REPLSmuggler.Protocols
using MsgPack

@testset "MsgPackSerializer.jl" begin
    io = IOBuffer()
    protocol = Protocols.Protocol(MsgPack, io)

    function test_msg(msg, expected_array)
        if bytesavailable(io) > 0
            take!(io)
        end
        Protocols.serialize(protocol, msg)
        res = take!(io)
        expected_res = pack(expected_array)
        @test res == expected_res
    end

    @testset "Serialization" begin
        msg = Protocols.Handshake()
        expected_array = [Protocols.NOTIFICATION, "handshake", [Protocols.PROTOCOL_MAGIC, string(Protocols.PROTOCOL_VERSION)]]
        @testset "Handshake" test_msg(msg, expected_array)

        msg = Protocols.Request(0x01, "eval", ["foo.jl", UInt32(1), "a=1"])
        expected_array = [Protocols.REQUEST, 0x01, "eval", ["foo.jl", UInt32(1), "a=1"]]
        @testset "Eval request" test_msg(msg, expected_array)

        msg = Protocols.Error(
            1, ErrorException("Foo"), [
                (file = "foo.jl", line = 1, func = "foo()"),
                (file = "bar.jl", line = 2, func = "bar()"),
            ],
        )
        expected_array = [Protocols.RESPONSE, 0x01, ["ErrorException", "ErrorException: Foo", [("foo.jl", 1, "foo()"), ("bar.jl", 2, "bar()")]], nothing]
        @testset "Error" test_msg(msg, expected_array)

        msg = Protocols.Result(1, "foo")
        expected_array = [Protocols.RESPONSE, 0x01, nothing, "foo"]
        @testset "Result" test_msg(msg, expected_array)
    end

    @testset "Deserialization" begin
        Protocols.deserialize

    end

end
