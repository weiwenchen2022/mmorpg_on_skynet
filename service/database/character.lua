local skynet = require "skynet"
local cmsgpack = require "cmsgpack"

local _M = setmetatable({}, {__index = _ENV,})
_ENV = _M

local db
function init(c)
    db = c
end

local function make_list_key(account)
    return string.format("character-list:%d", account)
end

local function make_character_key(id)
    return string.format("character:%d", id)
end

function reserve(id, name)
    assert(db:hsetnx("character-name", name, id) == 1)
    return id
end

function save(id, data)
    skynet.error("save", id, data)

    local key = make_character_key(id)
    data = cmsgpack.pack(data)
    db:hset(key, "base", data)
end

function load(id)
    local key = make_character_key(id)
    local data = assert(db:hget(key, "base"))
    data = cmsgpack.unpack(data)

    skynet.error("character, load", id, data)
    return data
end

function load_list(account)
    local key = make_list_key(account)
    local data = db:get(key)
    data = data and cmsgpack.unpack(data) or {}

    for i, v in ipairs(data) do
	data[i] = tonumber(v)
    end

    skynet.error("load_list", account, key, data)

    return data
end

function save_list(account, data)
    local key = make_list_key(account)
    skynet.error("save_list", account, key, data)

    data = cmsgpack.pack(data)
    db:set(key, data)
end

return _M
