print("Installing ASN...")

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

print("Your copy of address book editor", VERSION, "is successfully installed!")
print("Execute \"asn\" command in order to run address book editor.")
