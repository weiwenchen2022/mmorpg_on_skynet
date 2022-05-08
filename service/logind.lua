local login = require "loginserver"
local skynet = require "skynet"

local server = {
    host = skynet.getenv "loginserver_host",
    port = assert(tonumber(skynet.getenv "loginserver_port")),
    auth_timeout = assert(tonumber(skynet.getenv "auth_timeout")),
    session_expire_time = assert(tonumber(skynet.getenv "session_expire_time")),
    name = "login_master",
}

login(server)
