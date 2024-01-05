using REPLSmuggler
using Test
using Aqua

@testset "REPLSmuggler.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(REPLSmuggler)
    end
    # Write your tests here.
end
