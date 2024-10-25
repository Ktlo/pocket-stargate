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

print("Installing PSG...")
print("Checking peripherals...")
if not peripheral.find("modem") then
    print("Modem not found!")
    if typeY() then return end
end
print("Peripherals OK")

print("Downloading files...")
local function wgetraw(distribution, filename)
    local fullUrl = GITHUBRAW.."/"..BRANCH.."/distributions/"..distribution.."/"..filename
    shell.execute("wget", fullUrl, filename)
end

if not fs.exists("addresses.conf") then
    wgetraw("psg", "addresses.conf")
end
shell.execute("wget", RELEASES.."/"..BRANCH.."/psg.lua", "psg.lua")

print("Files downloaded!")

print("Your copy of Pocket Stargate is successfully installed!")
print("You can modify \"addresses.conf\" now.")
print("Execute \"psg\" command in order to run Pocket Stargate.")
