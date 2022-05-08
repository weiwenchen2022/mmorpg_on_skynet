
local _M = setmetatable({}, {__index = _ENV,})
_ENV = _M

local meta = {}
meta.__index = meta

local function subdivide(self, last)
    local left, top, right, bottom = self.left, self.top, self.right, self.bottom
    local centerx = left + (right - left) // 2
    local centery = top + (bottom - top) // 2

    assert(not self.children)
    self.children = {
	new(left, top, centerx, centery),
	new(centerx, top, right, centery),
	new(left, centery, right, bottom),
	new(centerx, centery, right, bottom),
    }

    local ret
    local t
    for k, v in pairs(self.object) do
	for _, c in ipairs(self.children) do
	    t = c:insert(k, v.x, v.y)
	    if t then
		if last == k then
		    ret = t
		end

		break
	    end
	end
    end

    self.object = nil
    return ret
end

function meta:insert(id, x, y)
    if not (self.left <= x and x <= self.right and self.top <= y and y <= self.bottom) then
	return false
    end

    if self.children then
	local t
	for _, v in pairs(self.children) do
	    t = v:insert(id, x, y)
	    if t then return t end
	end
    else
	self.object[id] = {x = y, y = y,}

	local k = next(self.object)
	if next(self.object, k) then
	    return subdivide(self, id)
	end

	return self
    end
end

function meta:remove(id)
    if self.children then
	for _, child in ipairs(self.children) do
	    if child:remove(id) then return true end
	end
    elseif self.object then
	if self.object[id] then
	    self.object[id] = nil
	    return true
	end
    end

    return false
end

function meta:query(id, left, top, right, bottom, result)
    if left > self.right or right < self.left or top > self.bottom or bottom < self.top then return end

    if self.children then
	for _, child in ipairs(self.children) do
	    child:query(id, left, top, right, bottom, result)
	end
    elseif self.object then
	for k, v in pairs(self.object) do
	    if id ~= k and (left <= v.x and v.x <= right and top <= v.y and v.y <= bottom) then
		table.insert(result, k)
	    end
	end
    end
end

function new(left, top, right, bottom)
    return setmetatable({
	left = left,
	top = top,
	right = right,
	bottom = bottom,

	object = {},
    }, meta)
end

return _M
