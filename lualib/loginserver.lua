local skynet = require "skynet"
require "skynet.manager"
local socket = require "skynet.socket"

local sprotoloader = require "sprotoloader"
local srp = require "srp"
local aes = require "aes"
local uuid = require "uuid"

local master
local database
local host
local auth_timeout
local session_expire_time
local connection = {}
local saved_session = {}

local CMD = {}

local session = 0
local slave = {}

local socket_error = {}

local function assert_socket(service, v, fd)
    if v then
	return v
    end

    skynet.error(string.format("%s failed: socket (fd = %d) closed", service, fd))
    error(socket_error)
end

local function write(service, fd, text)
    local pack = string.pack(">s2", text)
    assert_socket(service, socket.write(fd, pack), fd)
end

local function read(service, fd)
    local sz = assert_socket(service, socket.read(fd, 2), fd)
    sz = sz:byte(1) * 256 + sz:byte(2)

    local msg = assert_socket(service, socket.read(fd, sz), fd)
    return host:dispatch(msg)
end

local function close(fd)
    assert(connection[fd])
    connection[fd] = nil
    socket.close(fd)
end

local function launch_slave(loginmaster, conf)
    master = loginmaster
    database = skynet.uniqueservice "database"
    host = sprotoloader.load(1):host "package"
    auth_timeout = conf.auth_timeout
    session_expire_time = conf.session_expire_time

    local function auth(fd, addr)
	-- set socket buffer limit (8K)
	-- If the attacker send large package, close the socket
	socket.limit(fd, 8192)

	connection[fd] = addr

	skynet.timeout(auth_timeout * 100, function()
	    if connection[fd] == addr then
		skynet.error(string.format("connection %d from %s auth timeout", fd, addr))
		close(fd)
	    end
	end)

	local type, name, arg, response = read("auth", fd)
	assert("REQUEST" == type)

	if "handshake" == name then
	    assert(arg and arg.name and arg.client_pub, "Invalid handshake request")

	    local account = skynet.call(database, "lua", "account", "load", arg.name)
	    local session_key, _, pkey = srp.create_server_session_key(account.verifier, arg.client_pub)
	    local challenge = srp.random()
	    local msg = response {
		user_exists = account.id ~= nil,
		salt = account.salt,
		server_pub = pkey,
		challenge = challenge,
	    }
	    write("auth", fd, msg)

	    type, name, arg, response = read("auth", fd)
	    assert("REQUEST" == type)
	    assert(name == "auth" and arg and arg.challenge, "Invalid auth request")

	    local text = aes.decrypt(arg.challenge, session_key)
	    assert(challenge == text, "auth challenge failed")

	    local id = tonumber(account.id)
	    if not id then
		assert(arg.password)
		id = uuid.gen()

		local password = aes.decrypt(arg.password, session_key)
		account.id = skynet.call(database, "lua", "account", "create", id, account.name, password)
	    end

	    challenge = srp.random()
	    local session = skynet.call(master, "lua", "save_session", id, session_key, challenge)
	    msg = response {
		session = session,
		expire = session_expire_time * 100,
		challenge = challenge,
	    }
	    write("auth", fd, msg)

	    type, name, arg, response = read("auth", fd)
	    assert("REQUEST" == type)
	end

	assert("challenge" == name)
	assert(arg and arg.session and arg.challenge)

	-- local token, challenge = CMD.challenge(arg.session, arg.challenge)
	local token, challenge = skynet.call(master, "lua", "challenge", arg.session, arg.challenge)
	assert(token and challenge)

	local msg = response {
	    token = token,
	    challenge = challenge,
	}
	write("auth", fd, msg)

	close(fd)

	return true
    end

    local function pack(ok, err, ...)
	if ok then
	    return skynet.pack(err, ...)
	end

	if socket_error == err then
	    return skynet.pack(nil, "socket error")
	end

	return skynet.pack(false, err)
    end

    local function auth_fd(fd, addr)
	skynet.error(string.format("connect from %s (fd = %d)", addr, fd))
	socket.start(fd) -- may raise error here

	local msg, len = pack(pcall(auth, fd, addr))
	socket.abandon(fd) -- never raise error here
	return msg, len
    end

    function CMD.auth(fd, addr)
	local ok, msg, len = pcall(auth_fd, fd, addr)
	if ok then
	    skynet.ret(msg, len)
	else
	    skynet.retpack(false, msg)
	end
    end

    function CMD.save_session(session, account, key, challenge)
	saved_session[session] = {
	    account = account,
	    key = key,
	    challenge = challenge,
	}

	skynet.timeout(session_expire_time * 100, function()
	    local t = saved_session[session]
	    if t and t.key == key then
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

    function CMD.verify(session, secret)
	local t = assert(saved_session[session])
	local text = aes.decrypt(secret, t.key)
	assert(t.token == text)
	t.token = nil

	return t.account
    end

    skynet.dispatch("lua", function(_, _, cmd, ...)
	local f = assert(CMD[cmd])

	if "auth" == cmd then
	    f(...)
	else
	    skynet.retpack(f(...))
	end
    end)
end

local function accept(s, fd, addr)
    -- call slave auth
    local ok, err = skynet.call(s, "lua", "auth", fd, addr)
    -- slave will accept(start) fd, so we can write to fd later

    if not ok then
	error(err)
    end
end

local function launch_master(conf)
    local instance = conf.instance or 8
    assert(instance > 0)

    local host = conf.host or "0.0.0.0"
    local port = assert(tonumber(conf.port))
    local balance = 1

    skynet.dispatch("lua", function(_, _, cmd, ...)
	local f = assert(CMD[cmd])
	skynet.retpack(f(...))
    end)

    for i = 1, instance do
	table.insert(slave, skynet.newservice(SERVICE_NAME))
    end

    skynet.error(string.format("login server listen at: %s %d", host, port))

    local id = socket.listen(host, port)
    socket.start(id, function(fd, addr)
	local s = slave[balance]
	balance = balance + 1
	if balance > #slave then
	    balance = 1
	end

	local ok, err = pcall(accept, s, fd, addr)
	if not ok then
	    if socket_error ~= err then
		skynet.error(string.format("invalid client (fd = %d) error = %s", fd, err))
	    end
	end
    end)

    function CMD.save_session(account, key, challenge)
	session = session + 1
	local s = slave[session % #slave + 1]
	skynet.call(s, "lua", "save_session", session, account, key, challenge)

	return session
    end

    function CMD.challenge(session, challenge)
	local s = slave[session % #slave + 1]
	return skynet.call(s, "lua", "challenge", session, challenge)
    end

    function CMD.verify(session, token)
	local s = slave[session % #slave + 1]
	return skynet.call(s, "lua", "verify", session, token)
    end
end

local function login(conf)
    local name = "." .. (conf.name or "login")

    skynet.start(function()
	local loginmaster = skynet.localname(name)
	if loginmaster then
	    launch_master = nil
	    launch_slave(loginmaster, conf)
	else
	    launch_slave = nil

	    skynet.register(name)
	    launch_master(conf)
	end
    end)
end

return login
