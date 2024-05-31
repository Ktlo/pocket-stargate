local CHANNEL_COMMAND = 46
local CHANNEL_EVENT = 47
local CHANNEL_RESPONSE = 48
local TIMEOUT = 1

--------------------------------------------------------

local concurrent = require 'concurrent'

local modem = peripheral.find("modem", function(_, modem) return modem.isWireless() end)

if not modem then
    error "No modem found; exiting..."
end

local mutex = concurrent.mutex()

local function exchange(command, data)
    local id = math.random()
    local request = {
        id = id;
        command = command;
        data = data;
    }
    modem.open(CHANNEL_RESPONSE)
    modem.transmit(CHANNEL_COMMAND, CHANNEL_RESPONSE, request)
    local timer = os.startTimer(TIMEOUT)
    local event, side, channel, _, message
    repeat
        event, side, channel, _, message = os.pullEvent()
        if event == "timer" and side == timer then
            os.cancelTimer(timer)
            modem.close(CHANNEL_RESPONSE)
            error("timeout", 3)
        end
    until event == 'modem_message' and channel == CHANNEL_RESPONSE and message.id == id
    os.cancelTimer(timer)
    modem.close(CHANNEL_RESPONSE)
    if message.success then
        return message.data
    else
        return nil, message.error
    end
end

exchange = mutex:wrap(exchange)

local stargate = {}

function stargate.dial(address, fast)
    assert(exchange("dial", {address=address, fast=fast}))
end

function stargate.disconnect(message)
    return assert(exchange("disconnect", message))
end

function stargate.tell(message)
    assert(exchange("tell", message))
end

function stargate.restrict(boolean)
    return exchange("restrict", boolean)
end

function stargate.network(networkId)
    return exchange("network", networkId)
end

function stargate.target(energy)
    return exchange("target", energy)
end

local eventLoopMutex = concurrent.mutex()

function stargate.enterEventLoop()
    eventLoopMutex:lock()
    modem.open(CHANNEL_EVENT)
end

function stargate.pullEvent()
    local event, _, channel, _, message, _
    repeat
        event, _, channel, _, message, _ = os.pullEvent()
    until event == 'modem_message' and channel == CHANNEL_EVENT
    return message.command, message.data
end

function stargate.leaveEventLoop()
    modem.close(CHANNEL_EVENT)
    eventLoopMutex:unlock()
end

function stargate.eventLoop(handler)
    stargate.enterEventLoop()
    while true do
        local result = { pcall(function() return handler(stargate.pullEvent()) end) }
        if not result[1] then
            stargate.leaveEventLoop()
            error(result[2])
        end
        if #result > 1 then
            stargate.leaveEventLoop()
            return table.unpack(result, 2)
        end
    end
end

return stargate
