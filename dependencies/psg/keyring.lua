
local AUTHORIZED_KEYS_FILE = "keyring.txt"

-------------------------------

local base64 = require 'ktlo.base64'

local function read_key(line)
    local key, name = line:match "^([%w+=/]+)%s+(.+)$"
    if key then
        return key, name
    else
        return line
    end
end

local authorizedKeys = {}
do
    local file = io.open(AUTHORIZED_KEYS_FILE, 'r')
    if file then
        for line in file:lines('l') do
            local key, name = read_key(line)
            authorizedKeys[base64.decode(key)] = {key=key, name=name}
        end
        file:close()
    end
end

local keyring = {
    keys = authorizedKeys;
}

-----------------------------------------------

keyring.read_key = read_key

function keyring.get_all()
    local result = {}
    for _, key in pairs(authorizedKeys) do
        table.insert(result, key)
    end
    return result
end

local function write_key(file, keyinfo)
    file:write(keyinfo.key)
    local name = keyinfo.name
    if name then
        file:write(' ')
        file:write(name)
    end
    file:write('\n')
end

local function save_keys()
    local file = io.open(AUTHORIZED_KEYS_FILE, 'w')
    if not file then
        error("file '"..AUTHORIZED_KEYS_FILE.."' cannot be opened for writing")
    end
    for _, keyinfo in pairs(authorizedKeys) do
        write_key(file, keyinfo)
    end
    file:close()
end

function keyring.exists(key)
    local decoded = base64.decode(key)
    return authorizedKeys[decoded]
end

function keyring.trust(key, name)
    local decoded = base64.decode(key)
    local old = authorizedKeys[decoded]
    if old then
        if old.name ~= name then
            old.name = name
        end
        save_keys()
        return false
    end
    authorizedKeys[decoded] = { key=key, name=name }
    save_keys()
    return true
end

function keyring.forget(key)
    key = base64.decode(key)
    if not authorizedKeys[key] then
        return false
    end
    authorizedKeys[key] = nil
    save_keys()
    return true
end

-----------------------------------------------

return keyring
