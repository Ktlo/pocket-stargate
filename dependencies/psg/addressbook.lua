local DEFAULT_LOCATION = "file:addresses.conf"

---------------------------------------------

local address = require 'psg.address'

settings.define("psg.addressesLocation", {
    description = "Stargate addresses file location",
    default = DEFAULT_LOCATION,
    type = "string",
})

local mLocation = settings.get("psg.addressesLocation", DEFAULT_LOCATION)

local library = {}

function library.get_location()
    return mLocation
end

local function resolve_location_from(location)
    if location:sub(1, 5) == "file:" then
        return 'file', location:sub(6)
    elseif location:sub(1, 5) == "http:" or location:sub(1, 6) == "https:" then
        return 'web', location
    else
        error("unsupported location: "..location)
    end
end

function library.set_location(value)
    resolve_location_from(value)
    mLocation = value
    settings.set("psg.addressesLocation", value)
    settings.save()
end

local function resolve_location()
    return resolve_location_from(mLocation)
end

local function transformAddress(object)
    if object == nil then
        return nil
    end
    if type(object) == "table" then
        return address.create(table.unpack(object))
    else
        return address.parse(object)
    end
end

local function transformAddressbook(addresses)
    local identity = {}
    if addresses.identity then
        for i, record in ipairs(addresses.identity) do
            identity[i] = {
                name = record.name;
                address = transformAddress(record.address);
            }
        end
    end
    local position = {}
    if addresses.position then
        for i, record in ipairs(addresses.position) do
            local interstellar = {}
            if record.interstellar then
                for galaxy, addr in pairs(record.interstellar) do
                    interstellar[galaxy] = transformAddress(addr)
                end
            end
            position[i] = {
                name = record.name;
                key = record.key;
                interstellar = interstellar;
                extragalactic = transformAddress(record.extragalactic);
            }
        end
    end
    return {
        position = position,
        identity = identity,
    }
end

--- @async
--- @return psg.addressbook?, string?
function library.load()
    local kind, location = resolve_location()
    local addressesString
    if kind == 'file' then
        local file = assert(io.open(location))
        addressesString = file:read("a")
        file:close()
    elseif kind == 'web' then
        local file = assert(http.get(location))
        addressesString = file.readAll()
        file.close()
    end
    local r, err = textutils.unserialise(addressesString)
    if not r then
        local z, err2 = textutils.unserialiseJSON(addressesString)
        if not z then
            return nil, err
        end
        r = z
    end
    return transformAddressbook(r)
end

local function transformBackAddressbook(addresses)
    local position
    if next(addresses.position) then
        position = {}
        for i, record in ipairs(addresses.position) do
            local interstellar
            if next(record.interstellar) then
                interstellar = {}
                for galaxy, addr in pairs(record.interstellar) do
                    interstellar[galaxy] = tostring(addr)
                end
            end
            position[i] = {
                name = record.name;
                key = record.key;
                interstellar = interstellar;
                extragalactic = record.extragalactic and tostring(record.extragalactic);
            }
        end
    end
    local identity
    if next(addresses.identity) then
        identity = {}
        for i, record in ipairs(addresses.identity) do
            identity[i] = {
                name = record.name;
                address = record.address and tostring(record.address);
            }
        end
    end
    return {
        position = position;
        identity = identity;
    }
end

--- @async
function library.save(addresses)
    addresses = transformBackAddressbook(addresses)
    local kind, location = resolve_location()
    if kind == 'file' then
        local content
        if location:sub(-5) == ".json" then
            content = textutils.serialiseJSON(addresses)
        else
            content = textutils.serialise(addresses)
        end
        local file = assert(io.open(location, "w"))
        file:write(content)
        file:write('\n')
        file:close()
        return true
    elseif kind == 'web' then
        return false, "unsupported operation: saving to web location"
    end
end

return library
