local core = require "uuid.core"
local skynet = require "skynet"

-- uuid format: (33 bits timestamp) (6 bits harbor)(15 bits service) (10 bits sequence)
local M = setmetatable({}, {__index = _ENV,})
_ENV = M

local timestamp
local service
local sequence

function gen()
    if not service then
	local sid = core.sid()
	local harbor = skynet.harbor(skynet.self())
	service = ((harbor & 0x3f) << 25) | ((sid & 0xffff) << 10)
    end

    if not timestamp then
	timestamp = (os.time() << 31) | service
	sequence = 0

	skynet.timeout(100, function()
	    timestamp = nil
	end)
    end

    sequence = sequence + 1
    assert(sequence < 1024)

    return (timestamp | sequence)
end

function split(id)
    local sequence = id & 0x3ff
    local service = (id >> 10) & 0x7fff
    local harbor = (id >> 25) & 0x3f
    local timestamp = id >> 31

    return timestamp, harbor, service, sequence
end

return M
