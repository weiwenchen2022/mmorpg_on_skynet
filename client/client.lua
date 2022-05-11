package.cpath = "luaclib/?.so;" .. "skynet/luaclib/?.so"
package.path = "proto/?.lua;" .. "client/?.lua;" .. "lualib/?.lua;" .. "skynet/lualib/?.lua"

if _VERSION ~= "Lua 5.4" then
    error "Use Lua 5.4"
end

local socket = require "client.socket"
local sproto = require "sproto"
local proto = require "proto"
local srp = require "srp"
local aes = require "aes"
local constant = require "constant"
local print_r = require "print_r"


local host = sproto.new(proto.s2c):host "package"
local request = host:attach(sproto.new(proto.c2s))

local fd
local last = ""

local user = {name = arg[1] or "test", password = constant.default_password, login = false,}
user.private_key, user.public_key = srp.create_client_key()

local function send_package(fd, pack)
    local package = string.pack(">s2", pack)
    socket.send(fd, package)
end

local pending_session = {}
local session = 0

local function send_request(name, arg)
    session = session + 1
    local str = request(name, arg, session)
    send_package(fd, str)
    pending_session[session] = {name = name, arg = arg,}

    print("Request: " .. session)
end

local RESPONSE = {}

function RESPONSE:handshake(arg)
    print "RESPONSE.handshake"

    local name = self.name
    assert(user.name == name)

    local session_key = srp.create_client_session_key(user.name, user.password, arg.salt,
	    user.private_key, user.public_key, arg.server_pub)
    user.session_key = session_key

    send_request("auth", {
	challenge = aes.encrypt(arg.challenge, session_key),
	password = not arg.user_exists and aes.encrypt(user.password, session_key) or nil,
    })
end

function RESPONSE:auth(arg)
    print "RESPONSE.auth"

    user.session = arg.session
    local challenge = aes.encrypt(arg.challenge, user.session_key)
    send_request("challenge", {session = arg.session, challenge = challenge,})
end

function RESPONSE:challenge(arg)
    print "RESPONSE.challenge"

    local token = aes.encrypt(arg.token, user.session_key)
    socket.close(fd)

    fd = assert(socket.connect("127.0.0.1", 8888))
    last = ""

    print(string.format("game server connected, fd = %d", fd))
    send_request("login", {session = user.session, token = token,})
end

function RESPONSE:login(arg)
    assert(arg.ok, arg.error)
    user.login = true
end

function RESPONSE:character_list(arg)
    print("character_list")
    print_r(arg.character)
    user.character_list = arg.character
end

function RESPONSE:character_pick(arg)
    assert(arg.ok and arg.character)
    print("character_pick")
    print_r(arg.character)
    user.character = arg.character
end

function RESPONSE:map_ready()
    user.map_ready = true
end

local function handle_response(session, arg)
    local t = assert(pending_session[session])
    pending_session[session] = nil

    local f = RESPONSE[t.name]
    if f then
	f(t.arg, arg)
    else
	print("response", t.name)

	if arg then
	    print_r(arg)
	end
    end
end

local r = {wantmore = true,}
local REQUEST = {}

function REQUEST.aoi_add(arg)
    assert(arg and arg.character and arg.character.id)

    if not user.aoi_view then
	user.aoi_view = {}
    end

    user.aoi_view[arg.character.id] = arg.character
end

local function handle_request(name, arg, response)
    print("request", name)

    if arg then
	print_r(arg)
    else
	print "no argument"
    end

    local f = REQUEST[name]
    if f then
	f(arg)
    end

    if name:sub(1, 4) == "aoi_" and name ~= "aoi_remove" then
	if response then
	    r.character = arg.character.id
	    send_package(fd, response(r))
	end
    end
end

local function handle_package(t, ...)
    if "REQUEST" == t then
	handle_request(...)
    else
	assert("RESPONSE" == t)
	handle_response(...)
    end
end

local function unpack_package(text)
    local len = #text
    if len < 2 then
	return nil, text
    end

    local sz = text:byte(1) * 256 + text:byte(2)
    if len < 2 + sz then
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

    local str = socket.recv(fd)
    if not str then
	return nil, last
    end

    if str == "" then
	error "Server closed"
    end

    return unpack_package(last .. str)
end

local function disptach_package()
    while true do
	local v
	v, last = recv_package(last)
	if not v then break end

	handle_package(host:dispatch(v))
    end
end

fd = assert(socket.connect("127.0.0.1", 8001))
last = ""

print(string.format("login server connected, fd = %d", fd))
send_request("handshake", {name = user.name, client_pub = user.public_key,})

local HELP = {}

function HELP.character_create()
    return [[
	name: your nickname in game
	race: 1: human, 2: orc
	class: 1: warrior, 2: mage
    ]]
end

local function handle_cmd(line)
    local cmd
    local p = string.gsub(line, "([_%w]+)", function(s)
	cmd = string.lower(s)
	return ""
    end, 1)

    if cmd == "help" then
	for k, v in pairs(HELP) do
	    print(string.format("command:\n\t%s\nparameter:\n%s", k, v()))
	end

	return true
    end

    if cmd == "character_create" then
	p = string.gsub(p, "$name", function()
	    if user.name == "test" then
		return "hello"
	    elseif user.name == "test2" then
		return "world"
	    end

	    return nil
	end)
    elseif cmd == "character_pick" then
	if not user.character_list then
	    return false
	end

	p = string.gsub(p, "$([_%w]+)", function(name)
	    local _, v = next(user.character_list)
	    return tostring(v[name])
	end)
    elseif cmd == "map_ready" then
	if not user.character then
	    return false
	end
    elseif cmd == "move" then
	if not user.map_ready then
	    return false
	end

	p = string.gsub(p, "$([_%w]+)", function(name)
	    return tostring(user.character.movement.pos[name])
	end)
    elseif cmd == "combat" then
	if not user.aoi_view or not next(user.aoi_view) then
	    return false
	end

	local _, target = next(user.aoi_view)
	p = string.gsub(p, "$target", function()
	    return tostring(target.id)
	end)
    end

    print(cmd, "===", p)

    local arg = {}
    local f = assert(load(p, "=(load)", "t", arg))
    f()

    print("cmd", cmd)
    arg = next(arg) and arg or nil

    if arg then
	print_r(arg)
    else
	print "no argument"
    end

    if cmd then
	local ok, err = pcall(send_request, cmd, arg)
	if not ok then
	    print(string.format("Invalid command: %s, error: %s", cmd, err))
	end
    end

    return true
end

print "type 'help' to see all available command."
local line

while true do
    disptach_package()

    if user.login and not line then
	line = socket.readstdin()
    end

    if line then
	local ok = true
	if string.sub(line, 1, 1) ~= "#" then
	    ok = handle_cmd(line)
	end

	if ok then
	    line = nil
	end
    else
	socket.usleep(100)
    end
end
