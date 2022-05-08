local skynet = require "skynet"

skynet.start(function()
    skynet.error("Server start")

    skynet.uniqueservice "protoloader"
    skynet.uniqueservice "database"

    if not skynet.getenv "daemon" then
	local console = skynet.newservice("console")
    end

    skynet.newservice("debug_console", 8000)

    local loginserver = skynet.newservice "logind"
    local gate = skynet.newservice("gate", loginserver)

    skynet.call(gate, "lua", "open", {
	port = assert(tonumber(skynet.getenv "gameserver_port")),
	maxclient = tonumber(skynet.getenv "maxclient") or 64,
	servername = assert(skynet.getenv "servername"),
    })

    skynet.uniqueservice "gdd"
    skynet.uniqueservice "world"

    skynet.exit()
end)
