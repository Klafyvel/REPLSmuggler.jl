using REPL

include("./FakeSessions.jl")
using .FakeSessions

# Because evaluation is tied to the REPL, we need a REPL to do the evaluation.
# I'm relying heavily on Base.REPL tests. (https://github.com/JuliaLang/julia/blob/master/stdlib/REPL/test/repl.jl)

# Fragile, at the time of writing, the julia prompt is printed as :
# 1. clear until begining of line, print `julia> `, carriage return, then move
# 7 characters to the right.
JULIA_PROMPT_OVERRIDE = "\r\e[0Kjulia> \r\e[7C"

const BASE_TEST_PATH = joinpath(Sys.BINDIR, "..", "share", "julia", "test")
isdefined(Main, :FakePTYs) || @eval Main include(joinpath($(BASE_TEST_PATH), "testhelpers", "FakePTYs.jl"))
import .Main.FakePTYs: with_fake_pty

include("FakeTerminals.jl")
import .FakeTerminals.FakeTerminal

function kill_timer(delay)
    # Give ourselves a generous timer here, just to prevent
    # this causing e.g. a CI hang when there's something unexpected in the output.
    # This is really messy and leaves the process in an undefined state.
    # the proper and correct way to do this in real code would be to destroy the
    # IO handles: `close(stdout_read); close(stdin_write)`
    test_task = current_task()
    function kill_test(t)
        # **DON'T COPY ME.**
        # The correct way to handle timeouts is to close the handle:
        # e.g. `close(stdout_read); close(stdin_write)`
        test_task.queue === nothing || Base.list_deletefirst!(test_task.queue, test_task)
        schedule(test_task, "hard kill repl test"; error = true)
        return print(stderr, "WARNING: attempting hard kill of repl test after exceeding timeout\n")
    end
    return Timer(kill_test, delay)
end

function fake_repl(@nospecialize(f); options::REPL.Options = REPL.Options(confirm_exit = false))
    # Use pipes so we can easily do blocking reads
    # In the future if we want we can add a test that the right object
    # gets displayed by intercepting the display
    input = Pipe()
    output = Pipe()
    err = Pipe()
    Base.link_pipe!(input, reader_supports_async = true, writer_supports_async = true)
    Base.link_pipe!(output, reader_supports_async = true, writer_supports_async = true)
    Base.link_pipe!(err, reader_supports_async = true, writer_supports_async = true)

    repl = REPL.LineEditREPL(FakeTerminal(input.out, output.in, err.in, options.hascolor), options.hascolor)
    repl.options = options

    hard_kill = kill_timer(900) # Your debugging session starts now. You have 15 minutes. Go.
    f(input.in, output.out, err.out, repl)
    t = @async begin
        close(input.in)
        close(output.in)
        close(err.in)
    end
    @test read(err.out, String) == ""
    #display(read(output.out, String))
    Base.wait(t)
    close(hard_kill)
    return nothing
end

# Writing ^C to the repl will cause sigint, so let's not die on that
Base.exit_on_sigint(false)

function consume_responses(responsechannel, result, mime = MIME("text/plain"); file, line, msgid)
    response = take!(responsechannel)
    @test response isa REPLSmuggler.Protocols.ResultResponse
    @test response.msgid == msgid
    @test response.line == line
    @test response.mime == mime
    return @test response.result == string(result)
end
function consume_responses(responsechannel, results::Vector; file, line, msgid)
    for (producerline, result, mime) in results
        consume_responses(responsechannel, result, mime; file, msgid, line = producerline)
    end
    return
end
function consume_responses(responsechannel, results::Nothing; file, line, msgid)
end
function test_ans_value(result)
    return @test getglobal(Base.MainInclude, :ans) == result
end
function test_ans_value(results::Vector)
    result = last(results)[2]
    return test_ans_value(result)
end
reg_cmd = r"(\r\e\[0Kjulia>(.|\n)+)?\r\e\[0Kjulia> (\r\e\[7C)+(?<cmd>(.|\n)+)\r\e\[[0-9]+C\n"
function test_printed_result(stdout_read, result; test_print_results, collect_print_results)
    # We want to check that the command has been printed, and then the result.
    # Because of the inner workings of the REPL and of REPLSmuggler, this is
    # actually printed twice: first when we "insert" the command in the prompt,
    # then when we print it (after the `julia>` prompt has been printed. The
    # first print is invisible, and so it does not really make sense to test on
    # it. We are interested in the second one.
    r = readuntil(stdout_read, "C\n", keep = true)
    match_cmd_printed = match(reg_cmd, r)
    @test !isnothing(match_cmd_printed)
    if !isnothing(match_cmd_printed)
        printed_command = match_cmd_printed[:cmd]
    else
        printed_command = ""
        @info "Failed to match command." r
    end
    if collect_print_results
        # Then the result, which is followed by two new lines, so that's easy.
        printed_result = rstrip(String(readuntil(stdout_read, "\n\n")))
        if test_print_results
            @test printed_result == string(result)
        end
    else
        printed_result = ""
    end
    # Consume the julia prompt print
    r = readuntil(stdout_read, JULIA_PROMPT_OVERRIDE)
    return printed_command, printed_result
end
function test_printed_result(stdout_read, results::Vector; test_print_results, collect_print_results)
    printed = []
    for (_, result, _) in results
        printed_command, printed_result = test_printed_result(stdout_read, result; test_print_results, collect_print_results)
        push!(printed, (printed_command, printed_result))
    end
    return printed
end

function eval_test_cmd(stdout_read, repl, session, cmd, result; file = "test.jl", line = 1, msgid = 0x01, test_print_results = true, test_ans = true, collect_print_results = true)
    # First consume everything that might be left from previous code.
    # readavailable(stdout_read)
    # Evaluate the command
    REPLSmuggler.Server.evaluate_entry(session, msgid, file, line, cmd, repl)
    # Now we check what happened. First, take the response.
    consume_responses(session.responsechannel, result; file, line, msgid)
    # Test that `ans` has been set correctly
    if test_ans
        test_ans_value(result)
    end
    # Test what's been printed
    res = test_printed_result(stdout_read, result; test_print_results, collect_print_results)
    flushed = String(readavailable(stdout_read))
    return res
end

@testset "Eval tests" begin
    fake_repl(options = REPL.Options(confirm_exit = false, hascolor = false)) do stdin_write, stdout_read, stderr_read, repl
        repl.specialdisplay = REPL.REPLDisplay(repl)
        repl.history_file = false

        # Don't expect more than 256 responses!
        responsechannel = Channel(256)
        session = FakeSessions.FakeSession(Main, deepcopy(REPLSmuggler.Server.DEFAULT_SESSION_DICT), responsechannel)

        repltask = @async begin
            REPL.run_repl(repl)
        end
        # Give some time to the REPL to be initialized
        readuntil(stdout_read, JULIA_PROMPT_OVERRIDE)
        @info "REPL seems ready."

        # Simplest eval test, if this breaks the package has no purpose anymore :D
        # This can also be used as a template to check the output of evaluations.
        printed = eval_test_cmd(stdout_read, repl, session, "1+1", 2)
        printed_cmd = printed[1]
        @test printed_cmd == "1+1"
        # Test multiple statements (eval by statements)
        printed = eval_test_cmd(
            stdout_read, repl, session, "1+1\n2+2\n3+3", [
                (1, 2, MIME("text/plain")),
                (2, 4, MIME("text/plain")),
                (3, 6, MIME("text/plain")),
            ],
        )
        for i in 1:3
            printed_cmd = printed[i][1]
            @test printed_cmd == "$i+$i"
        end
        # Test multiple statements (eval by blocks)
        session.sessionparams["evalbyblocks"] = true
        printed = eval_test_cmd(
            stdout_read, repl, session, "1+1\n2+2\n3+3", [
                (3, 6, MIME("text/plain")),
            ], test_print_results = false,
        )
        printed_cmd = printed[1][1]
        @test printed_cmd == "1+1\n\r\e[7C2+2\n\r\e[7C3+3"
        printed_result = printed[1][2]
        @test printed_result == "6"
        session.sessionparams["evalbyblocks"] = false

        # Variables with UTF-8 names
        cmd = "ħ = 1/2π"
        printed = eval_test_cmd(stdout_read, repl, session, cmd, 0.15915494309189535)
        printed_cmd = printed[1]
        @test printed_cmd == cmd

        # Command that ends with a `;`
        cmd = "1+1+1;"
        printed = eval_test_cmd(stdout_read, repl, session, cmd, nothing, test_print_results = false, test_ans = false, collect_print_results = false)
        printed_cmd = printed[1]
        printed_result = printed[2]
        @test printed_cmd == cmd
        @test printed_result == ""

        # Weird indentation, and multiline.
        cmd = """
            function bad_bad_bad()
              error("hey!")
            end
        """
        printed = eval_test_cmd(stdout_read, repl, session, cmd, nothing, test_print_results = false, test_ans = false)
        printed_cmd = printed[1]
        printed_result = printed[2]
        for line in split(printed_cmd, "\n")[2:end]
            @test startswith(line, "\r\e[7C")
        end
        @test printed_result == "bad_bad_bad (generic function with 1 method)"

        # An error
        cmd = "error(\"bad bad\")"
        printed = eval_test_cmd(stdout_read, repl, session, cmd, nothing, test_print_results = false, test_ans = false)
        printed_cmd = printed[1]
        printed_result = printed[2]
        @test printed_cmd == cmd
        @test startswith(printed_result, "ERROR: bad bad\nStacktrace:\n  [1] error(s::String)")

        # Delete line (^U) and close REPL (^D)
        write(stdin_write, "\x15\x04")
        Base.wait(repltask)

        nothing
    end
end
