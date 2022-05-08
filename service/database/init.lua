local skynet = require "skynet"
local redis = require "skynet.db.redis"

local account = require "account"
local character = require "character"

local db
local MODULE = {}

local function module_init(name, m)
    assert(MODULE[name] == nil)

    MODULE[name] = m
    m.init(db)
end

skynet.start(function()
    skynet.dispatch("lua", function(_, _, mod, cmd, ...)
	local m = assert(MODULE[mod])
	local f = assert(m[cmd])
	skynet.retpack(f(...))
    end)

    db = redis.connect {
	host = skynet.getenv "redis_host" or "127.0.0,1",
	port = tonumber(skynet.getenv "redis_port") or 6379,
	db = 0,
    }

    module_init("account", account)
    module_init("character", character)
end)
