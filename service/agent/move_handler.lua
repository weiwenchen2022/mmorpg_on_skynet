local skynet = require "skynet"
local handler = require "handler"
local aoi_handler = require "aoi_handler"

local REQUEST = {}
local _M = handler.new(REQUEST)
_ENV = _M

function REQUEST:move(arg)
    assert(arg and arg.pos)

    local npos = arg.pos
    local opos = self.character.movement.pos
    for k, v in pairs(opos) do
	if not npos[k] then
	    npos[k] = v
	end
    end

    local ok = skynet.call(self.map, "lua", "move_blink", npos)
    if ok then
	self.character.movement.pos = npos
	aoi_handler.boardcast "move"

	return {pos = npos,}
    end
end

return _M
