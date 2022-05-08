local skynet = require "skynet"
local gdd = require "gdd"
local handler = require "handler"
local uuid = require "uuid"

local REQUEST = {}
local _M = handler.new(REQUEST)
_ENV = _M

local database
local world

local function load_list(account)
    local list = skynet.call(database, "lua", "character", "load_list", account)
    return list
end

local function check_character(account, id)
    skynet.error("check_character", account, id)

    local list = load_list(account)
    for _, v in pairs(list) do
	if id == v then return true end
    end

    return false
end

function REQUEST:character_list()
    local list = load_list(self.account)
    local character = {}

    skynet.error("character_list", #list, self.account)

    for _, id in pairs(list) do
	local c = skynet.call(database, "lua", "character", "load", id)
	if c then
	    character[id] = c
	end
    end

    return {character = character,}
end

local function create_character(name, race, class)
    assert(type(name) == "string" and 2 < #name and #name < 24)
    assert(race)
    assert(gdd["class"][class])

    local r = assert(gdd["race"][race])

    local character = {
	general = {
	    name = name,
	    race = race,
	    class = class,
	    map = r.home,
	},

	attribute = {
	    level = 1,
	    exp = 0,
	},

	movement = {
	    mode = 0,
	    pos = {x = r.pos_x, y = r.pos_y, z = r.pos_z, o = r.pos_o,},
	},
    }

    return character
end

function REQUEST:character_create(arg)
    local c = assert(arg.character)
    local character = create_character(c.name, c.race, c.class)

    local id = skynet.call(database, "lua", "character", "reserve", uuid.gen(), c.name)
    if not id then return {ok = false,} end

    skynet.error("character_create", id)

    character.id = id
    skynet.call(database, "lua", "character", "save", id, character)

    local list = load_list(self.account)
    table.insert(list, id)
    skynet.call(database, "lua", "character", "save_list", self.account, list)

    return {ok = true, character = character,}
end

function REQUEST:character_pick(arg)
    local id = assert(arg.id)
    assert(check_character(self.account, id))

    local character = skynet.call(database, "lua", "character", "load", id)
    self.character = character

    skynet.call(world, "lua", "character_enter", id)
    return {ok = true, character = character,}
end

function init(character)
    local temp_attribute = {{}, {},}
    local attribute_count = #temp_attribute

    character.runtime = {
	temp_attribute = temp_attribute,
	attribute = temp_attribute[attribute_count],
    }

    local class, race, level = character.general.class, character.general.race, character.attribute.level
    skynet.error("math.type(level)", math.type(level))

    local attribute = gdd.attribute
    local base = temp_attribute[1]
    base.health_max = attribute.health_max[class][level]
    base.strength = attribute.strength[race][level]
    base.stamina = attribute.stamina[race][level]
    base.attack_power = 0

    local final = temp_attribute[attribute_count]

    if base.stamina >= 20 then
	final.health_max = base.health_max + 20 + (base.stamina - 20) * 10
    else
	final.health_max = base.health_max + base.stamina
    end

    final.strength = base.strength
    final.stamina = base.stamina
    final.attack_power = base.attack_power + final.strength

    local attribute = setmetatable(character.attribute, {__index = character.runtime.attribute,})

    local health = attribute.health
    if not health or health > attribute.health_max then
	attribute.health = attribute.health_max
    end
end

function save(character)
    local runtime = character.runtime
    character.runtime = nil

    skynet.call(database, "lua", "character", "save", character.id, character)
    character.runtime = runtime
end

skynet.init(function()
    database = skynet.uniqueservice "database"
    world = skynet.uniqueservice "world"
end)

return _M
