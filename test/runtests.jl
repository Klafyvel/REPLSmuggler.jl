using REPLSmuggler
using Test
using Aqua

@testset "REPLSmuggler.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(REPLSmuggler)
    end
    include("protocol.jl")
    include("msgpackserializer.jl")
    include("evaltests.jl")
end
