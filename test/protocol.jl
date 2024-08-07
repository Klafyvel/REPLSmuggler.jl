using REPLSmuggler.Protocols

@testset "Protocols.jl" begin
    TestSerializer = :TestSerializer
    function Protocols.serialize(protocol::Protocols.Protocol{TestSerializer}, msg::Protocols.AbstractMsgPackRPC)
        io = protocol.io
        msg_tuple = Protocols.astuple(msg)
        put!(io, msg_tuple)
    end

    function test_response(response, model)
        ret = true
        for (r, m) in zip(response, model)
            ret = ret && typeof(r) == typeof(m)
            ret || break
            if r isa AbstractArray || r isa Tuple
                ret = ret && test_response(r, m)
            else
                ret = ret && (r == m)
            end
            ret || break
        end
        ret
    end

    chan = Channel(Inf)
    protocol = Protocols.Protocol(TestSerializer, chan)
    @test protocol isa Protocols.Protocol{TestSerializer}

    # Handshake
    Protocols.serialize(protocol, Protocols.Handshake())
    @test isready(chan)
    response = take!(chan)
    @test test_response(
        response, (
            Protocols.NOTIFICATION,
            "handshake",
            [Protocols.PROTOCOL_MAGIC, string(Protocols.PROTOCOL_VERSION)],
        ),
    )

    # Error
    Protocols.serialize(
        protocol, Protocols.Error(
            1, ErrorException("Foo"), [
                (file = "foo.jl", line = 1, func = "foo()"),
                (file = "bar.jl", line = 2, func = "bar()"),
            ],
        ),
    )
    @test isready(chan)
    response = take!(chan)
    @test test_response(
        response, (
            Protocols.RESPONSE,
            1,
            (
                "ErrorException", "ErrorException: Foo",
                [
                    ("foo.jl", 1, "foo()"),
                    ("bar.jl", 2, "bar()"),
                ],
            ),
            nothing,
        ),
    )

    # Result
    Protocols.serialize(protocol, Protocols.Result(1, 1, "foo"))
    @test isready(chan)
    response = take!(chan)
    @test test_response(
        response, (
            Protocols.RESPONSE,
            UInt32(1),
            nothing,
            (UInt32(1), "foo"),
        ),
    )

    # Deserialize
    function Protocols.deserialize(protocol::Protocols.Protocol{TestSerializer})
        io = protocol.io
        array = take!(io)
        Protocols.Request(array)
    end
    evalrequest = [Protocols.REQUEST, UInt32(1), "eval", ["foo.jl", UInt32(1), "a=1"]]
    interruptrequest = [Protocols.REQUEST, UInt32(2), "interrupt", []]
    exitrequest = [Protocols.REQUEST, UInt32(2), "exit", []]
    invalidrequest = [Protocols.REQUEST]

    put!(chan, evalrequest)
    request = Protocols.deserialize(protocol)
    @test request.msgid == 1
    @test request.method == "eval"
    @test request.params == ["foo.jl", UInt32(1), "a=1"]

    put!(chan, interruptrequest)
    request = Protocols.deserialize(protocol)
    @test request.msgid == 2
    @test request.method == "interrupt"
    @test request.params == []

    put!(chan, exitrequest)
    request = Protocols.deserialize(protocol)
    @test request.msgid == 2
    @test request.method == "exit"
    @test request.params == []

    put!(chan, invalidrequest)
    @test_throws Protocols.ProtocolException Protocols.deserialize(protocol)

    # Dispatch
    dispatched = Channel(Inf)
    function dispatch(args...)
        put!(dispatched, args)
    end

    put!(chan, evalrequest)
    Protocols.dispatchonmessage(protocol, dispatch, "foo")
    @test isready(dispatched)
    array = take!(dispatched)
    @test array == (Val(Symbol("eval")), "foo", UInt32(1), "foo.jl", UInt32(1), "a=1")

end
