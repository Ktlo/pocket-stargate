local CHANNEL_COMMAND = 46
local CHANNEL_EVENT = 47
local DISCOVER_PERIOD = 1

-------------------------------

local concurrent = require 'concurrent'

local modem = peripheral.find("modem", function(_, modem) return modem.isWireless() end)

if not modem then
    error "No modem found; exiting..."
end

local tier
local stargate

do
    local interfaces = {
        "advanced_crystal_interface",
        "crystal_interface",
        "basic_interface",
    }
    for i, interface in ipairs(interfaces) do
        stargate = peripheral.find(interface)
        if stargate then
            tier = #interfaces - i + 1
            break
        end
    end
end

if not stargate then
    error "No stargate found; exiting..."
end

settings.define("galaxies", {
    description = "Galaxies",
    default = {"sgjourney:milky_way"},
    type = "table",
})

settings.define("solarSystem", {
    description = "Current solar system",
    default = "minecraft:overworld",
    type = "string",
})

settings.save()

local galaxies = settings.get("galaxies", {"sgjourney:milky_way"})

local solarSystem = settings.get("solarSystem", "minecraft:overworld")

modem.open(CHANNEL_COMMAND)

local broadcastEvents = {}
do
    local broadcastEventsList = {
        "stargate_chevron_engaged",
        "stargate_incoming_wormhole",
        "stargate_outgoing_wormhole",
        "stargate_disconnected",
        "stargate_deconstructing_entity",
        "stargate_reconstructing_entity",
        "stargate_reset",
        "stargate_message_received",
    }
    for _, event in ipairs(broadcastEventsList) do
        broadcastEvents[event] = true
    end
end

local taskChannel = concurrent.channel()

local function taskThread()
    while true do
        local task = assert(taskChannel:recv())
        local ok, err = pcall(task)
        if not ok then
            print("ERROR TASK: "..err)
        end
    end
end

local forkChannel = concurrent.channel()

local function fork(f)
    forkChannel:send(f)
end

local function forkThread()
    while true do
        local task = assert(forkChannel:recv())
        local ok, err = pcall(task)
        if not ok then
            print("ERROR FORK: "..err)
        end
    end
end

local id = math.random()

local handlers = {}

local addressBuffer = {}

local function buildDiscoverEvent()
    local result = {}
    local feedbackCode, feedbackName = stargate.getRecentFeedback();
    result.id = id
    result.galaxies = galaxies
    result.solarSystem = solarSystem
    result.tier = tier
    local dialedAddress
    if tier >= 2 then dialedAddress = stargate.getDialedAddress() end
    local skip = 0
    if dialedAddress and dialedAddress[#dialedAddress] == addressBuffer[1] then
        skip = 1
    end
    local sendAddressBuffer = {}
    for i = 1+skip, #addressBuffer do
        if addressBuffer[i] == 0 then break end
        table.insert(sendAddressBuffer, addressBuffer[i])
    end
    result.addressBuffer = sendAddressBuffer
    result.basic = {
        energy = stargate.getEnergy();
        energyTarget = stargate.getEnergyTarget();
        generation = stargate.getStargateGeneration();
        type = stargate.getStargateType();
        stargateEnergy = stargate.getStargateEnergy();
        chevronsEngaged = stargate.getChevronsEngaged();
        openTime = stargate.getOpenTime();
        isConnected = stargate.isStargateConnected();
        isDialingOut = stargate.isStargateDialingOut();
        isWormholeOpen = stargate.isWormholeOpen();
        recentFeedbackCode = feedbackCode;
    }
    if tier >= 2 then
        result.crystal = {
            recentFeedbackName = feedbackName;
            dialedAddress = dialedAddress;
        }
    end
    if tier >= 3 then
        result.advanced = {
            connectedAddress = stargate.getConnectedAddress();
            localAddress = stargate.getLocalAddress();
            network = stargate.getNetwork();
            isNetworkRestricted = stargate.isNetworkRestricted();
        }
    end
    return result
end

function handlers.target(target)
    stargate.setEnergyTarget(target)
    return stargate.getEnergyTarget()
end

function handlers.tell(message)
    stargate.sendStargateMessage(message)
    return true
end

function handlers.restrict(boolean)
    if tier >= 3 then
        stargate.restrictNetwork(boolean)
        return true
    end
    return false
end

function handlers.network(networkId)
    if tier >= 3 then
        stargate.setNetwork(networkId)
        return true
    end
    return false
end

local engagedChevrons = -1

local function dial(fast)
    local slow = not fast
    if tier >= 2 then
        while #addressBuffer > 0 do
            local symbol = addressBuffer[1]
            engagedChevrons = stargate.getChevronsEngaged()
            if stargate.engageSymbol(symbol) < 0 then
                addressBuffer = {}
                break
            end
            if slow then
                os.sleep(0.5)
            end
            while engagedChevrons == stargate.getChevronsEngaged() do
                os.sleep(0.2)
            end
            if engagedChevrons == -1 then
                addressBuffer = {}
                break
            end
            table.remove(addressBuffer, 1)
        end
    elseif stargate.getStargateType() == "sgjourney:milky_way_stargate" then
        while #addressBuffer > 0 do
            local symbol = addressBuffer[1]
            local current = stargate.getCurrentSymbol()
            local diff = current - symbol
            if diff < 0 then
                stargate.rotateAntiClockwise(symbol)
            else
                stargate.rotateClockwise(symbol)
            end
            repeat os.sleep(0.2)
            until stargate.isCurrentSymbol(symbol)
            if slow then
                os.sleep(1)
            end
            if #addressBuffer == 0 then break end
            stargate.openChevron()
            if slow then
                os.sleep(1)
            end
            stargate.closeChevron()
            if #addressBuffer == 0 then
                stargate.disconnectStargate()
                break
            end
            if slow then
                os.sleep(1)
            end
            table.remove(addressBuffer, 1)
        end
    end
end

function handlers.dial(data)
    local n = #addressBuffer
    for i = 1, n do
        if addressBuffer[i] == 0 then
            return true
        end
    end
    for _, symbol in ipairs(data.address) do
        for i = 1, n do
            if symbol == addressBuffer[i] then
                goto skip
            end
        end
        table.insert(addressBuffer, symbol)
        ::skip::
    end
    local fast = data.fast
    taskChannel:send(function() dial(fast) end)
    return true
end

function handlers.disconnect()
    addressBuffer = {}
    stargate.disconnectStargate()
    return true
end

local function processRequest(command, data)
    local action = handlers[command]
    if action then
        return action(data)
    else
        return nil, "unknown command: "..command
    end
end

local function onRequest(replyChannel, message)
    local data, error = processRequest(message.command, message.data)
    if data ~= nil then
        local response = {
            id = message.id;
            success = true;
            data = data;
        }
        modem.transmit(replyChannel, CHANNEL_COMMAND, response)
        print("response: "..textutils.serialize(response, {compact = true}))
    else
        local response = {
            id = message.id;
            success = false;
            error = error;
        }
        modem.transmit(replyChannel, CHANNEL_COMMAND, response)
        print("error: "..textutils.serialize(response, {compact = true}))
    end
end

local function mainThread()
    local discoverTimer = os.startTimer(DISCOVER_PERIOD)
    while true do
        local event = { os.pullEvent() }
        local eventType = event[1]
        if broadcastEvents[eventType] then
            local response = {
                command = 'event';
                data = event;
            }
            fork(function()
                modem.transmit(CHANNEL_EVENT, CHANNEL_COMMAND, response)
                print("event: "..textutils.serialize(response, {compact = true}))
            end)
        end
        if eventType == 'stargate_reset' then
            engagedChevrons = -1
        end
        if eventType == 'timer' and event[2] == discoverTimer then
            fork(function()
                local response = {
                    command = 'discover';
                    data = buildDiscoverEvent();
                }
                modem.transmit(CHANNEL_EVENT, CHANNEL_COMMAND, response)
                --print("discover: "..textutils.serialize(response, {compact = true}))
                discoverTimer = os.startTimer(DISCOVER_PERIOD)
            end)
        end
        if eventType == 'modem_message' then
            local _, channel, replyChannel, message, _ = table.unpack(event, 2)
            print("request: "..textutils.serialize(message, {compact = true}))
            if channel == CHANNEL_COMMAND then
                fork(function() onRequest(replyChannel, message) end)
            end
        end
    end
end

local function handleErrors(f)
    return function(...)
        local result = { pcall(f, ...) }
        if not result[1] then
            print("ERROR: "..result[2])
            error(result[1])
        end
        return table.unpack(result, 2)
    end
end

parallel.waitForAll(handleErrors(mainThread), taskThread, forkThread)
