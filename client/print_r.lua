local print = print
local tconcat = table.concat
local tinsert = table.insert
local srep = string.rep
local type = type
local pairs = pairs
local tostring = tostring
local next = next

local function dump(t, space, name, cached)
    cached = cached or {[t] = ".",}
    local list = {}

    for k, v in pairs(t) do
	local key = type(k) == "string" and k or string.format("%q", k)

	if type(v) == "table" then
	    if cached[v] then
		tinsert(list, "+" .. key .. " {" .. cached[v] .. "}")
	    else
		local new_key = name .. "." .. key
		cached[v] = new_key

		tinsert(list,
		    "+" .. key .. dump(v, space .. (next(t, k) and "|" or " ") .. srep(" ", #key), new_key, cached))
	    end
	else
	    tinsert(list, "+" .. key .. " [" .. string.format("%q", v) .. "]")
	end
    end

    return tconcat(list, "\n" .. space)
end

local function print_r(root)
    print(dump(root, "", ""))
end

return print_r
