"""
Inspired by [JET](https://github.com/aviatesk/JET.jl)'s handling of vscode.
"""
module JETExt

using JET, REPLSmuggler

transformpath(path::Symbol) = transformpath(string(path))
transformpath(path::AbstractString) = JET.tofullpath(path)

"""
    smuggle(jet_result)

Smuggle a JET report to your editor.
!!! warning

    The notification will be sent to all connected sessions.

# Examples
```julia
smuggle(@report_opt my_func())
```
"""
function REPLSmuggler.smuggle(result::JET.JETCallResult)
    if isnothing(REPLSmuggler.CURRENT_SMUGGLER)
        error("No smuggling route. First call `smuggle()` and connect with your editor to open one.")
    end
    for report in JET.get_reports(result)
        showpoint = first(report.vst)
        path = transformpath(showpoint.file)
        message = sprint(JET.print_report, report)
        line = showpoint.line
        func = string(showpoint.linfo)
        for session in REPLSmuggler.Server.sessions(REPLSmuggler.CURRENT_SMUGGLER)
            put!(session.responsechannel, REPLSmuggler.Protocols.Diagnostic(string(typeof(report)), message, [(path, line, func)]))
        end
    end
end

end
