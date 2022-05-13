package.path = "client/?.lua;" .. "proto/?.lua;" .. "lualib/?.lua;" .. "skynet/lualib/?.lua;" .. package.path
package.cpath = "luaclib/?.so;" .. "skynet/luaclib/?.so;" .. package.cpath

if _VERSION ~= "Lua 5.4" then
    error "Use lua 5.4"
end

local socket = require "client.socket"
local proto = require "proto"
local sproto = require "sproto"
local srp = require "srp"
local aes = require "aes"
local constant = require "constant"
local print_r = require "print_r"

local host = sproto.new(proto.s2c):host "package"
local request = host:attach(sproto.new(proto.c2s))

local fd
local last = ""
local user

local function send_package(fd, pack)
    local package = string.pack(">s2", pack)
    socket.send(fd, package)
end

local session = 0
local pending_session = {}
local function send_request(name, arg)
    session = session + 1
    local str = request(name, arg, session)
    send_package(fd, str)
    pending_session[session] = {name = name, arg = arg,}
    print("Request:", session)
end

local function unpack_package(text)
    local size = #text
    if size < 2 then
	return nil, text
    end

    local sz = text:byte(1) * 256 + text:byte(2)
    if size < 2 + sz then
	return nil, text
    end

    return text:sub(3, 2 + sz), text:sub(3 + sz)
end

local function recv_package(last)
    local result
    result, last = unpack_package(last)

    if result then
	return result, last
    end

    local r = socket.recv(fd)
    if not r then
	return nil, last
    end

    if r == "" then
	error "Server closed"
    end

    return unpack_package(last .. r)
end

local function handle_request(name, arg, response)
    print("REQUEST", name)

    if arg then
	print_r(arg)
    end
end

local RESPONSE = {}

function RESPONSE:handshake(arg)
    local session_key
    if arg.user_exists then
	session_key = srp.create_client_session_key(user.name, user.password,
	    arg.salt, user.private_key, user.public_key, arg.server_pub)
    else
	session_key = srp.create_client_session_key(user.name, constant.default_password,
	    arg.salt, user.private_key, user.public_key, arg.server_pub)
    end

    send_request("auth", {
	challenge = aes.encrypt(arg.challenge, session_key),
	password = not arg.user_exists and aes.encrypt(user.password, session_key) or nil,
    })

    user.session_key = session_key
end

function RESPONSE:auth(arg)
    user.session = arg.session

    local challenge = aes.encrypt(arg.challenge, user.session_key)
    send_request("challenge", {session = arg.session, challenge = challenge,})
end

function RESPONSE:challenge(arg)
    socket.close(fd)
    fd = assert(socket.connect("127.0.0.1", 8888))
    last = ""

    local token = aes.encrypt(arg.token, user.session_key)
    send_request("login", {session = user.session, token = token,})
end

local function handle_response(session, arg)
    print("RESPONSE", session)

    if arg then
	print_r(arg)
    end

    local s = assert(pending_session[session])
    pending_session[session] = nil

    local f = assert(RESPONSE[s.name])
    f(s.arg, arg)
end

local function handle_package(t, ...)
    if t == "REQUEST" then
	handle_request(...)
    else
	assert(t == "RESPONSE")
	handle_response(...)
    end
end

local function dispatch_package()
    while true do
	local v
	v, last = recv_package(last)
	if not v then break end

	handle_package(host:dispatch(v))
    end
end

user = {name = arg[1] or "test", password = arg[2] or constant.default_password,}

fd = assert(socket.connect("127.0.0.1", 8001))
last = ""

local private_key, public_key = srp.create_client_key()
user.private_key = private_key
user.public_key = public_key

send_request("handshake", {name = user.name, client_pub = public_key,})

while true do
    dispatch_package()
    socket.usleep(100)
end
