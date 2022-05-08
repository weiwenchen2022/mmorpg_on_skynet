local _M = setmetatable({}, {__index = _ENV,})
_ENV = _M

local handler = setmetatable({}, {__index = _ENV,})
local meta = {__index = handler,}

function handler:init(f)
    table.insert(self.init_func, f)
end

local function merge(dest, src)
    if not dest or not src then return end

    for k, v in pairs(src) do
	assert(not dest[k], "key '" .. k .. "' already exists")
	dest[k] = v
    end
end

function handler:register(user)
    for _, f in pairs(self.init_func) do
	f(user)
    end

    merge(user.REQUEST, self.request)
    merge(user.RESPONSE, self.response)
    merge(user.CMD, self.cmd)
end

local function clean(dest, src)
    if not dest or not src then return end

    for k in pairs(src) do
	dest[k] = nil
    end
end

function handler:unregister(user)
    clean(user.REQUEST, self.request)
    clean(user.RESPONSE, self.response)
    clean(user.CMD, self.cmd)
end

function new(request, response, cmd)
    return setmetatable({
	request = request,
	response = response,
	cmd = cmd,
	init_func = {},
    }, meta)
end

return _M
