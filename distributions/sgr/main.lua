local CHANNEL_COMMAND = 46
local CHANNEL_EVENT = 47

-------------------------------

local wiredModem = peripheral.find("modem", function(_, modem) return not modem.isWireless() end)
assert(wiredModem, "Wired modem not found!")

local wirelessModem = peripheral.find("modem", function(_, modem) return modem.isWireless() end)
assert(wirelessModem, "Wireless modem not found!")

wiredModem.closeAll()
wiredModem.open(CHANNEL_EVENT)
wirelessModem.open(CHANNEL_COMMAND)

local wiredModemName = peripheral.getName(wiredModem)
local wirelessModemName = peripheral.getName(wirelessModem)

while true do
    local event, side, channel, replyChannel, message = os.pullEventRaw('modem_message')
    if event == 'terminate' then
        break
    end
    if side == wiredModemName then
        wirelessModem.transmit(channel, replyChannel, message)
        if channel ~= CHANNEL_EVENT then
            print("wired", channel, replyChannel, message)
            wiredModem.close(channel)
        end
    end
    if side == wirelessModemName then
        print("wireless", channel, replyChannel, message)
        wiredModem.open(replyChannel)
        wiredModem.transmit(channel, replyChannel, message)
    end
end

wiredModem.close(CHANNEL_EVENT)
wirelessModem.close(CHANNEL_COMMAND)
