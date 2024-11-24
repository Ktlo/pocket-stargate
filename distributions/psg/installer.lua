print("Installing PSG...")
print("Checking peripherals...")
if not peripheral.find("modem") then
    print("Modem not found!")
    typeY()
end
print("Peripherals OK")

print("Unpacking files...")
if not fs.exists("addresses.conf") then
    saveExtra("addresses.conf")
end
saveProgram()

print("Files unpacked!")

print("Your copy of Pocket Stargate is successfully installed!")
print("You can modify \"addresses.conf\" now.")
print("Execute \"psg\" command in order to run Pocket Stargate.")
