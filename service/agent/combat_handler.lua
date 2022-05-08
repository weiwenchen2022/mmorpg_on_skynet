local skynet = require "skynet"
local handler = require "handler"

local REQUEST = {}
local CMD = {}
local user
local _M = handler.new(REQUEST, nil, CMD)
_ENV = _M

_M:init(function(u)
    user = u
end)

function REQUEST:combat(arg)
    assert(arg and arg.target)

    local tid = arg.target
    local agent = aoi_handler.find(tid)
    assert(agent)

    local damage = self.character.attribute.attack_power
    damage = skynet.call(agent, "lua", "combat_melee_damage", user.character.id, damage)

    return {target = tid, damage = damage,}
end

function CMD.combat_melee_damage(source, attacker, damage)
    damage = math.floor(damage * 0.75)

    local hp = user.character.attribute.health - damage
    if hp <= 0 then
	damage = damage + hp
	hp = user.character.attribute.health_max
    end

    user.character.attribute.health = hp

    aoi_handler.boardcast "attribute"
    return damage
end

return _M
