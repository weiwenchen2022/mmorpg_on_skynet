local skynet = require "skynet"
local sharemap = require "skynet.sharemap"
local handler = require "handler"

local RESPONSE = {}
local CMD = {}

local _M = handler.new(nil, RESPONSE, CMD)
_ENV = _M

local subscribe_character
local subscribe_agent
local character_writer
local user
local self_id
local self_flag
local scope2proto = {
    move = "aoi_update_move",
    attribute = "aoi_update_attribute",
}

_M:init(function(u)
    user = u
    character_writer = nil
    subscribe_character = {}
    subscribe_agent = {}

    self_id = u.character.id

    self_flag = {}
    for k in pairs(scope2proto) do
	self_flag[k]= {dirty = false, wantmore = true,}
    end
end)

local function send_self(scope)
    local flag = self_flag[scope]

    if flag.dirty and flag.wantmore then
	flag.dirty = false
	flag.wantmore = false

	user.send_request(scope2proto[scope], {character = user.character,})
    end
end

local function agent2id(agent)
    local t = subscribe_agent[agent]
    if t then return t.character.id
    else return nil end
end

local function mark_flag(character, scope, key, value)
    local t = subscribe_character[character]
    if not t then return end

    t = t.flag[scope]

    if value == nil then value = true end
    t[key] = value
end

local function create_reader()
    skynet.error "create_reader"

    character_writer = character_writer or sharemap.writer("character", user.character)
    return character_writer:copy()
end

local function subscribe(agent, reader)
    skynet.error(string.format("aoi_handler, subscribe agent (%d) reader (%s)", agent, reader))
    local c = sharemap.reader("character", reader)

    local flag = {}
    for k in pairs(scope2proto) do
	flag[k] = {dirty = false, wantmore = false,}
    end

    local t = {
	character = c,
	agent = agent,
	flag = flag,
    }

    subscribe_character[c.id] = t
    subscribe_agent[agent] = t

    user.send_request("aoi_add", {character = c,})
end

local function refresh_aoi(id, scope)
    skynet.error("refresh_aoi character (%d) scope (%s)", id, scope)

    local t = subscribe_character[id]
    if not t then return end

    local c = t.character
    t = c.flag[scope]
    if not t then return end

    skynet.error(string.format("dirty = %q, wantmore = %q", t.dirty, t.wantmore))

    if t.dirty and t.wantmore then
	c:update()

	user.send_request(scope2proto[scope], {character = c,})
	t.dirty = false
	t.wantmore = false
    end
end

local function aoi_update_response(id, scope)
    if self_id == id then
	self_flag[scope].wantmore = true
	send_self(scope)
	return
    end

    mark_flag(id, scope, "wantmore", true)
    refresh_aoi(id, scope)
end

local function aoi_add(list)
    if not list then return end

    for _, agent in pairs(list) do
	skynet.fork(function()
	    local reader = skynet.call(agent, "lua", "aoi_subscribe", skynet.self(), create_reader())
	    subscribe(agent, reader)
	end)
    end
end

local function aoi_update(list, scope)
    if not list then return end

    self_flag[scope].dirty = true
    send_self(scope)

    for _, agent in pairs(list) do
	skynet.fork(function()
	    skynet.call(agent, "lua", "aoi_send", scope)
	end)
    end
end

local function aoi_remove(list)
    if not list then return end

    for _, agent in pairs(list) do
	skynet.fork(function()
	    local t = subscribe_agent[agent]
	    if t then
		local id = t.character.id
		subscribe_agent[agent] = nil
		subscribe_character[id] = nil

		user.send_request("aoi_remove", {character = id,})
		skynet.call(agent, "lua", "aoi_unsubscribe", skynet.self())
	    end
	end)
    end
end

function CMD.aoi_subscribe(source, reader)
    skynet.error(string.format("aoi_subscribe, agent (%d) reader (%s)", source, reader))

    subscribe(source, reader)
    return create_reader()
end

function CMD.aoi_unsubscribe(source)
    skynet.error(string.format("aoi_unsubscribe, agent (%d)", source))

    local t = subscribe_agent[source]
    if t then
	local id = t.character.id
	subscribe_agent[source] = nil
	subscribe_character[id] = nil

	user.send_request("aoi_remove", {character = id,})
    end
end

function CMD.aoi_manage(source, alist, rlist, ulist, scope)
    if (alist or ulist) and character_writer then
	character_writer:commit()
    end

    aoi_add(alist)
    aoi_remove(rlist)
    aoi_update(ulist, scope)
end

function CMD.aoi_send(source, scope)
    local t = subscribe_agent[souce]
    if not t then return end

    local id = t.character.id

    mark_flag(id, scope, "dirty", true)
    refresh_aoi(id, scope)
end

function RESPONSE:aoi_add(response)
    if not response or not response.wantmore then return end

    local id = self.character.id
    for k in pairs(scope2proto) do
	mark_flag(id, k, "wantmore", true)
	refresh_aoi(id, k)
    end
end

function RESPONSE:aoi_update_move(response)
    if not response or not response.wantmore then return end

    aoi_update_response(self.character.id, "move")
end

function RESPONSE:aoi_update_attribute(response)
    if not response or not response.wantmore then return end

    aoi_update_response(self.character.id, "attribute")
end

function find(id)
    local t = subscribe_character[id]
    if t then return t.agent
    else return nil end
end

function boardcast(scope)
    if not character_writer then return end

    character_writer:commit()
    self_flag[scope].dirty = true
    send_self(scope)


    for agent in pairs(subscribe_agent) do
	skynet.fork(function()
	    skynet.call(agent, "lua", "aoi_send", scope)
	end)
    end
end

return _M
