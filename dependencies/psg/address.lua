local table, math, string = table, math, string
local table_concat, table_pack = table.concat, table.pack
local type, tonumber, error = type, tonumber, error
local debug_getmetatable = debug.getmetatable
local string_rep, string_match = string.rep, string.match

--- @class psg.address
--- @field n integer
--- @field kind string
local address_index = {}

local address_meta = {
    __tostring = function(self)
        return "-"..table_concat(self, "-").."-"
    end;
    __eq = function(self, other)
        local meta = debug_getmetatable(other)
        if meta.__name ~= 'address' then
            return false
        end
        local n = self.n
        if n ~= other.n then
            return false
        end
        for i=1, n do
            if self[i] ~= other[i] then
                return false
            end
        end
        return true
    end;
    __name = 'address';
}

--- @param ... integer
--- @return psg.address
local function address_create(...)
    local address = table_pack(...)
    local size = address.n
    local kind
    if size == 6 then
        kind = 'interstellar'
    elseif size == 7 then
        kind = 'extragalactic'
    elseif size == 8 then
        kind = 'systemwide'
    else
        error("unexpected symbol count in address (6, 7, or 8 symbols expected, got "..size..")", 2)
    end
    local seen = {}
    for i=1, #address do
        local symbol = tonumber(address[i])
        if type(symbol) ~= 'number' then
            error("each symbol must be an integer number", 2)
        end
        symbol = math.floor(symbol)
        if symbol < 1 or symbol > 47 then
            error("symbol #"..i.." is out of expected range [1;47]: "..symbol, 2)
        end
        if seen[symbol] then
            error("symbol '"..symbol.."' appered several times in address", 2)
        end
        seen[symbol] = true
        address[i] = symbol
    end
    address.kind = kind
    return setmetatable(address, address_meta)
end

local function address_pattern(n)
    return "^-"..string_rep("(%d+)-", n).."$"
end

local S6_ADDRESS = address_pattern(6)
local S7_ADDRESS = address_pattern(7)
local S8_ADDRESS = address_pattern(8)

local function try_parsed(...)
    if ... then
        return address_create(...)
    end
end

local function try_parse_by(str, ...)
    for i=1, select('#', ...) do
        local pattern = select(i, ...)
        local address = try_parsed(string_match(str, pattern))
        if address then
            return address
        end
    end
    error("not an address string", 2)
end

---@param str string
---@return psg.address
local function address_parse(str)
    return try_parse_by(str, S6_ADDRESS, S7_ADDRESS, S8_ADDRESS)
end

---@param str string
---@return integer
local function address_sizeof(str)
    if str == 'interstellar' then
        return 6
    elseif str == 'extragalactic' then
        return 7
    elseif str == 'systemwide' then
        return 8
    else
        error("unknown address type: "..str, 2)
    end
end

return {
    create = address_create;
    parse = address_parse;
    sizeof = address_sizeof;
}
