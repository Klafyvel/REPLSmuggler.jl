import REPL

"""
    evaluate_entry(session, msgid, file, line, value)

Evaluate the code in `value` in the context of the given `session`, replacing the
context of the code with `file` and `line`. If an error occurs, it will put a 
[`Protocols.Error`](@ref) to the outgoing channel of the session.
"""
function evaluate_entry(session, msgid, file, line, value)
    @debug "Evaluating entry" session file line value
    expr = Meta.parseall(value)
    @debug "Expression before correction" expr
    # Now we put the correct file name and line number on the parsed
    # expression.
    for node in PostOrderDFS(expr)
        if hasproperty(node, :args)
            new_args = map(node.args) do c
                if c isa LineNumberNode
                    LineNumberNode(line+c.line-1, file)
                else
                    c
                end
            end
            node.args = new_args
        end
    end
    @debug "Expression before evaluation" expr
    local repl_response
    try
        repl_response = Pair{Any, Bool}(Base.eval(session.evaluatein, expr), false)
    catch exc
        repl_response = Pair{Any, Bool}(current_exceptions(), true)
        @debug "Got an error" exc stacktrace(Base.catch_backtrace())
        stack = stacktrace(Base.catch_backtrace())
        put!(session.responsechannel, Protocols.Error(msgid, exc, stack))
    end
    @debug "Printing REPL response" repl_response
    repl = Base.active_repl
    hide_output = REPL.ends_with_semicolon(value)
    REPL.print_response(repl, repl_response, !hide_output, REPL.hascolor(repl))
end

