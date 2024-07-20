"""
A specific kind of server for UNIX sockets / Windows pipes.
"""
module SocketSmugglers
using Sockets

using ..REPLSmuggler
using REPLSmuggler.Server

export SocketSmuggler

struct SocketSmuggler
    path::String
    server::Base.IOServer
end
function SocketSmuggler(path)
    if !Sys.iswindows()
        mkpath(dirname(path))
    end
    server = listen(path)
    @info "Ahoy, now smuggling from socket $path."
    SocketSmuggler(path, server)
end
Base.isopen(s::SocketSmuggler) = isopen(s.server)
Base.close(s::SocketSmuggler) = close(s.server)

function REPLSmuggler.Server.waitsession(s::Server.Smuggler{SocketSmuggler, U}) where {U}
    socketsmuggler = REPLSmuggler.Server.vessel(s)
    accept(socketsmuggler.server)
end

Server.io(s::Base.PipeEndpoint) = s

end
