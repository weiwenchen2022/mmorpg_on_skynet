local skynet = require "skynet"
local socket = require "skynet.socket"
local sprotoloader = require "sprotoloader"

local character_handler = require "character_handler"
local map_handler = require "map_handler"
local aoi_handler = require "aoi_handler"
local move_handler = require "move_handler"
local combat_handler = require "combat_handler"

local gamed = assert(tonumber(...))

local host
local send_request

-- agent state
--[[
local self = {
    client_fd = integer,
    account = integer,

    character = table,
    world = integer,
    map = integer,
}
]]
local self = {
    client_fd = nil,

    character = nil,
    world = nil,
    map = nil,
}

local function send_package(pack)
    local package = string.pack(">s2", pack)
    socket.write(self.client_fd, package)
end

local session_id = 0
local session = {}

local function _send_request(name, arg)
    session_id = session_id + 1
    local pack = send_request(name, arg, session_id)
    send_package(pack)
    session[session_id] = {name = name, arg = arg,}
end

local function kick_self()
    skynet.call(gamed, "lua", "kick", skynet.self(), self.client_fd)
end

local last_heartbeat_time
local HEARTBEAT_TIME_MAX = 0

local function heartbeat_check()
    if HEARTBEAT_TIME_MAX <= 0 or not self.client_fd then return end

    local ti = last_heartbeat_time + HEARTBEAT_TIME_MAX - skynet.now()
    if ti <= 0 then
	skynet.error "heartbeat_check timeout"

	kick_self()
	return
    end

    skynet.timeout(ti, heartbeat_check)
end

local REQUEST
local function request(name, arg, response)
    local f = assert(REQUEST[name])
    local r = f(self, arg)
    if response then
	return response(r)
    end
end

local RESPONSE
local function response(id, arg)
    local t = assert(session[id])
    local f = assert(RESPONSE[t.name])
    f(arg)
end

skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,

    unpack = function(msg, sz)
	return host:dispatch(msg, sz)
    end,

    dispatch = function(fd, _, type, ...)
	assert(self.client_fd == fd) -- You can use fd to reply message
	skynet.ignoreret() -- session is fd, don't call skynet.ret

	if "REQUEST" == type then
	    last_heartbeat_time = skynet.now()

	    local ok, result = pcall(request, ...)
	    if ok then
		if result then
		    send_package(result)
		end
	    else
		skynet.error(result)
	    end
	else
	    assert("RESPONSE" == type)

	    local ok, err = pcall(response, ...)
	    if not ok then
		skynet.error(err)
	    end
	    -- error "This example doesn't support request client"
	end
    end,
}

local CMD = {}

function CMD.start(source, conf)
    -- slot 1, 2 set at main.lua
    host = sprotoloader.load(1):host "package"
    send_request = host:attach(sprotoloader.load(2))

    self = {
	client_fd = conf.client,
	gate = conf.gate,
	account = conf.account,

	REQUEST = {},
	RESPONSE = {},
	CMD = CMD,
	send_request = _send_request,
    }

    character_handler:register(self)

    REQUEST = self.REQUEST
    RESPONSE = self.RESPONSE
    CMD = self.CMD

    last_heartbeat_time = skynet.now()
    heartbeat_check()
end

function CMD.close()
    skynet.error "agent closed"

    if self then
	if self.map then
	    skynet.call(self.map, "lua", "character_leave")
	    self.map = nil

	    combat_handler:unregister(self)
	    move_handler:unregister(self)
	    aoi_handler:unregister(self)
	    map_handler:unregister(self)
	end

	if self.world then
	    skynet.call(self.world, "lua", "character_leave", self.character.id)
	    self.world = nil
	end

	character_handler.save(self.character)
	self = nil
    end
end

function CMD.disconnect()
    skynet.call(self.gate, "lua", "disconnect", self.account)
end

function CMD.kick()
    skynet.error "agent kicked"

    skynet.call(self.gate, "lua", "kick", self.client_fd)
end

function CMD.world_enter(source)
    character_handler.init(self.character)

    self.world = source
    character_handler:unregister(self)

    return self.character.general.map, self.character.movement.pos
end

function CMD.map_enter(source)
    self.map = source

    map_handler:register(self)
    aoi_handler:register(self)
    move_handler:register(self)
    combat_handler:register(self)
end

skynet.start(function()
    skynet.dispatch("lua", function(_, source, command, ...)
	local f = assert(CMD[command], "command '" .. command .."' not found")
	skynet.retpack(f(source, ...))
    end)
end)
