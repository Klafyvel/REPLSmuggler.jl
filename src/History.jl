"""
Smuggle REPLSmuggler's history within REPL's history. This is probably fragile,
as the code is based on undocumented REPL.jl code.
"""
module History
using REPL
"""
Return the currently in-use `REPL.REPLHistoryProvider`.
"""
function get_history_provider()
  repl = Base.active_repl
  state = REPL.LineEdit.state(repl.mistate)
  REPL.LineEdit.mode(state).hist
end
"""
Directly stolen and slightly modified from `REPL.add_history`.
"""
function add_history(hist::REPL.REPLHistoryProvider, str::AbstractString)
    striped_str = rstrip(String(take!(copy(IOBuffer(str)))))
    @debug "Adding input to history." striped_str
    isempty(strip(striped_str)) && return
    mode = :julia
    !isempty(hist.history) &&
        isequal(mode, hist.modes[end]) && striped_str == hist.history[end] && return
    push!(hist.modes, mode)
    push!(hist.history, striped_str)
    @debug "hist is now" hist.history hist.modes
    hist.history_file === nothing && return
    entry = """
    # time: $(Libc.strftime("%Y-%m-%d %H:%M:%S %Z", time()))
    # mode: $mode
    $(replace(striped_str, r"^"ms => "\t"))
    """
    # TODO: write-lock history file
    try
        seekend(hist.history_file)
    catch err
        (err isa SystemError) || rethrow()
        # File handle might get stale after a while, especially under network file systems
        # If this doesn't fix it (e.g. when file is deleted), we'll end up rethrowing anyway
        REPL.hist_open_file(hist)
    end
    print(hist.history_file, entry)
    flush(hist.history_file)
    nothing
end
add_history(session, str) = add_history(session.history, str)
end
