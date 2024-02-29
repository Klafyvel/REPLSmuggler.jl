using REPLSmuggler
using Documenter

DocMeta.setdocmeta!(REPLSmuggler, :DocTestSetup, :(using REPLSmuggler); recursive=true)

makedocs(;
    modules=[REPLSmuggler],
    authors="Hugo Levy-Falk <hugo@klafyvel.me> and contributors",
    repo="https://github.com/Klafyvel/REPLSmuggler.jl/blob/{commit}{path}#{line}",
    sitename="REPLSmuggler.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://klafyvel.github.io/REPLSmuggler.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/Klafyvel/REPLSmuggler.jl",
    devbranch="main",
)
