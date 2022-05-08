local constant = require "constant"
local srp = require "srp"
local skynet = require "skynet"

local M = setmetatable({}, {__index = _ENV,})
_ENV = M

local db

function init(c)
    skynet.error("account.init")

    db = c
end

local function make_key(name)
    return string.format("user:%s", name)
end

function load(name)
    skynet.error("account.load", name)

    local acc = {name = name,}
    local key = make_key(name)

    if db:exists(key) then
	acc.id, acc.salt, acc.verifier = table.unpack(db:hmget(key, "id", "salt", "verifier"))
    else
	acc.salt, acc.verifier = srp.create_verifier(name, constant.default_password)
    end

    return acc
end

function create(id, name, password)
    skynet.error("account.create", name, password)

    local key = make_key(name)
    assert(db:hsetnx(key, "id", id) == 1, "account exists")

    local salt, verifier = srp.create_verifier(name, password)
    assert(db:hmset(key, "salt", salt, "verifier", verifier) == "OK")

    return id
end

return M
