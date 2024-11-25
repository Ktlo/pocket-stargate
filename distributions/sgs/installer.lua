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

print("Do you prefer manual dialing? (enter 'yes' if so)")
local preferManual = read(nil, nil, nil, settings.get("preferManual", false) and "yes" or "no")

print("Modifying configuration file...")
settings.set("solarSystem", solarSystem)
settings.set("galaxies", galaxies)
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
