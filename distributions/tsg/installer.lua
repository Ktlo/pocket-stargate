local RELEASES = "https://github.com/Ktlo/pocket-stargate/releases/download"
local GITHUBRAW = "https://raw.githubusercontent.com/Ktlo/pocket-stargate"

--------------------------------

local completion = require 'cc.completion'

local function typeY()
    write("Do you want to continue? (Type Y for continue): ")
    local read = read(nil, nil, nil, "N")
    if read ~= 'Y' then
        print("Exiting...")
        return true
    end
end

print("Installing Stargate Trains...")
print("Checking peripherals...")
if not peripheral.find("modem", function(_, modem) return not peripheral.hasType(modem, "peripheral_hub") end) then
    print("Ender modem not found!")
    if typeY() then return end
end
if not peripheral.find("modem", function(_, modem) return peripheral.hasType(modem, "peripheral_hub") end) then
    print("Wired modem not found!")
    if typeY() then return end
end

local stations = { peripheral.find("Create_Station") }
local incoming, outgoing
if #stations < 2 then
    print("Not enoug train station attached to the CC network!")
    if typeY() then return end
else
    for i=1, #stations do
        stations[i] = peripheral.getName(stations[i])
    end

    local complete = function (text)
        return completion.choice(text, stations, false)
    end

    write("Specify incoming train station: ")
    incoming = read(nil, stations, complete, stations[1])
    for i=1, #stations do
        if stations[i] == incoming then
            table.remove(stations, i)
            break
        end
    end

    write("Specify outgoing train station: ")
    outgoing = read(nil, stations, complete, stations[1])
    if incoming == outgoing then
        print("Incoming station cannot be outgoing!")
        if typeY() then return end
    end
end

print("Peripherals OK")

print("Downloading files...")
shell.execute("wget", RELEASES.."/"..BRANCH.."/tsg.lua", "tsg.lua")

local function wgetraw(distribution, filename)
    local fullUrl = GITHUBRAW.."/"..BRANCH.."/distributions/"..distribution.."/"..filename
    shell.execute("wget", fullUrl, filename)
end

if not fs.exists("addresses.conf") then
    wgetraw("psg", "addresses.conf")
end

print("Files downloaded!")

if incoming and outgoing then
    print("Prepearing startup script...")
    local file = assert(io.open("startup.lua", "w"))
    file:write("shell.run \"tsg ")
    file:write(incoming)
    file:write(" ")
    file:write(outgoing)
    file:write("\"\n")
    file:close()
end

print("DONE! Rebooting...")
shell.execute 'reboot'
