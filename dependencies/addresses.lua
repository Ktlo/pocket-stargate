local DEFAULT_LOCATION = "file:addresses.conf"

---------------------------------------------

settings.define("psg.addressesLocation", {
    description = "Stargate addresses file location",
    default = DEFAULT_LOCATION,
    type = "string",
})

local location = settings.get("psg.addressesLocation", DEFAULT_LOCATION)

local addressesTable

do -- init
    local addressesString

    if location:sub(1, 5) == "file:" then
        local file = assert(io.open(location:sub(6)))
        addressesString = file:read("a")
        file:close()
    elseif location:sub(1, 5) == "http:" or location:sub(1, 6) == "https:" then
        local file = http.get(location)
        addressesString = file.readAll()
        file.close()
    else
        error("unsupported location: "..location)
    end

    addressesTable = load("return "..addressesString, "addresses", 't', {})()
end

local addresses = {}

function addresses.interstellar(galaxies, solarSystem)
    local result = {}
    for _, solar in ipairs(addressesTable.position or {}) do
        if solar.key ~= solarSystem then
            if solar.interstellar then
                for _, galaxy in ipairs(galaxies) do
                    local address = solar.interstellar[galaxy]
                    if address then
                        local record = {
                            name = solar.name or "?????",
                            address = address
                        }
                        table.insert(result, record)
                        break
                    end
                end
            end
        end
    end
    return result
end

function addresses.extragalactic(galaxies)
    local result = {}
    for _, solar in ipairs(addressesTable.position or {}) do
        if solar.extragalactic then
            local notSkip = true
            for _, galaxy in ipairs(galaxies) do
                if solar.interstellar[galaxy] then
                    notSkip = false
                    break
                end
            end
            if notSkip then
                local record = {
                    name = solar.name or "?????",
                    address = solar.extragalactic
                }
                table.insert(result, record)
            end
        end
    end
    return result
end

local function tableEquals(a, b)
    if #a == #b then
        for i = 1, #a do
            if a[i] ~= b[i] then
                return false
            end
        end
        return true
    else
        return false
    end
end

function addresses.direct(localAddress)
    local result = {}
    for _, record in ipairs(addressesTable.identity or {}) do
        if not localAddress or not tableEquals(record.address, localAddress) then
            table.insert(result, record)
        end
    end
    return result
end

function addresses.tostring(address)
    return table.concat(address, '-')
end

local nameByAddress = {}

for _, record in ipairs(addressesTable.identity or {}) do
    nameByAddress[addresses.tostring(record.address)] = record.name
end

local function galaxy_key(galaxy, address)
    return galaxy..":"..addresses.tostring(address)
end

for _, record in ipairs(addressesTable.position or {}) do
    local extragalactic = record.extragalactic
    if extragalactic then
        nameByAddress[addresses.tostring(extragalactic)] = record.name
    end
    for galaxy, address in pairs(record.interstellar or {}) do
        local key = galaxy_key(galaxy, address)
        nameByAddress[key] = record.name
    end
end

addresses.h = nameByAddress

function addresses.getname_by_key(key)
    for _, solar in ipairs(addressesTable.position or {}) do
        local name = solar.name
        if solar.key == key and name then
            return name
        end
    end
    return nil
end

function addresses.getname(address, galaxies)
    local n = #address
    if n == 6 then
        if galaxies then
            for _, galaxy in ipairs(galaxies) do
                local key = galaxy_key(galaxy, address)
                local name = nameByAddress[key]
                if name then
                    return name
                end
            end
        end
        return nil
    else
        return nameByAddress[addresses.tostring(address)]
    end
end

return addresses
