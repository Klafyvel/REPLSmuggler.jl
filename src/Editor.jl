"""
Bridge between Julia's `InteractiveUtils.edit` / `@edit` and connected
REPLSmuggler clients.

When a client opts in by sending a non-empty `editorpattern` setting via the
`configure` request, the server installs an `InteractiveUtils` editor callback
for that pattern. When `EDITOR` matches the pattern, an `edit` notification is
sent back over the existing session channel instead of spawning a nested
editor in the REPL's terminal — leaving each client free to open the file in
whatever way is idiomatic for its host editor.

The integration is fully editor-agnostic on the server side: REPLSmuggler does
not call into any editor binary directly. The pattern (and the open-on-edit
behaviour) is entirely the client's responsibility.
"""
module Editor

using InteractiveUtils

using ..Protocols

"Stack of sessions that have registered interest; most recent wins on `@edit`."
const SESSION_STACK = Any[]

"Set of patterns already installed with `InteractiveUtils.define_editor`."
const INSTALLED_PATTERNS = Set{String}()

# `true` exits 0 on Unix; on Windows the `cd.` builtin is a portable no-op.
const _NOOP_CMD = Sys.iswindows() ? `cmd /c cd.` : `true`

"""
    register(session)

Record that `session` wants `@edit` routed back through it. Idempotent;
re-registering bumps the session to the top of the stack so the most recently
configured session wins when multiple are connected.
"""
function register(session)
    filter!(s -> !(s === session), SESSION_STACK)
    push!(SESSION_STACK, session)
    return
end

"""
    forget(session)

Drop `session` from the stack (e.g. on disconnect). Safe to call for sessions
that were never registered.
"""
function forget(session)
    filter!(s -> !(s === session), SESSION_STACK)
    return
end

"Return the most-recently-registered live session, or `nothing` if none."
function current_session()
    while !isempty(SESSION_STACK)
        s = last(SESSION_STACK)
        if isopen(s)
            return s
        end
        pop!(SESSION_STACK)
    end
    return nothing
end

"""
    smuggler_edit(cmd, path, line)

Editor callback registered via `InteractiveUtils.define_editor`. When a
session is registered, send an `edit` notification on its response channel
and return a no-op `Cmd` so Julia does not also spawn the user's `EDITOR`.
With no session registered, fall back to the conventional `cmd +line path`
form so the user's `EDITOR` still works.
"""
function smuggler_edit(cmd, path, line)
    session = current_session()
    if session === nothing
        return line > 0 ? `$cmd +$line $path` : `$cmd $path`
    end
    notification = Protocols.EditRequest(path, line)
    try
        put!(session.responsechannel, notification)
    catch exc
        # Session may have been closed between current_session() and put!;
        # fall through to a local editor invocation rather than erroring out
        # of the user's `@edit` call.
        if exc isa InvalidStateException
            forget(session)
            return line > 0 ? `$cmd +$line $path` : `$cmd $path`
        end
        rethrow()
    end
    return _NOOP_CMD
end

"""
    install!(pattern::AbstractString)

Register `smuggler_edit` with `InteractiveUtils.define_editor` for the given
editor name `pattern` (anchored anywhere in the user's `EDITOR`). Idempotent:
the same `pattern` is only installed once per Julia session.
"""
function install!(pattern::AbstractString)
    key = String(pattern)
    key in INSTALLED_PATTERNS && return
    InteractiveUtils.define_editor(smuggler_edit, Regex(key); wait = false)
    push!(INSTALLED_PATTERNS, key)
    return
end

end
