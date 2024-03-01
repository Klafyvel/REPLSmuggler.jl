```@meta
CurrentModule = REPLSmuggler
```

# REPLSmuggler

Documentation for [REPLSmuggler](https://github.com/klafyvel/REPLSmuggler.jl).

REPLSmuggler is meant to evaluate code coming from various clients in your REPL. The main goal is for an editor to send a bunch of lines of code with some metadata giving the name of the file and the line. `REPLSmuggler` will evaluate the code and send back the return value. If an error is raised, it will send the traceback to the client.

See also the [the companion plugin for NeoVim](https://github.com/klafyvel/nvim-smuggler).

```@contents
Depth=5
```

## Usage

Using REPLSmuggler is as simple as:
```julia-repl
julia> using REPLSmugglers
julia> smuggle()
[ Info: Ahoy, now smuggling from socket /run/user/1000/julia/replsmuggler/contraband_clandestine_operation.
Task (runnable) @0x0000753a784c6bd0
```

## Internals

### REPLSmuggler

```@autodocs
Modules = [REPLSmuggler]
```

### Protocol

```@autodocs
Modules = [REPLSmuggler.Protocols]
```

### Server

```@autodocs
Modules = [REPLSmuggler.Server]
```

### Default implementation

```@autodocs
Modules = [REPLSmuggler.MsgPackSerializer, REPLSmuggler.SocketSmugglers]
```

## Index

```@index
```

