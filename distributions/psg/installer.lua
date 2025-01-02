print("Installing PSG...")
print("Checking peripherals...")
if not peripheral.find("modem") then
    print("Modem not found!")
    typeY()
end
print("Peripherals OK")

print("Specify an URL that points to addresses file: ")

local DEFAULT_LOCATION = "file:addresses.conf"
local addressesLocation = read(nil, nil, nil, settings.get("psg.addressesLocation", DEFAULT_LOCATION))

settings.set("psg.addressesLocation", addressesLocation)
settings.save()

print("Unpacking files...")
if not fs.exists("addresses.conf") and DEFAULT_LOCATION == addressesLocation then
    saveExtra("addresses.conf")
end
saveProgram()

print("Files unpacked!")

print("Your copy of Pocket Stargate", VERSION, "is successfully installed!")
print("You can modify \"addresses.conf\" now.")
print("Execute \"psg\" command in order to run Pocket Stargate.")
