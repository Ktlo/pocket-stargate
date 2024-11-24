local completion = require 'cc.completion'

print("Installing Stargate Trains...")

print("Checking peripherals...")
if not peripheral.find("modem", function(_, modem) return not peripheral.hasType(modem, "peripheral_hub") end) then
    print("Ender modem not found!")
    typeY()
end
if not peripheral.find("modem", function(_, modem) return peripheral.hasType(modem, "peripheral_hub") end) then
    print("Wired modem not found!")
    typeY()
end

local stations = { peripheral.find("Create_Station") }
local incoming, outgoing
if #stations < 2 then
    print("Not enoug train station attached to the CC network!")
    typeY()
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
        typeY()
    end
end

print("Peripherals OK")

print("Unpacking files...")
if not fs.exists("addresses.conf") then
    saveExtra("addresses.conf")
end
saveProgram()

print("Files unpacked!")

if incoming and outgoing then
    print("Prepearing startup script...")
    local file = assert(io.open("startup.lua", "w"))
    file:write("shell.run \"tsg ")
    file:write(incoming)
    file:write(" ")
    file:write(outgoing)
    file:write("\"\n")
    file:close()
    print("DONE! Rebooting...")
    shell.execute 'reboot'
end
