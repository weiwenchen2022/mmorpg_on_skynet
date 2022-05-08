local gatewayserver = require "gatewayserver"
local skynet = require "skynet"
require "skynet.manager"

local loginserver = assert(tonumber(...))

local server = {}

local agent_meta = {
    __gc = function(o)
	local a = o[1]
	o[1] = nil

	if a then
	    skynet.kill(a)
	end
    end,
}

local agent_pool = setmetatable({}, {__mode = "v",})
local users = {}

function server.open(source, conf)
    skynet.error("gate open")
end

local CMD = {}

function CMD.disconnect(source, account)
    assert(users[account][1] == source,
	string.format("user[%d][1] = %d, source = %d", account, users[account][1], source))

    local agent = users[account]
    users[account] = nil
    table.insert(agent_pool, agent)
    skynet.wakeup(agent)
    skynet.error(string.format("agent %d recycled", source))
end

function server.kick_handler(fd)
    gatewayserver.kick(fd)
end

function server.command_handler(cmd, source, ...)
    local f = assert(CMD[cmd])
    return f(source, ...)
end

function server.auth_handler(session, token)
    return skynet.call(loginserver, "lua", "verify", session, token)
end

function server.login_handler(fd, account)
    local agent = users[account]
    if agent then
	skynet.error(string.format("multiple login detected for account %d", account))
	skynet.call(agent[1], "lua", "kick", account)
	skynet.wait(agent)
    end

    agent = table.remove(agent_pool)
    if not agent then
	agent = setmetatable({skynet.newservice("agent", skynet.self()),}, agent_meta)
	skynet.error(string.format("pool is empty, new agent(%d) created", agent[1]))
    else
	skynet.error(string.format("agent(%d) assigned, %d remain in pool", agent[1], #agent_pool))
    end

    users[account] = agent
    skynet.call(agent[1], "lua", "start", {client = fd, account = account, gate = skynet.self(),})
    gatewayserver.forward(fd, agent[1])
    return agent[1]
end

function server.disconnect_handler(fd)
    skynet.error("fd (%d) disconnected", fd)
end

skynet.info_func(function()
    local user = {}
    for account, agent in pairs(users) do
	user[account] = agent[1]
    end

    return {
	agent_pool = #agent_pool,
	users = user,
    }
end)

gatewayserver.start(server)
