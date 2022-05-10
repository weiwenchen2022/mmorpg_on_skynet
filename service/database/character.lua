local cmsgpack = require "cmsgpack"
local skynet = require "skynet"

local _M = setmetatable({}, {__index = _ENV,})
_ENV = _M

local db

function init(c)
    db = c
end

local function make_set_key(account)
    return string.format("character-set:%d", account)
end

local function make_character_key(id)
    return string.format("character:%d", id)
end

function reserve(id, name)
    if db:hsetnx("character-name", name, id) ~= 1 then
	return nil, "name already exists"
    end

    return id
end

function save(id, data)
    local key = make_character_key(id)
    skynet.error("save", id, data)

    data = cmsgpack.pack(data)
    db:hset(key, "base", data)
end

function load(id)
    local key = make_character_key(id)
    local data = assert(db:hget(key, "base"))
    data = cmsgpack.unpack(data)

    return data
end

function load_list(account)
    local key = make_set_key(account)
    local data = db:smembers(key)

    for i, v in ipairs(data) do
	data[i] = tonumber(v)
    end

    return data
end

function add_list(account, id)
    local key = make_set_key(account)
    assert(db:sadd(key, id) == 1)
end

return _M
