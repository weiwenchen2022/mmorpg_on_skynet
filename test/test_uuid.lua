package.cpath = "luaclib/?.so;" .. package.cpath
local uuid = require "uuid.core"

for i = 1, 10 do
    print(uuid.sid())
end
