local skynet = require "skynet"
local aoi = require "aoi"
local gdd = require "gdd"

local space
local radius2

local world
local conf

local pending_character = {}
local online_character = {}

local CMD = {}

local object = {}

local function message(_, watcher, marker, noswap)
    local obj = assert(object[marker])

    skynet.error(string.format("message, watcher = %d, marker = %d", watcher, marker))

    if not obj.list[watcher] then
	obj.list[watcher] = true

	if not noswap then
	    local alist = {[watcher] = true,}
	    skynet.call(marker, "lua", "aoi_manage", alist)
	end

	if not noswap then
	    message(_, marker, watcher, true)
	end
    else
	local ulist = {[watcher] = true,}
	skynet.call(marker, "lua", "aoi_manage", nil, nil, ulist, "move")
    end
end

local function dist2(id1, id2)
    local obj1 = assert(object[id1])
    local obj2 = assert(object[id2])

    local d = (obj1.pos.x - obj1.pos.x) * (obj1.pos.x - obj1.pos.x)
		+ (obj1.pos.y - obj1.pos.y) * (obj1.pos.y - obj1.pos.y)
    return d
end

function CMD.init(source, name)
    world = w
    conf = gdd["map"][name]

    space = aoi.new(conf.radius)
    radius2 = conf.radius * conf.radius

    skynet.fork(function()
	while true do
	    space:message(message)

	    local rlist
	    for agent, obj in pairs(object) do
		for marker in pairs(obj.list) do
		    local distance2 = dist2(agent, marker)

		    if distance2 > radius2*4 then
			obj.list[marker] = nil
			rlist = rlist or {}
			rlist[marker] = true
		    end
		end

		if rlist then
		    skynet.call(agent, "lua", "aoi_manage", nil, rlist)
		    rlist = nil
		end
	    end

	    skynet.sleep(100)
	end
    end)
    -- aoi.init(conf.bbox, conf.radius)
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

    skynet.error(string.format("character (%d) enter map", character), pos)

    assert(object[agent] == nil)
    local obj = {
	id = agent,
	pos = pos,
	list = {},
    }
    object[agent] = obj

    space:update(agent, "wm", pos.x, pos.y)

    -- local ok, list = aoi.insert(agent, pos)
    -- if not ok then return false end

    -- skynet.error("character_ready", list)

    -- skynet.call(agent, "lua", "aoi_manage", list)
    return true
end

function CMD.character_leave(agent)
    local character = pending_character[agent] or online_character[agent]
    if character then
	skynet.error(string.format("character (%d) leave map", character))

	space:update(agent, "d")
	local obj = object[agent]
	object[agent] = nil

	if obj then
	    for id in pairs(obj.list) do
		local t = object[id]
		if t then
		    t.list[agent] = nil
		end
	    end

	    local rlist = obj.list
	    skynet.call(agent, "lua", "aoi_manage", nil, rlist)
	end
	-- local ok, list = aoi.remove(agent)
	-- if ok then
	--     skynet.call(agent, "lua", "aoi_manage", nil, list)
	-- end
    end

    pending_character[agent] = nil
    online_character[agent] = nil
end

function CMD.move_blink(agent, pos)
    space:update(agent, "wm", pos.x, pos.y)

    local obj = assert(object[agent])
    obj.pos = pos

    local alist, rlist, ulist = nil, nil, obj.list
    skynet.call(agent, "lua", "aoi_manage", nil, nil, ulist, "move")
    -- local ok, add, update, remove = aoi.update(agent, pos)
    -- skynet.error("move_blink", agent, pos, ok)
    -- if not ok then return end

    -- skynet.call(agent, "lua", "aoi_manage", add, remove, update, "move")
    return true
end

skynet.start(function()
    skynet.dispatch("lua", function(_, source, cmd, ...)
	local f = assert(CMD[cmd])
	skynet.retpack(f(source, ...))
    end)
end)
