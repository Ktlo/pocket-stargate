print("Installing SGS...")
print("Checking peripherals...")
if not (peripheral.find "advanced_crystal_interface" or peripheral.find "crystal_interface" or peripheral.find "basic_interface") then
    print("Stargate interface not found!")
    typeY()
end
if not peripheral.find("modem") then
    print("Modem not found!")
    typeY()
end
print("Peripherals OK")

write("Name current solar system: ")
local solarSystem = read(nil, nil, nil, settings.get("solarSystem", "sgjourney:terra"))

local oldGalaxies = settings.get("galaxies", {"sgjourney:milky_way"})
local galaxies = {}

print("Please, enter names of galaxies where the stargate is located at (empty input means end of list)")
while true do
    local n = #galaxies + 1
    write("Name galaxy #"..n..": ")
    local galaxy = read(nil, nil, nil, oldGalaxies[n])
    if galaxy == "" then break end
    table.insert(galaxies, galaxy)
end

local ADDRESS_PATTERN = ("(%d+)."):rep(7).."(%d+)"

local function addr2str(address)
    return '-'..table.concat(address, '-')..'-'
end
local localAddress, localAddressString
localAddress = settings.get("psg.localAddress")
if localAddress then
    localAddressString = addr2str(localAddress)
end
print("You can specify local address (real or fake)")
while true do
    write("Local address: ")
    localAddressString = read(nil, nil, nil, localAddressString)
    if localAddressString == "" then
        print("No local address specified")
        localAddress = nil
        break
    end
    local address = { localAddressString:match(ADDRESS_PATTERN) }
    if #address > 0 then
        localAddress = address
        print("Setting local address...")
        break
    else
        print("Invalid address, please retry")
    end
end

print("Do you prefer manual dialing? (enter 'yes' if so)")
local preferManual = read(nil, nil, nil, settings.get("preferManual", false) and "yes" or "no")

print("Modifying configuration file...")
settings.set("solarSystem", solarSystem)
settings.set("galaxies", galaxies)
if localAddress then
    settings.set("psg.localAddress", localAddress)
else
    settings.unset("psg.localAddress")
end
settings.set("preferManual", preferManual == "yes" or preferManual == "y")
settings.save()
print("Configuration OK")

print("Unpacking files...")
saveExtra("dialing.dfpwm")
saveExtra("offworld.dfpwm")
saveProgram("startup.lua")

print("Files unpacked!")
print("Restarting...")

shell.execute 'reboot'
