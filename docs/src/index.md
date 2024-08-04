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

You are then able to send code and get notified when an error happens.

`smuggle` can also be used the other way around, to directly send diagnostics
to your editor. For example, if your editor has smuggled the following function:
```julia
function bad_bad_bad()
  error("hey!")
end
```
You can send back diagnostics to the editor directly from the REPL by catching 
an exception.
```julia-repl
julia> try
       bad_bad_bad()
catch exc
       smuggle(exc)
end
```

You can even send directly diagnostics, without looking for code that has actually
been sent by the editor:
```julia-repl
julia> smuggle("hey", "foo", "$(pwd())/test.jl", 11, "none")
```

There's also an extension to work with [JET](https://github.com/aviatesk/JET.jl)'s 
reports. Say you smuggled the following functions:
```julia
function foo(s0)
  a = []
  for s in split(s0)
    push!(a, bar(s))
  end
  return sum(a)
end
bar(s::String) = parse(Int, s)
```
You can smuggle back to the editor JET's report as follow:
```julia-repl
julia> smuggle(@report_call foo("1 2 3"))
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

