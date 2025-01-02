local type, select, rawget, tostring, error, debug, table = type, select, rawget, tostring, error, debug, table
local debug_getmetatable = debug.getmetatable
local table_concat, table_remove = table.concat, table.remove

local library = {}

----------------------------------------------------

local function get_display_type(value, t)
    -- Lua is somewhat inconsistent in whether it obeys __name just for values which
    -- have a per-instance metatable (so tables/userdata) or for everything. We follow
    -- Cobalt and only read the metatable for tables/userdata.
    if t ~= "table" and t ~= "userdata" then return t end

    local metatable = debug_getmetatable(value)
    if not metatable then return t end

    local name = rawget(metatable, "__name")
    if type(name) == "string" then return name else return t end
end

local function get_type_names(...)
    local types = { ... }
    for i = #types, 1, -1 do
        if types[i] == "nil" then table_remove(types, i) end
    end
    if #types <= 1 then
        return tostring(...)
    else
        return table_concat(types, ", ", 1, #types - 1) .. " or " .. types[#types]
    end
end

local function compare_type(value, native_type, expected_type)
    if native_type == expected_type then
        return true
    end
    if native_type ~= "table" and native_type ~= "userdata" then return false end
    local metatable = debug_getmetatable(value)
    if not metatable then return false end
    local name = rawget(metatable, "__name")
    if name == expected_type then
        return true
    end
    local classes = metatable.__classes
    if not classes then return false end
    if classes[expected_type] then
        return true
    end
    return false
end

--- Expect an argument to have a specific type.
---
--- @generic T
--- @param index integer The 1-based argument index.
--- @param value T The argument's value.
--- @param ... string The allowed types of the argument.
--- @return T value The given `value`.
--- @throws If the value is not one of the allowed types.
function library.expect(index, value, ...)
    local native_type = type(value)
    for i = 1, select("#", ...) do
        local expected_type = select(i, ...)
        if compare_type(value, native_type, expected_type) then return value end
    end

    local t = get_display_type(value, native_type)

    -- If we can determine the function name with a high level of confidence, try to include it.
    local name
    local ok, info = pcall(debug.getinfo, 3, "nS")
    if ok and info.name and info.name ~= "" and info.what ~= "C" then name = info.name end

    local type_names = get_type_names(...)
    if name then
        error(("bad argument #%d to '%s' (%s expected, got %s)"):format(index, name, type_names, t), 3)
    else
        error(("bad argument #%d (%s expected, got %s)"):format(index, type_names, t), 3)
    end
end

----------------------------------------------------

return library
