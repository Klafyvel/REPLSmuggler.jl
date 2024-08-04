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
    repl = Base.active_repl
    current_line = line
    current_index = 1
    julia_prompt = repl.interface.modes[1] # Fragile, but assumed throughout REPL.jl
    current_mode = repl.mistate.current_mode
    if current_mode != julia_prompt
        REPL.transition(repl.mistate, julia_prompt)
        REPL.transition(repl.mistate, :reset)
    end
    s = repl.mistate.mode_state[repl.mistate.current_mode]
    while current_index < lastindex(value)
        node, new_index = JuliaSyntax.parsestmt(JuliaSyntax.GreenNode, value, current_index, ignore_errors = true, ignore_trivia = false)
        eval_string = value[current_index:prevind(value, new_index)]

        @debug "Printing eval string" eval_string
        REPL.LineEdit.edit_insert(s, strip(eval_string))
        REPL.LineEdit.commit_line(repl.mistate)

        expr = Meta.parseall(eval_string)
        # Now we put the correct file name and line number on the parsed
        # expression.
        @debug "expr before adjustment" expr
        for node in AbstractTrees.PostOrderDFS(expr)
            if hasproperty(node, :args)
                new_args = map(node.args) do c
                    if c isa LineNumberNode
                        LineNumberNode(current_line + c.line - 1, file)
                    else
                        c
                    end
                end
                node.args = new_args
            end
        end
        @debug "expr after adjustment" expr

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
        setglobal!(Base.MainInclude, :ans, first(repl_response))
        hide_output = REPL.ends_with_semicolon(eval_string)
        REPL.print_response(repl, repl_response, !hide_output, REPL.hascolor(repl))
        REPL.LineEdit.reset_state(s)
        REPL.LineEdit.refresh_line(s)

        current_index = new_index
        number_of_lines_evaluated = count('\n', eval_string)
        @debug "Here's what I did." number_of_lines_evaluated
        current_line = current_line + number_of_lines_evaluated
        if last(repl_response)
            @debug "Evaluation errored, stopping early." number_of_lines_evaluated
            break
        end
    end
    REPL.transition(repl.mistate, current_mode)
end
