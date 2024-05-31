
local LOCATION = "file:addresses.conf"

---------------------------------------------

local addressesTable

do -- init
    local addressesString

    if LOCATION:sub(1, 5) == "file:" then
        local file = assert(io.open(LOCATION:sub(6)))
        addressesString = file:read("a")
        file:close()
    elseif LOCATION:sub(1, 5) == "http:" or LOCATION:sub(1, 6) == "https:" then
        local file = http.get(LOCATION)
        addressesString = file.readAll()
        file.close()
    else
        error("unsupported location: "..LOCATION)
    end

    addressesTable = load("return "..addressesString, "addresses", 't', {})()
end

local addresses = {}

function addresses.interstellar(galaxies, solarSystem)
    local result = {}
    for _, solar in ipairs(addressesTable.position) do
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
    for _, solar in ipairs(addressesTable.position) do
        if solar.extragalactic then
            for _, galaxy in ipairs(galaxies) do
                if solar.interstellar[galaxy] then
                    goto skip
                end
            end
            local record = {
                name = solar.name or "?????",
                address = solar.extragalactic
            }
            table.insert(result, record)
            ::skip::
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
    for _, record in ipairs(addressesTable.identity) do
        if not localAddress or not tableEquals(record.address, localAddress) then
            table.insert(result, record)
        end
    end
    return result
end

return addresses
