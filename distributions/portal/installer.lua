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

print("Installing ME portal...")
print("Checking peripherals...")
if not peripheral.find("modem", function(_, modem) return not peripheral.hasType(modem, "peripheral_hub") end) then
    print("Ender modem not found!")
    if typeY() then return end
end
if not peripheral.find("monitor") then
    print("Monitor not found!")
    if typeY() then return end
end
if not peripheral.find("meBridge") then
    print("meBridge not found!")
    if typeY() then return end
end
if not peripheral.find("ae2:spatial_io_port") then
    print("Spatial IO port not found!")
    if typeY() then return end
end
print("Peripherals OK")

print("Downloading files...")
shell.execute("wget", RELEASES.."/"..BRANCH.."/portal.lua", "portal.lua")

print("Files downloaded!")

print("Execute \"portal\" command in order to run ME portal.")
