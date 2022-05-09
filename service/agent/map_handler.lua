local skynet = require "skynet"
local handler = require "handler"

local REQUEST = {}
local _M = handler.new(REQUEST)
_ENV = _M

function REQUEST:map_ready()
    skynet.error "map_ready"

    skynet.call(self.map, "lua", "character_ready", self.character.movement.pos)
end

return _M
