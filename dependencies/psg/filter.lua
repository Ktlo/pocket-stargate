local ALLOWLIST_FILE = "allowlist.txt"
local DENYLIST_FILE = "denylist.txt"

-----------------------------------------------

local stargate = peripheral.find 'advanced_crystal_interface'

local function ADDRESS_PATTERN(n)
    return "^%-"..("(%d+)-"):rep(n).."$"
end
local SYMBOL7_PATTERN = ADDRESS_PATTERN(6)
local SYMBOL8_PATTERN = ADDRESS_PATTERN(7)
local SYMBOL9_PATTERN = ADDRESS_PATTERN(8)

local function parseAddressParts(address)
    local symbol7 = { address:match(SYMBOL7_PATTERN) }
    if next(symbol7) then
        return symbol7
    end
    local symbol8 = { address:match(SYMBOL8_PATTERN) }
    if next(symbol8) then
        return symbol8
    end
    local symbol9 = { address:match(SYMBOL9_PATTERN) }
    if next(symbol9) then
        return symbol9
    end
    return nil
end

local function parseAddress(address)
    local parts = parseAddressParts(address)
    if not parts then
        return nil
    end
    for i in ipairs(parts) do
        parts[i] = tonumber(parts[i])
    end
    return parts
end

local function loadAddresses(filename)
    local result = {}
    local file = io.open(filename, 'r')
    if file then
        for line in file:lines 'l' do
            local address = parseAddress(line)
            if address then
                result[line] = address
            end
        end
    end
    return result
end

local allowlist = loadAddresses(ALLOWLIST_FILE)
local denylist = loadAddresses(DENYLIST_FILE)

local filter = {}

-----------------------------------------------

local function addressToString(address)
    return '-'..table.concat(address, '-')..'-'
end

local function listAdd(list, method, filename, address)
    local str = addressToString(address)
    if list[str] then
        return false
    end
    method(address, false)
    list[str] = address
    local file = assert(io.open(filename, 'a'))
    file:write(str)
    file:write('\n')
    file:close()
    return true
end

function filter.allowlist_add(address)
    return listAdd(allowlist, stargate.addToWhitelist, ALLOWLIST_FILE, address)
end

function filter.denylist_add(address)
    return listAdd(denylist, stargate.addToBlacklist, DENYLIST_FILE, address)
end

local function listDel(list, method, filename, address)
    local str = addressToString(address)
    if not list[str] then
        return false
    end
    method(address)
    list[str] = nil
    local file = assert(io.open(filename, 'w'))
    for item in pairs(list) do
        file:write(item)
        file:write('\n')
    end
    file:close()
    return true
end

function filter.allowlist_del(address)
    return listDel(allowlist, stargate.removeFromWhitelist, ALLOWLIST_FILE, address)
end

function filter.denylist_del(address)
    return listDel(denylist, stargate.removeFromBlacklist, DENYLIST_FILE, address)
end

local function listSynch(list, clearMethod, addMethod)
    clearMethod()
    for _, address in pairs(list) do
        addMethod(address, false)
    end
end

function filter.allowlist_synch()
    listSynch(allowlist, stargate.clearWhitelist, stargate.addToWhitelist)
end

function filter.denylist_synch()
    listSynch(denylist, stargate.clearBlacklist, stargate.addToBlacklist)
end

local function listGetall(list)
    local result = {}
    for _, address in pairs(list) do
        table.insert(result, address)
    end
    return result
end

function filter.allowlist_getall()
    return listGetall(allowlist)
end

function filter.denylist_getall()
    return listGetall(denylist)
end

-----------------------------------------------

return filter
