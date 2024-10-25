local GITHUBRAW = "https://raw.githubusercontent.com/Ktlo/pocket-stargate"
local RELEASES = "https://github.com/Ktlo/pocket-stargate/releases/download"

--------------------------------

local function typeY()
    write("Do you want to continue? (Type Y for continue): ")
    local read = read(nil, nil, nil, "N")
    if read ~= 'Y' then
        print("Exiting...")
        return true
    end
end

print("Installing SGS...")
print("Checking peripherals...")
if not (peripheral.find "advanced_crystal_interface" or peripheral.find "crystal_interface" or peripheral.find "basic_interface") then
    print("Stargate interface not found!")
    if typeY() then return end
end
if not peripheral.find("modem") then
    print("Modem not found!")
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
local function wgetraw(distribution, filename)
    local fullUrl = GITHUBRAW.."/"..BRANCH.."/distributions/"..distribution.."/"..filename
    shell.execute("wget", fullUrl, filename)
end

shell.execute("wget", RELEASES.."/"..BRANCH.."/sgs.lua", "startup.lua")
wgetraw("sgs", "dialing.dfpwm")
wgetraw("sgs", "offworld.dfpwm")

print("Files downloaded!")
print("Restarting...")

shell.execute 'reboot'
