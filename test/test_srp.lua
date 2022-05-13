package.path = "proto/?.lua;" .. package.path
local skynet = require "skynet"
local sprotoloader = require "sprotoloader"
local proto = require "proto"

--[[
local function protect(f, ...)
    local t = table.pack(pcall(f, ...))
    assert(t[1], t[2])

    return table.unpack(t, 2, t.n)
end

local I = "jintiao"
local p = "123abc*()DEF"

-- Call at server side when user register new user
local s, v = protect(srp.create_verifier, I, p)
assert(s and v)

-- Call at client side when user try to login
local a, A = srp.create_client_key()

-- Call at server side. A is send from client to server
local Ks, b, B = protect(srp.create_server_session_key, v, A)

-- Call at client side. s, B is send from server to client
local Kc = protect(srp.create_client_session_key, I, p, s, a, A, B)

-- We should not use this in real world, K must not expose to network
-- use this key to encrypt something then verify it on other side is more reasonable
assert(Ks == Kc, "srp test failed")
]]

skynet.start(function()
    sprotoloader.save(proto.c2s, 1)
    sprotoloader.save(proto.s2c, 2)

    skynet.uniqueservice "database"

    local loginserver = skynet.newservice("loginserver")
    skynet.call(loginserver, "lua", "open", skynet.self(), {
	 host = skynet.getenv "loginserver_host",
	 port = assert(tonumber(skynet.getenv "loginserver_port")),
	 auth_timeout = assert(tonumber(skynet.getenv "auth_timeout")),
	 session_expire_time = assert(tonumber(skynet.getenv "session_expire_time")),
     })

    local gate = skynet.newservice("gate", loginserver)
    skynet.call(gate, "lua", "open", {
	port = assert(tonumber(skynet.getenv "gameserver_port")),
	maxclient = tonumber(skynet.getenv "maxclient") or 64,
	servername = assert(skynet.getenv "servername"),
    })
end)
