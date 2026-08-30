using REPLSmuggler
using InteractiveUtils

const Editor = REPLSmuggler.Editor

# Minimal stand-in for a `Server.Session`: `current_session` needs `isopen`,
# and `smuggler_edit` needs `responsechannel`. Mutating `open` flips it closed.
mutable struct FakeSession
    responsechannel::Channel
    open::Bool
end
make_fake_session() = FakeSession(Channel(8), true)
Base.isopen(s::FakeSession) = s.open

function reset_editor_state!()
    empty!(Editor.SESSION_STACK)
    return
end

@testset "Editor.jl" begin
    @testset "register / current_session / forget" begin
        reset_editor_state!()
        @test Editor.current_session() === nothing

        s = make_fake_session()
        Editor.register(s)
        @test Editor.current_session() === s

        Editor.forget(s)
        @test Editor.current_session() === nothing
    end

    @testset "most-recently-registered wins" begin
        reset_editor_state!()
        s1 = make_fake_session()
        s2 = make_fake_session()

        Editor.register(s1)
        Editor.register(s2)
        @test Editor.current_session() === s2

        # Re-registering s1 bumps it to the top of the stack.
        Editor.register(s1)
        @test Editor.current_session() === s1

        # Forgetting the top exposes the next one down.
        Editor.forget(s1)
        @test Editor.current_session() === s2

        Editor.forget(s2)
        @test Editor.current_session() === nothing
    end

    @testset "forget is safe for unknown sessions" begin
        reset_editor_state!()
        s = make_fake_session()
        # Shouldn't throw even though `s` was never registered.
        Editor.forget(s)
        @test Editor.current_session() === nothing
    end

    @testset "closed sessions are skipped" begin
        reset_editor_state!()
        s1 = make_fake_session()
        s2 = make_fake_session()
        Editor.register(s1)
        Editor.register(s2)
        s2.open = false
        # `current_session` should pop the closed one and surface s1.
        @test Editor.current_session() === s1
        @test length(Editor.SESSION_STACK) == 1
    end

    @testset "smuggler_edit sends notification when session registered" begin
        reset_editor_state!()
        s = make_fake_session()
        Editor.register(s)

        cmd = Editor.smuggler_edit(`nvim`, "foo.jl", 42)
        @test cmd == Editor._NOOP_CMD

        notification = take!(s.responsechannel)
        @test notification isa REPLSmuggler.Protocols.Notification
        @test notification.method == "edit"
        @test notification.params == Any["foo.jl", UInt32(42)]

        # line = 0 means "no specific line" — gets clamped to UInt32(0).
        Editor.smuggler_edit(`nvim`, "bar.jl", 0)
        n2 = take!(s.responsechannel)
        @test n2.params == Any["bar.jl", UInt32(0)]
    end

    @testset "smuggler_edit falls back without session" begin
        reset_editor_state!()
        @test Editor.smuggler_edit(`nvim`, "foo.jl", 42) == `nvim +42 foo.jl`
        @test Editor.smuggler_edit(`nvim`, "foo.jl", 0) == `nvim foo.jl`
        # Fallback works for any editor binary — that's the point of decoupling
        # the open-on-edit behaviour from the server.
        @test Editor.smuggler_edit(`emacs`, "foo.jl", 7) == `emacs +7 foo.jl`
    end

    @testset "smuggler_edit falls back if channel was closed" begin
        reset_editor_state!()
        s = make_fake_session()
        Editor.register(s)
        close(s.responsechannel)

        cmd = Editor.smuggler_edit(`nvim`, "foo.jl", 5)
        @test cmd == `nvim +5 foo.jl`
        # The dead session is auto-forgotten so subsequent calls don't retry.
        @test Editor.current_session() === nothing
    end

    @testset "install! is idempotent per pattern" begin
        # Installing the same pattern twice must not register multiple callbacks
        # with InteractiveUtils — otherwise every `@edit` call would invoke our
        # action N times.
        Editor.install!("nvim")
        before = length(InteractiveUtils.EDITOR_CALLBACKS)
        Editor.install!("nvim")
        Editor.install!("nvim")
        @test length(InteractiveUtils.EDITOR_CALLBACKS) == before
        @test "nvim" in Editor.INSTALLED_PATTERNS

        # A different pattern adds a separate callback — supporting clients for
        # other editors (emacs, helix, ...) connecting to the same server.
        Editor.install!("emacs")
        @test length(InteractiveUtils.EDITOR_CALLBACKS) == before + 1
        @test "emacs" in Editor.INSTALLED_PATTERNS
    end
end
