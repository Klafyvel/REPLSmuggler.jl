using REPLSmuggler
using InteractiveUtils

const Editor = REPLSmuggler.Editor

# Reset the module's globals so this testset is independent of any other state
# that might exist from previous tests in the same Julia session.
function reset_editor_state!()
    empty!(Editor.SESSION_SOCKETS)
    empty!(Editor.SESSION_ORDER)
    return
end

# `register` keys sessions by `objectid`, so any mutable instance works as a
# stand-in for a real `Server.Session` here.
make_fake_session() = Ref{Int}(0)

@testset "Editor.jl" begin
    @testset "register / current_socket / forget" begin
        reset_editor_state!()
        @test Editor.current_socket() == ""

        s1 = make_fake_session()
        Editor.register(s1, "/tmp/nvim-1.sock")
        @test Editor.current_socket() == "/tmp/nvim-1.sock"

        Editor.forget(s1)
        @test Editor.current_socket() == ""
    end

    @testset "most-recently-registered wins" begin
        reset_editor_state!()
        s1 = make_fake_session()
        s2 = make_fake_session()

        Editor.register(s1, "/tmp/a.sock")
        Editor.register(s2, "/tmp/b.sock")
        @test Editor.current_socket() == "/tmp/b.sock"

        # Re-registering s1 bumps it to the top of the order stack.
        Editor.register(s1, "/tmp/a.sock")
        @test Editor.current_socket() == "/tmp/a.sock"

        # Forgetting the top exposes the next one down.
        Editor.forget(s1)
        @test Editor.current_socket() == "/tmp/b.sock"

        Editor.forget(s2)
        @test Editor.current_socket() == ""
    end

    @testset "register with empty string forgets" begin
        reset_editor_state!()
        s = make_fake_session()
        Editor.register(s, "/tmp/x.sock")
        @test Editor.current_socket() == "/tmp/x.sock"

        # Empty socket is the documented way for a client to opt out.
        Editor.register(s, "")
        @test Editor.current_socket() == ""
        @test !haskey(Editor.SESSION_SOCKETS, objectid(s))
    end

    @testset "forget is safe for unknown sessions" begin
        reset_editor_state!()
        s = make_fake_session()
        # Shouldn't throw even though `s` was never registered.
        Editor.forget(s)
        @test Editor.current_socket() == ""
    end

    @testset "smuggler_edit Cmd construction" begin
        reset_editor_state!()

        # No session → fall back to a normal local nvim invocation.
        @test Editor.smuggler_edit(`nvim`, "foo.jl", 42) == `nvim +42 foo.jl`
        @test Editor.smuggler_edit(`nvim`, "foo.jl", 0) == `nvim foo.jl`

        # With a session → drive the remote nvim via --remote-expr / :tabedit.
        # `--remote-tab*` swallows `+cmd` as a filename (see comment in
        # Editor.smuggler_edit), so this must go through fnameescape.
        s = make_fake_session()
        Editor.register(s, "/tmp/remote.sock")
        @test Editor.smuggler_edit(`nvim`, "foo.jl", 42) == `nvim --server /tmp/remote.sock --remote-expr "execute('tabedit +42 ' . fnameescape('foo.jl'))"`
        @test Editor.smuggler_edit(`nvim`, "foo.jl", 0) == `nvim --server /tmp/remote.sock --remote-expr "execute('tabedit ' . fnameescape('foo.jl'))"`

        # Paths with single quotes are embedded via Vimscript's '' escape.
        @test Editor.smuggler_edit(`nvim`, "weird's.jl", 7) == `nvim --server /tmp/remote.sock --remote-expr "execute('tabedit +7 ' . fnameescape('weird''s.jl'))"`
    end

    @testset "install! is idempotent" begin
        # Calling install! repeatedly must not register multiple callbacks with
        # InteractiveUtils — otherwise every `@edit` call would invoke our
        # action N times.
        Editor.install!()
        before = length(InteractiveUtils.EDITOR_CALLBACKS)
        Editor.install!()
        Editor.install!()
        @test length(InteractiveUtils.EDITOR_CALLBACKS) == before
        @test Editor.REGISTERED[]
    end
end
