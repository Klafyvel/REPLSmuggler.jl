[pkgeval-img]: https://juliaci.github.io/NanosoldierReports/pkgeval_badges/R/REPLSmuggler.svg
[pkgeval-url]: https://juliaci.github.io/NanosoldierReports/pkgeval_badges/R/REPLSmuggler.html
<div align="center">

# REPLSmuggler 

*Well, listen up, folks! [`REPLSmuggler.jl`](https://github.com/klafyvel/REPLSmuggler.jl) just slipped into your cozy REPL like a shadow in the night.*

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://klafyvel.github.io/REPLSmuggler.jl/stable/) [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://klafyvel.github.io/REPLSmuggler.jl/dev/) [![Build Status](https://github.com/klafyvel/REPLSmuggler.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/klafyvel/REPLSmuggler.jl/actions/workflows/CI.yml?query=branch%3Amain) [![Coverage](https://codecov.io/gh/klafyvel/REPLSmuggler.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/klafyvel/REPLSmuggler.jl) [![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl) [![code style: runic](https://img.shields.io/badge/code_style-%E1%9A%B1%E1%9A%A2%E1%9A%BE%E1%9B%81%E1%9A%B2-black)](https://github.com/fredrikekre/Runic.jl) [![PkgEval][pkgeval-img]][pkgeval-url]
---

</div>


## Summary

REPLSmuggler is meant to evaluate code coming from various clients in your REPL. The main goal is for an editor to send a bunch of lines of code with some metadata giving the name of the file and the line. `REPLSmuggler` will evaluate the code and send back the return value. If an error is raised, it will send the traceback to the client.

## Usage

For now functionalities are quite basic:

```julia
using REPLSmuggler
smuggle()
```

## See also

Have a look at [the companion plugin for NeoVim](https://github.com/klafyvel/nvim-smuggler).
