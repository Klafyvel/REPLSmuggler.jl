module REPLSmuggler

using BaseDirs

export smuggle

const PROJECT = BaseDirs.Project("REPLSmuggler")

# Nouns related to smuggling
const SMUGGLING_NOUNS = ["contraband", "clandestine_operation", "smuggler", "bootlegging", "illicit_trade", "covert_transport", "underworld", "black_market", "contraband_goods", "smuggling_route"]

# Adjectives related to smuggling
const SMUGGLING_ADJECTIVES = ["covert", "stealthy", "illicit", "underground", "secretive", "clandestine", "smuggled", "contraband", "sneaky", "illegitimate"]

function yer_name(;joinpath=true)
    filename = rand(SMUGGLING_ADJECTIVES) * "_" * rand(SMUGGLING_NOUNS)
    if joinpath
        BaseDirs.User.runtime(PROJECT, filename)
    else
        filename
    end
end

include("Protocols.jl")
using .Protocols

include("Server.jl")
using .Server


CURRENT_SMUGGLER = nothing
"""
    smuggle(smuggler, args...; kwargs...)
You can start smuggling.
"""
function smuggle(T, U)
    global CURRENT_SMUGGLER
    CURRENT_SMUGGLER = Smuggler(T(), U, Set{Session}())
    serve_repl(CURRENT_SMUGGLER)
end

include("SocketSmugglers.jl")
using .SocketSmugglers
smuggle(U) = smuggle(SocketSmuggler, U)

include("MsgPackSerializer.jl")
using MsgPack
using .MsgPackSerializer
smuggle() = smuggle(SocketSmuggler, MsgPack)

end
