local table, math, string = table, math, string
local table_unpack, table_insert, table_concat = table.unpack, table.insert, table.concat
local error, setmetatable, tostring, type = error, setmetatable, tostring, type
local math_huge, math_floor = math.huge, math.floor
local string_match, string_gsub, string_format = string.match, string.gsub, string.format

local library = {}

----------------------------------------------------

local result_methods = {}

function result_methods:unwrap()
    local value = self.value
    if self.success then
        return table_unpack(value)
    else
        error(value, 2)
    end
end

function result_methods:extract()
    local value = self.value
    if self.success then
        return true, table_unpack(value)
    else
        return false, value
    end
end

local result_meta = {
    __index = result_methods;
}

local function result_success(...)
    local result = {
        success = true;
        value = { ... };
    }
    return setmetatable(result, result_meta)
end

local function result_failure(err)
    local result = {
        success = false;
        value = err;
    }
    return setmetatable(result, result_meta)
end

local function result_catching(action, ...)
    local r = { action(...) }
    if r[1] then
        return result_success(table_unpack(r, 2))
    else
        return result_failure(r[2])
    end
end

library.result = {
    success = result_success;
    failure = result_failure;
    catching = result_catching;
}

----------------------------------------------------

local function math_type(value)
    if type(value) ~= 'number' then
        return nil
    end
    if value == math_huge or value == -math_huge or value ~= math_floor(value) then
        return 'float'
    end
    return 'integer'
end

local function append_value(strings, value)
    if type(value) == 'string' then
        local formated = string_gsub(string_format("%q", value), "\\\n", "\\n")
        table_insert(strings, formated)
    elseif math_type(value) == 'float' then
        if value ~= value then
            table_insert(strings, "0/0")
        elseif value == math_huge then
            table_insert(strings, "1/0")
        elseif value == -math_huge then
            table_insert(strings, "-1/0")
        else
            table_insert(strings, tostring(value))
        end
    else
        table_insert(strings, tostring(value))
    end
end

local function datum_tostring(self)
    local strings = {"{"}
    local size = #self
    for i=1, size do
        append_value(strings, self[i])
        table_insert(strings, ",")
    end
    for key, value in pairs(self) do
        if not (math_type(key) == 'integer' and key >= 1 and key <= size) then
            if type(key) == 'string' and string_match(key, '^[_%a][_%w]*$') then
                table_insert(strings, key)
            else
                table_insert(strings, "[")
                append_value(strings, key)
                table_insert(strings, "]")
            end
            table_insert(strings, "=")
            append_value(strings, value)
            table_insert(strings, ",")
        end
    end
    if #strings == 1 then
        return "{}"
    end
    strings[#strings] = '}'
    return table.concat(strings)
end

local function datum_eq(a, b)
    local keys = {}
    for key1, value1 in pairs(a) do
        local value2 = b[key1]
        if value2 == nil or value1 ~= value2 then
            return false
        end
        keys[key1] = true
    end
    for key2, _ in pairs(b) do
        if not keys[key2] then return false end
    end
    return true
end

local datum_meta = {
    __tostring = datum_tostring;
    __eq = datum_eq;
}

local datum_create
function datum_create(value, recursive)
    local result = setmetatable(value, datum_meta)
    if recursive then
        for _, child in pairs(value) do
            if type(child) == 'table' then
                datum_create(child, true)
            end
        end
    end
    return result
end

library.datum = datum_create

----------------------------------------------------

return library
