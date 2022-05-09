local skynet = require "skynet"
local aoi = require "aoi"
local gdd = require "gdd"

local world
local conf

local pending_character = {}
local online_character = {}

local CMD = {}

function CMD.init(source, name)
    world = w
    conf = gdd["map"][name]

    aoi.init(conf.bbox, conf.radius)
end

function CMD.character_enter(_, agent, character)
    skynet.error(string.format("character (%d) loading map", character))

    pending_character[agent] = character
    skynet.call(agent, "lua", "map_enter")
end

function CMD.character_ready(agent, pos)
    local character = pending_character[agent]
    if not character then return false end

    online_character[agent] = character
    pending_character[agent] = nil

    skynet.error(string.format("character (%d) enter map", character))

    local ok, list = aoi.insert(agent, pos)
    if not ok then return false end

    skynet.call(agent, "lua", "aoi_manage", list)
    return true
end

function CMD.character_leave(agent)
    local character = pending_character[agent] or online_character[agent]
    if character then
	skynet.error(string.format("character (%d) leave map", character))

	local ok, list = aoi.remove(agent)
	if ok then
	    skynet.call(agent, "lua", "aoi_manage", nil, list)
	end
    end

    pending_character[agent] = nil
    online_character[agent] = nil
end

function CMD.move_blink(agent, pos)
    local ok, add, update, remove = aoi.update(agent, pos)
    if not ok then return end

    skynet.call(agent, "lua", "aoi_manage", add, remove, update, "move")
    return true
end

skynet.start(function()
    skynet.dispatch("lua", function(_, source, cmd, ...)
	local f = assert(CMD[cmd])
	skynet.retpack(f(source, ...))
    end)
end)
