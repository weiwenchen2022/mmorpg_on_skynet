local sprotoparser = require "sprotoparser"

local proto = {}

local types = [[
.package {
    type 0 : integer
    session 1 : integer
}

.general {
    name 0 : string
    race 1 : string
    class 2 : string
    map 3 : string
}

.attribute_overview {
    level 0 : integer
}

.character_overview {
    id 0 : integer
    general 1 : general
    attribute 2 : attribute_overview
}

.attribute {
    health 0 : integer
    level 1 : integer
    exp 2 : integer
    health_max 3 : integer
    strength 4 : integer
    stamina 5 : integer
    attack_power 6 : integer
}

.position {
    x 0 : integer
    y 1 : integer
    z 2 : integer
    o 3 : integer
}

.movement {
    pos 0 : position
}

.character {
    id 0 : integer
    general 1 : general
    attribute 2 : attribute
    movement 3 : movement
}

.attribute_aoi {
    level 0 : integer
    health 1 : integer
    health_max 2 : integer
}

.character_aoi {
    id 0 : integer
    general 1 : general
    attribute 2 : attribute_aoi
    movement 3 : movement
}

.character_aoi_move {
    id 0 : integer
    movement 1 : movement
}
]]

proto.types = sprotoparser.parse(types)

proto.c2s = sprotoparser.parse(types .. [[
handshake 1 {
    request {
	name 0 : string # username
	client_pub 1 : string # srp argument, client public key, known as 'A'
    }

    response {
	user_exists 0 : boolean # 'true' if username is already used
	salt 1 : string # srp argument, salt, known as 's'
	server_pub 2 : string # srp argument, server public key, known as 'B'
	challenge 3 : string # session challenge
    }
}

auth 2 {
    request {
	challenge 0 : string # encrypted challenge
	password 1 : string # encrypted password. send this ONLY IF you're registrying new account
    }

    response {
	session 0 : integer # login session id, needed for further use
	expire 1 : integer # session expire time, in second
	challenge 2 : string # token request challenge
    }
}

challenge 3 {
    request {
	session 0 : integer # login session id
	challenge 1 : string # encryped challenge
    }

    response {
	token 0 : string # login token
	challenge 1 : string # next token challenge
    }
}

login 4 {
    request {
	session 0 : integer # login session id
	token 1 : string # encryped token
    }

    response {
	ok 0 : boolean
	error 1 : string
    }
}

character_list 5 {
    response {
	character 0 : *character_overview(id)
    }
}

character_create 6 {
    request {
	character 0 : general
    }

    response {
	err 0 : string
	character 1 : character_overview
    }
}

character_pick 7 {
    request {
	id 0 : integer
    }

    response {
	ok 0 : boolean
	character 1 : character
    }
}

map_ready 8 {

}

move 9 {
    request {
	pos 0 : position
    }

    response {
	pos 0 : position
    }
}
]])

proto.s2c = sprotoparser.parse(types .. [[
aoi_add 1 {
    request {
	character 0 : character_aoi
    }

    response {
	wantmore 0 : boolean
    }
}

aoi_remove 2 {
    request {
	character 0 : integer
    }
}

aoi_update_move 3 {
    request {
	character 0 : character_aoi_move
    }

    response {
	wantmore 0 : boolean
    }
}
]])

return proto
