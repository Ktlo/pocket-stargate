print("Installing SGR...")
print("Checking peripherals...")
if not peripheral.find("modem", function(_, modem) return not modem.isWireless() end) then
    print("Wired modem not found!")
    typeY()
end
if not peripheral.find("modem", function(_, modem) return modem.isWireless() end) then
    print("Wireless modem not found!")
    typeY()
end
print("Peripherals OK")

print("Unpacking files...")
saveProgram("startup.lua")

print("Files unpacked!")
os.reboot()
