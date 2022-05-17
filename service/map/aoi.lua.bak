local quadtree = require "quadtree"

local _M = setmetatable({}, {__index = _ENV,})
_ENV = _M

local object = {}
local qtree
local radius

function init(bbox, r)
    qtree = quadtree.new(bbox.left, bbox.top, bbox.right, bbox.bottom)
    radius = r
end

function insert(id, pos)
    if object[id] then return false end

    local tree = qtree:insert(id, pos.x, pos.y)
    if not tree then return false end

    local result = {}
    qtree:query(id, pos.x - radius, pos.y - radius, pos.x + radius, pos.y + radius, result)

    local list = {}
    for _, cid in ipairs(result) do
	local c = object[cid]
	if c then
	    c.list[id] = true
	    list[cid] = true
	end
    end

    object[id] = {id = id, pos = pos, qtree = tree, list = list,}
    return true, list
end

function remove(id)
    local c = object[id]
    if not c then return false end

    if c.qtree then
	c.qtree:remove(id)
    else
	qtree:remove(id)
    end

    for cid in pairs(c.list) do
	local t = object[cid]
	if t then
	    t.list[id] = nil
	end
    end

    object[id] = nil
    return true, c.list
end

function update(id, pos)
    local c = object[id]
    if not c then return false end

    if c.qtree then
	c.qtree:remove(id)
    else
	qtree:remove(id)
    end

    local olist = c.list
    local tree = qtree:insert(id, pos.x, pos.y)
    if not tree then return false end

    c.pos = pos

    local result = {}
    qtree:query(id, pos.x - radius, pos.y - radius, pos.x + radius, pos.y + radius, result)

    local nlist = {}
    for _, cid in ipairs(result) do
	nlist[cid] = true
    end

    local ulist = {}
    for cid in pairs(nlist) do
	if olist[cid] then
	    olist[cid] = nil
	    ulist[cid] = true
	end
    end

    for cid in pairs(ulist) do
	nlist[cid] = nil
    end

    c.list = {}
    for cid in pairs(nlist) do
	c.list[cid] = true
    end

    for cid in pairs(ulist) do
	c.list[cid] = true
    end

    return true, nlist, ulist, olist
end

return _M
