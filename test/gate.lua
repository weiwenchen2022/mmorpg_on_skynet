local skynet = require "skynet"
local gateserver = require "snax.gateserver"
local sprotoloader = require "sprotoloader"

local logind = assert(tonumber(...))

local pending_msg = {}
local handler = {}

local host = sprotoloader.load(1):host "package"

function handler.connect(fd, addr)
    skynet.error(string.format("connect from %s (fd = %d)", addr, fd))
    gateserver.openclient(fd)
end

function handler.disconnect(fd)
    skynet.error(string.format("fd (%d) disconnected", fd))
end

local function do_login(fd, msg, sz)
    local type, name, arg, response = host:dispatch(msg, sz)
    assert(type == "REQUEST")
    assert(name == "login" and arg.session and arg.token)

    local account = skynet.call(logind, "lua", "verify", arg.session, arg.token)
    assert(account)

    return account
end

function handler.message(fd, msg, sz)
    local queue = pending_msg[fd]
    if queue then
	table.insert(queue {msg, sz,})
    else
	pending_msg[fd] = {}
	local ok, account = pcall(do_login, fd, msg, sz)
	if ok then
	    skynet.error(string.format("account %d login success", account))
	else
	    skynet.error(string.format("%s login failed: %s", addr, account))
	    gateserver.closeclient(fd)
	end

	pending_msg[fd] = nil
    end
end

gateserver.start(handler)
