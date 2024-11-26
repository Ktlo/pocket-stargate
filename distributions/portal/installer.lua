print("Installing ME portal...")

print("Checking peripherals...")
if not peripheral.find("modem", function(_, modem) return not peripheral.hasType(modem, "peripheral_hub") end) then
    print("Ender modem not found!")
    typeY()
end
if not peripheral.find("monitor") then
    print("Monitor not found!")
    typeY()
end
if not peripheral.find("meBridge") then
    print("meBridge not found!")
    typeY()
end
if not peripheral.find("ae2:spatial_io_port") then
    print("Spatial IO port not found!")
    typeY()
end
print("Peripherals OK")

write("Specify portal name: ")
local name = read()

print("Unpacking files...")
saveProgram()
print("Files unpacked!")

if name then
    print("Prepearing startup script...")
    local file = assert(io.open("startup.lua", "w"))
    file:write("shell.run \"portal ")
    file:write(name)
    file:write(" 3\"\n")
    file:close()
    print("DONE! Rebooting...")
    shell.execute 'reboot'
end
