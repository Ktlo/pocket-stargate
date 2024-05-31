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
if not peripheral.find("modem", function(_, modem) return modem.isWireless() end) then
    print("Wireless modem not found!")
    if typeY() then return end
end
if not pocket then
    print("This is not a pocket device!")
    if typeY() then return end
end
print("Peripherals OK")

print("Downloading files...")
local function wget(side, filename)
    local fullUrl = PREFIX.."/"..BRANCH.."/"..side.."/"..filename
    shell.execute("wget", fullUrl, filename)
end

shell.execute("wget", "run", "https://basalt.madefor.cc/install.lua", "packed", "basalt.lua", "v1.6.6")
wget("common", "concurrent.lua")
wget("client", "addresses.conf")
wget("client", "addresses.lua")
wget("client", "stargate.lua")
wget("client", "psg.lua")
wget("client", "psg.xml")

print("Files downloaded!")

print("Your copy of Pocket Stargate is successfully installed!")
print("You can modify \"addresses.conf\" now.")
print("Execute \"psg\" command in order to run Pocket Stargate.")
