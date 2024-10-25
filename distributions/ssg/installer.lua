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

print("Installing SSG...")
print("Checking peripherals...")
if not peripheral.find("modem", function(_, modem) return not modem.isWireless() end) then
    print("Wired modem not found!")
    if typeY() then return end
end
print("Peripherals OK")

print("Downloading files...")
shell.execute("wget", RELEASES.."/"..BRANCH.."/ssg.lua", "ssg.lua")

print("Files downloaded!")

print("Your copy of Stargate Security Terminal is successfully installed!")
print("Execute \"ssg\" command in order to run Stargate Security Terminal.")
