local PREFIX = "https://raw.githubusercontent.com/Ktlo/pocket-stargate"
local BRANCH = "develop"

--------------------------------

local function typeY()
    write("Do you want to continue? (Type Y for continue): ")
    local read = read(nil, nil, nil, "N")
    if read ~= 'Y' then
        print("Exiting...")
        return true
    end
end

print("Installing PSG server...")
print("Checking peripherals...")
if not (peripheral.find "advanced_crystal_interface" or peripheral.find "crystal_interface" or peripheral.find "basic_interface") then
    print("Stargate interface not found!")
    if typeY() then return end
end
if not peripheral.find("modem", function(_, modem) return modem.isWireless() end) then
    print("Wireless modem not found!")
    if typeY() then return end
end
print("Peripherals OK")

write("Name current solar system: ")
local solarSystem = read(nil, nil, nil, "sgjourney:terra")

local galaxies = {}

print("Please, enter names of galaxies where the stargate is located at (empty input means end of list)")
while true do
    write("Name galaxy #"..tostring(#galaxies + 1)..": ")
    local galaxy = read(nil, nil, nil, #galaxies == 0 and "sgjourney:milky_way" or nil)
    if galaxy == "" then break end
    table.insert(galaxies, galaxy)
end

print("Do you prefer manual dialing? (enter 'yes' if so)")
local preferManual = read(nil, nil, nil, "no")

print("Modifying configuration file...")
settings.set("solarSystem", solarSystem)
settings.set("galaxies", galaxies)
settings.set("preferManual", preferManual == "yes" or preferManual == "y")
settings.save()
print("Configuration OK")

print("Downloading files...")
local function wget(side, filename)
    local fullUrl = PREFIX.."/"..BRANCH.."/"..side.."/"..filename
    shell.execute("wget", fullUrl, filename)
end

wget("common", "concurrent.lua")
wget("server", "startup.lua")
wget("server", "alarm.dfpwm")

print("Files downloaded!")
print("Restarting...")

shell.execute 'reboot'
