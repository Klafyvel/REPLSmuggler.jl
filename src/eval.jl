import REPL
import JuliaSyntax
import AbstractTrees

struct StatementsIterator
    evalstring::AbstractString
end
Base.IteratorSize(::Type{StatementsIterator}) = Base.SizeUnknown()
Base.IteratorEltype(::Type{StatementsIterator}) = Base.HasEltype()
Base.eltype(::Type{StatementsIterator}) = String

function Base.iterate(s::StatementsIterator, current_index = 1)
    if current_index ≥ lastindex(s.evalstring)
        return nothing
    end
    _, new_index = JuliaSyntax.parsestmt(
        JuliaSyntax.GreenNode, s.evalstring, current_index,
        ignore_errors = true, ignore_trivia = false,
    )
    eval_string = s.evalstring[current_index:prevind(s.evalstring, new_index)]
    return (eval_string, new_index)
end

function stripblock(s)
    retlines = String[]
    commonlspace = typemax(Int) 
    for line in split(s,'\n')
        if isempty(strip(line))
            continue
        end
        lspace = length(line) - length(lstrip(line))  
        if lspace < commonlspace
            commonlspace = lspace
        end
    end
    for line in split(s,'\n')
        if isempty(strip(line))
            continue
        else
            push!(retlines,line[commonlspace+1:end])
        end
    end
    return join(retlines,'\n')
end

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
    julia_prompt = repl.interface.modes[1] # Fragile, but assumed throughout REPL.jl
    current_mode = repl.mistate.current_mode
    if current_mode != julia_prompt
        REPL.transition(repl.mistate, julia_prompt)
        REPL.transition(repl.mistate, :reset)
    end
    s = repl.mistate.mode_state[repl.mistate.current_mode]
    if session.sessionparams["evalbyblocks"]
        iterator = [value]
    else
        iterator = StatementsIterator(value)
    end
    for eval_string in iterator
        @debug "Printing eval string and commiting to history." eval_string
        REPL.LineEdit.edit_insert(s, stripblock(eval_string))
        REPL.LineEdit.commit_line(repl.mistate)
        REPL.history_reset_state(repl.mistate.current_mode.hist)

        expr = Meta.parseall(eval_string)
        # Now we put the correct file name and line number on the parsed
        # expression.
        renumber_evaluated_expression!(expr, current_line, file)
        @debug "expr after renumbering of lines" expr

        repl_response, error = evaluate_expression(expr, session.evaluatein)
        if !isnothing(error)
            put!(session.responsechannel, Protocols.Error(msgid, error.exception, error.stack))
        end

        @debug "Printing REPL response" repl_response
        hide_output = REPL.ends_with_semicolon(eval_string)
        REPL.print_response(repl, repl_response, !hide_output, REPL.hascolor(repl))
        println(REPL.terminal(repl))
        REPL.LineEdit.reset_state(s)
        REPL.LineEdit.refresh_line(s)

        number_of_lines_evaluated = count('\n', eval_string)
        current_line = current_line + number_of_lines_evaluated
        if last(repl_response)
            @debug "Evaluation errored, stopping early." number_of_lines_evaluated
            break
        end
    end
    REPL.transition(repl.mistate, current_mode)
end

function renumber_evaluated_expression!(expression, firstline, file)
    for node in AbstractTrees.PostOrderDFS(expression)
        if hasproperty(node, :args)
            new_args = map(node.args) do c
                if c isa LineNumberNode
                    LineNumberNode(firstline + c.line - 1, file)
                else
                    c
                end
            end
            node.args = new_args
        end
    end
end
function evaluate_expression(expression, evalmodule)
    response = nothing
    error = nothing
    try
        response = Base.eval(evalmodule, expression)
    catch exception
        response = current_exceptions()
        stack = stacktrace(Base.catch_backtrace())
        error = (; exception, stack)
    end
    setglobal!(Base.MainInclude, :ans, response)
    return response => !isnothing(error), error
end
