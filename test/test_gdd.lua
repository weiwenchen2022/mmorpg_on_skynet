local skynet = require "skynet"
local gdd = require "gdd"

skynet.start(function()
    local mapdata = gdd.map

    for _, conf in pairs(mapdata) do
	skynet.error("name = " .. conf.name)
    end
end)
