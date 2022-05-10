local skynet = require "skynet"
local gateserver = require "snax.gateserver"
local sprotoloader = require "sprotoloader"
local netpack = require "skynet.netpack"
local socketdriver = require "skynet.socketdriver"

local gatewayserver = {}

local handshake = {}
local connection = {} -- fd -> connection : {fd , client, agent, ip, mode,}

skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
}

function gatewayserver.forward(fd, agent)
    local c = connection[fd]
    if c then
	assert(c.agent == nil)
	c.agent = agent

	skynet.error(string.format("start forward fd (%d) to agent (%d)", fd, agent))
    end
end

function gatewayserver.kick(fd)
    local c = connection[fd]
    if c then
	gateserver.closeclient(fd)
    end
end

function gatewayserver.start(conf)
    local host = sprotoloader.load(1):host "package"
    local send_request = host:attach(sprotoloader.load(2))

    local handler = {}
    local CMD = {
	kick = assert(conf.kick_handler),
    }

    function handler.command(cmd, source, ...)
	local f = CMD[cmd]
	if f then
	    return f(...)
	else
	    return conf.command_handler(cmd, source, ...)
	end
    end

    function handler.open(source, gateconf)
	conf.open(source, gateconf)
    end

    function handler.connect(fd, addr)
	skynet.error(string.format("connect from %s (fd = %d)", addr, fd))

	handshake[fd] = addr
	gateserver.openclient(fd)
    end

    function handler.disconnect(fd)
	skynet.error("disconnect", fd)

	handshake[fd] = nil
	local c = connection[fd]
	if c then
	    local agent = c.agent
	    if agent then
		skynet.error(string.format("fd (%d) disconnected, closing agent (%d)", fd, agent))

		skynet.call(agent, "lua", "disconnect")
		c.agent = nil
	    else
		if conf.disconnect_handler then
		    conf.disconnect_handler(fd)
		end
	    end

	    c.fd = nil
	    connection[fd] = nil
	end
    end

    handler.error = function(fd, err)
	skynet.error(string.format("error, fd = %d, err = '%s'", fd, err))

	handler.disconnect(fd)
    end

    local function do_auth(fd, type, name, arg, addr)
	assert("REQUEST" == type)
	assert("login" == name and arg.session and arg.token)

	local account = conf.auth_handler(arg.session, arg.token)
	assert(account)

	local c = {
	    fd = fd,
	    ip = addr,
	}
	connection[fd] = c

	local agent = conf.login_handler(fd, account)
    end

    local function auth(fd, addr, msg, sz)
	local type, name, arg, response = host:dispatch(msg, sz)
	local ok, result = pcall(do_auth, fd, type, name, arg, addr)
	if not ok then
	    skynet.error(result)
	    result = "Bad Request"
	end

	local close = result ~= nil

	if result == nil then
	    result = "OK"
	end

	socketdriver.send(fd, netpack.pack(response {ok = ok, error = result,}))

	if close then
	    gateserver.closeclient(fd)
	end
    end

    function handler.message(fd, msg, sz)
	local addr = handshake[fd]
	if addr then
	    auth(fd, addr, msg, sz)
	    handshake[fd] = nil
	else
	    -- recv a package, forward it
	    local c = connection[fd]
	    local agent = c.agent
	    if agent then
		-- It's safe to redirect msg directly , gateserver framework will not free msg.
		skynet.redirect(agent, 0, "client", fd, msg, sz)
	    else
		skynet.error(string.format("Drop message from fd (%d) : %s", fd, netpack.tostring(msg, sz)))
	    end
	end
    end

    return gateserver.start(handler)
end

return gatewayserver
