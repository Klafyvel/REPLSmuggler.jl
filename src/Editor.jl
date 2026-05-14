"""
Integration of Julia's `@edit` / `InteractiveUtils.edit` with a connected
nvim-smuggler client.

When a client (typically Neovim) ships an `editorsocket` setting via the
`configure` request, REPLSmuggler can drive that running editor to open the
file at the right line, instead of spawning a nested editor in the Julia
REPL's terminal.

The integration is opt-in (the setting defaults to ""), and is non-breaking:
older Julia servers silently drop unknown settings keys.
"""
module Editor

using InteractiveUtils

"Maps a session id (objectid of the Session) to its editor socket path."
const SESSION_SOCKETS = Dict{UInt, String}()

"Stack of session ids in registration order; most recent wins on `@edit`."
const SESSION_ORDER = UInt[]

"Set to `true` after the first call to `register`."
const REGISTERED = Ref(false)

"""
    register(session, socket::AbstractString)

Record that `session` is being driven by an editor listening on `socket`.
Idempotent. Installs the `define_editor` hook on first call.
"""
function register(session, socket::AbstractString)
    id = objectid(session)
    if isempty(socket)
        forget(session)
        return
    end
    SESSION_SOCKETS[id] = String(socket)
    # Move id to top of order stack (most recent wins).
    filter!(!=(id), SESSION_ORDER)
    push!(SESSION_ORDER, id)
    install!()
    return
end

"""
    forget(session)

Drop any editor socket associated with `session` (e.g. on disconnect).
"""
function forget(session)
    id = objectid(session)
    delete!(SESSION_SOCKETS, id)
    filter!(!=(id), SESSION_ORDER)
    return
end

"Return the most-recently-registered editor socket, or an empty string if none."
function current_socket()
    while !isempty(SESSION_ORDER)
        id = last(SESSION_ORDER)
        sock = get(SESSION_SOCKETS, id, "")
        if !isempty(sock)
            return sock
        end
        pop!(SESSION_ORDER)
    end
    return ""
end

"""
    smuggler_edit(cmd, path, line)

Editor action registered with `InteractiveUtils.define_editor`. When a smuggler
session has provided an `editorsocket`, route the edit to that running nvim
via `--remote-expr`, driving `:tabedit` with `fnameescape` so paths with
spaces or special characters work. Falls back to a normal nvim invocation
when no socket is configured.

`--remote-tab*` does not honor the `+cmd` syntax (it treats `+42` as a file
name), so we cannot use it to jump to a line — `--remote-expr` is required.
"""
function smuggler_edit(cmd, path, line)
    sock = current_socket()
    if isempty(sock)
        return line > 0 ? `$cmd +$line $path` : `$cmd $path`
    end
    # Embed `path` in a Vimscript single-quoted string literal — Vim escapes
    # single quotes by doubling them.
    escaped_path = replace(path, "'" => "''")
    expr = if line > 0
        "execute('tabedit +$(line) ' . fnameescape('$(escaped_path)'))"
    else
        "execute('tabedit ' . fnameescape('$(escaped_path)'))"
    end
    return `nvim --server $sock --remote-expr $expr`
end

"Register `smuggler_edit` with InteractiveUtils on first call. Idempotent."
function install!()
    REGISTERED[] && return
    InteractiveUtils.define_editor(smuggler_edit, r"nvim"; wait = false)
    REGISTERED[] = true
    return
end

end
