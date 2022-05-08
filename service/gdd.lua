local skynet = require "skynet"
local sharedata = require "skynet.sharedata"

local list = {
    race = "config/race.lua",
    class = "config/class.lua",
    map = "config/map.lua",
    attribute = "config/attribute.lua",
}

skynet.start(function()
    for name, filepath in pairs(list) do
	sharedata.new(name, "@" .. filepath)
    end
end)
