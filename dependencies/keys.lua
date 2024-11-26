local base64 = require 'base64'

local lib = {}

local function halfing(value)
    local size = (#value)/2
    local most = value:sub(1, size)
    local least = value:sub(size + 1)
    local result = {}
    for i=1, size do
        result[i] = string.char(bit.bxor(most:byte(i), least:byte(i)))
    end
    return table.concat(result, '')
end

local zero = ('0'):byte(1)
local a = ('A'):byte(1)

local function encodeHexCode(code)
    local symbol
    if code < 10 then
        symbol = zero + code
    else
        symbol = a + code
    end
    return string.char(symbol)
end

local function encodeChar(char)
    return encodeHexCode(bit.brshift(char, 4))..encodeHexCode(bit.band(char, 15))
end

local function encodeHex(str)
    local r = {}
    for i=1, #str do
        table.insert(r, encodeChar(str:byte(i)))
    end
    return table.concat(r, '')
end

function lib.fingerprint(key)
    return encodeHex(halfing(halfing(base64.decode(key))))
end

return lib
