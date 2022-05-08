local skynet = require "skynet"
local gdd = require "gdd"

local CMD = {}
local map_instance = {}
local online_character = {}

function CMD.kick(character)
    local agent = online_character[character]
    if agent then
	skynet.call(agent, "lua", "kick")
	online_character[character] = nil
    end
end

function CMD.character_enter(agent, character)
    if online_character[character] then
	skynet.error(string.format("multiple login detected, character %d", character))
	CMD.kick(character)
    end

    online_character[character] = agent
    skynet.error(string.format("character (%d) enter world", character))

    local map, pos = skynet.call(agent, "lua", "world_enter")

    local m = assert(map_instance[map])
    skynet.call(m, "lua", "character_enter", agent, character, pos)
end

function CMD.character_leave(agent, character)
    skynet.error(string.format("character (%d) leave world", character))
    online_character[character] = nil
end

skynet.start(function()
    local mapconf = gdd["map"]

    for _, conf in pairs(mapconf) do
	local name = conf.name
	local s = skynet.newservice("map", skynet.self())
	skynet.call(s, "lua", "init", name)
	map_instance[name] = s
    end

    skynet.dispatch("lua", function(_, source, cmd, ...)
	local f = assert(CMD[cmd])
	skynet.retpack(f(source, ...))
    end)
end)
