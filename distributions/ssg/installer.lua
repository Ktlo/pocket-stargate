print("Installing SSG...")

print("Checking peripherals...")
if not peripheral.find("modem", function(_, modem) return not modem.isWireless() end) then
    print("Wired modem not found!")
    typeY()
end
print("Peripherals OK")

print("Unpacking files...")
saveProgram()
print("Files unpacked!")

print("Your copy of Stargate Security Terminal is successfully installed!")
print("Execute \"ssg\" command in order to run Stargate Security Terminal.")
