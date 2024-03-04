import REPL
import JuliaSyntax
import AbstractTrees

"""
    evaluate_entry(session, msgid, file, line, value)

Evaluate the code in `value` in the context of the given `session`, replacing the
context of the code with `file` and `line`. If an error occurs, it will put a 
using Base: JuliaSyntax
[`Protocols.Error`](@ref) to the outgoing channel of the session.
"""
function evaluate_entry(session, msgid, file, line, value)
    @debug "Evaluating entry" session file line value
    current_line = line
    current_index = 1
    while current_index < lastindex(value)
        node, new_index = JuliaSyntax.parsestmt(JuliaSyntax.GreenNode, value, current_index) 
        eval_string = value[current_index:new_index-1]
        expr = Meta.parse(eval_string, raise=false)
        # Now we put the correct file name and line number on the parsed
        # expression.
        for node in AbstractTrees.PostOrderDFS(expr)
            if hasproperty(node, :args)
                new_args = map(node.args) do c
                    if c isa LineNumberNode
                        LineNumberNode(current_line+c.line-1, file)
                    else
                        c
                    end
                end
                node.args = new_args
            end
        end

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
        hide_output = REPL.ends_with_semicolon(eval_string)
        REPL.print_response(repl, repl_response, !hide_output, REPL.hascolor(repl))

        current_index = new_index
        current_line = current_line + countlines(IOBuffer(eval_string))
    end
end

