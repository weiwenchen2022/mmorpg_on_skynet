local skynet = require "skynet"
local sharedata = require "skynet.sharedata"

local gdd = setmetatable({}, {
    __index = function(_, name)
	return sharedata.query(name)
    end,
})

skynet.init(function()
    skynet.uniqueservice "gdd"
end)

return gdd
