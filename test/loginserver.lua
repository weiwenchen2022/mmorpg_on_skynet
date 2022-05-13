local skynet = require "skynet"
require "skynet.manager"
local socket = require "skynet.socket"

local sprotoloader = require "sprotoloader"

local srp = require "srp"
local aes= require "aes"
local uuid = require "uuid"
local constant = require "constant"

local host
local request
local CMD = {}

local socket_error = {}
local function assert_socket(service, v, fd)
    if v then
	return v
    end

    skynet.error(string.format("%s failed: socket (fd = %d) closed", service, fd))
    error(socket_error)
end

local function write(service, fd, msg)
    local package = string.pack(">s2", msg)
    assert_socket(server, socket.write(fd, package), fd)
end

local function read(service, fd)
    local sz = assert_socket(server, socket.read(fd, 2), fd)
    sz = sz:byte(1) * 256 + sz:byte(2)

    local msg = assert_socket(server, socket.read(fd, sz), fd)
    return host:dispatch(msg, sz)
end

local function launch_slave(m, conf)
    local master
    local database
    local saved_session = {}
    local connection = {}
    local auth_timeout
    local session_expire_time
    local session_expire_time_in_second

    local function close(fd)
	if connection[fd] then
	    connection[fd] = nil
	    socket.close(fd)
	end
    end

    function CMD.save_session(session, account, key, challenge)
	saved_session[session] = {account = account, key = key, challenge = challenge,}

	skynet.timeout(session_expire_time, function()
	    local t = saved_session[session]
	    if t and key == t.key then
		saved_session[session] = nil
	    end
	end)
    end

    function CMD.challenge(session, secret)
	local t = assert(saved_session[session])
	local text = aes.decrypt(secret, t.key)
	assert(t.challenge == text)

	t.token = srp.random()
	t.challenge = srp.random()

	return t.token, t.challenge
    end

    function CMD.auth(fd, addr)
	connection[fd] = addr

	skynet.timeout(auth_timeout, function()
	    if addr == connection[fd] then
		skynet.error("connection %d from %s, auth timeout!", fd, addr)
		close(fd)
	    end
	end)

	socket.start(fd)
	socket.limit(fd, 8192)

	local type, name, arg, response = read("auth", fd)
	assert(type == "REQUEST")

	if name == "handshake" then
	    assert(arg.name and arg.client_pub, "Invalid handshake request")

	    local account = skynet.call(database, "lua", "account", "load", arg.name)

	    local session_key, _, pkey = srp.create_server_session_key(account.verifier, arg.client_pub)
	    local challenge = srp.random()
	    write("auth", fd, response {
		user_exists = (account.id ~= nil),
		salt = account.salt,
		server_pub = pkey,
		challenge = challenge,
	    })

	    type, name, arg, response = read("auth", fd)
	    assert(type == "REQUEST")
	    assert(name == "auth" and arg and arg.challenge, "Invalid auth request")

	    local text = aes.decrypt(arg.challenge, session_key)
	    assert(challenge == text, "auth challenge failed")

	    local id = tonumber(account.id)
	    if not id then
		assert(arg.password)
		local password = aes.decrypt(arg.password, session_key)
		id = uuid.gen()
		account.id = skynet.call(database, "lua", "account", "create", id, account.name, password)
	    end

	    challenge = srp.random()
	    local session = skynet.call(master, "lua", "save_session", id, session_key, challenge)
	    write("auth", fd, response {
		session = session,
		expire = session_expire_time_in_second,
		challenge = challenge,
	    })

	    type, name, arg, response = read("auth", fd)
	    assert(type == "REQUEST")
	end

	assert(name == "challenge" and arg and arg.session and arg.challenge)
	local token, challenge = skynet.call(master, "lua", "challenge", arg.session, arg.challenge)
	assert(token and challenge)

	write("auth", fd, response {
	    token = token,
	    challenge = challenge,
	})

	close(fd)
    end

    function CMD.verify(session, secret)
	local t = assert(saved_session[session])
	local text = aes.decrypt(secret, t.key)
	assert(t.token == text)
	t.token = nil

	return t.account
    end

    master = m
    database = skynet.uniqueservice "database"
    host = sprotoloader.load(1):host "package"
    auth_timeout = conf.auth_timeout * 100
    session_expire_time_in_second = conf.session_expire_time
    session_expire_time = conf.session_expire_time * 100
end

local function launch_master(conf)
    local session_id = 1
    local balance = 1
    local slave = {}
    local listenfd

    function CMD.save_session(account, key, challenge)
	local session = session_id
	session_id = session_id + 1

	local s = slave[(session % #slave) + 1]
	skynet.call(s, "lua", "save_session", session, account, key, challenge)
	return session
    end

    function CMD.challenge(session, challenge)
	local s = slave[(session % #slave) + 1]
	return skynet.call(s, "lua", "challenge", session, challenge)
    end

    function CMD.verify(session, token)
	local s = slave[(session % #slave) + 1]
	return skynet.call(s, "lua", "verify", session, token)
    end

    local instance = conf.instance or 1
    assert(instance > 0)

    for i = 1, instance do
	local s = skynet.newservice(SERVICE_NAME, "slave")
	skynet.call(s, "lua", "open", skynet.self(), conf)
	table.insert(slave, s)
    end

    local host = conf.host or "0.0.0.0"
    local port = assert(tonumber(conf.port))

    listenfd = socket.listen(host, port)
    skynet.error(string.format("Listen on %s:%d", host, port))

    socket.start(listenfd, function(fd, addr)
	local s= slave[balance]
	balance = balance + 1
	if balance > #slave then balance = 1 end

	skynet.call(s, "lua", "auth", fd, addr)
    end)
end

function CMD.open(m, conf)
    local name = "." .. (conf.name or "login")
    local loginmaster = skynet.localname(name)

    if loginmaster then
	launch_master = nil
	launch_slave(m, conf)
    else
	launch_slave = nil
	skynet.register(name)
	launch_master(conf)
    end
end

skynet.start(function()
    skynet.dispatch("lua", function(_, _, cmd, ...)
	local f = assert(CMD[cmd])
	skynet.retpack(f(...))
    end)
end)
