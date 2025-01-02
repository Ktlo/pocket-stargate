local CHANNEL = 77
local SGS_CHANNEL_COMMAND = 46
local SGS_CHANNEL_EVENT = 47
local TIMEOUT = 1

--------------------------------

local concurrent = require 'ktlo.concurrent'
local rpc = require 'ktlo.rpc'
local job = require 'ktlo.job'
local shared = require 'ktlo.shared'
local addresses = require 'psg.addresses'

--------------------------------

local incoming = assert(..., "Incoming train station is not provided")
local outgoing = assert(select(2, ...), "Outgoing train station is not provided")

--------------------------------

incoming = peripheral.wrap(incoming)
outgoing = peripheral.wrap(outgoing)
local enderModem = assert(peripheral.find("modem", function(device)
    return not peripheral.hasType(device, "peripheral_hub")
end), "no ender modem found")
local wiredModem = assert(peripheral.find("modem", function(device)
    return peripheral.hasType(device, "peripheral_hub")
end), "no wired modem found")

--------------------------------

local statsProperty = concurrent.property(nil)

job.run(function ()

rpc.subscribe_network(wiredModem, SGS_CHANNEL_EVENT, function(event)
    local type = event.type
    local data = event.data
    if type == 'discover' then
        statsProperty:set(data)
    end
end)

local function id(x)
    return x
end
statsProperty:wait_until(id)
print("SGS is found")

local solarSystemProperty = job.livedata.combine(function(stats)
    return stats.solarSystem
end, statsProperty)
local galaxiesProperty = job.livedata.combine(function(stats)
    return stats.galaxies
end, statsProperty)
local solarSystemNameProperty = job.livedata.combine(function(solarSystem)
    return addresses.getname_by_key(solarSystem)
end, solarSystemProperty)
job.livedata.subscribe(solarSystemNameProperty, function(name)
    incoming.setStationName(name)
    outgoing.setStationName(name)
end)

local sgsClient = rpc.client_network(wiredModem, SGS_CHANNEL_COMMAND, TIMEOUT)

--------------------------------

local function broadcast(message)
    rpc.broadcast_network(enderModem, CHANNEL, message)
end

shared.on_event(function(event)
    broadcast {
        type = 'shared';
        payload = event;
    }
end)

rpc.subscribe_network(enderModem, CHANNEL, function(event)
    local type = event.type
    if type == 'shared' then
        shared.push(event.payload)
    elseif type == 'train_passed' then
        os.queueEvent('train_passed', event.name)
    end
end)

job.async(function()
    while true do
        sleep(1)
        shared.expire()
    end
end)

shared.initialize()
print('gathered state')

local gateBucket = shared.bucket('gate')

--------------------------------

local function getAddress(name)
    local interstellar = addresses.interstellar(galaxiesProperty.value, solarSystemProperty.value)
    for _, record in ipairs(interstellar) do
        if record.name == name then
            return record.address
        end
    end
    local extragalactic = addresses.extragalactic(galaxiesProperty.value)
    for _, record in ipairs(extragalactic) do
        if record.name == name then
            return record.address
        end
    end
    local direct = addresses.direct(nil)
    for _, record in ipairs(direct) do
        if record.name == name then
            return record.address
        end
    end
end

local function currentEntryIndex(schedule)
    local current = schedule.current
    if current then
        return current
    end
    local currentName = solarSystemNameProperty.value
    local entries = schedule.entries
    local size = #entries
    for i=1, size do
        local entry = entries[i]
        local instruction = entry.instruction
        if instruction.id == "create:destination" and instruction.data.text == currentName then
            local nextIndex = i % size + 1
            local next = entries[nextIndex]
            local nextInstruction = next.instruction
            local nextInstructionId = nextInstruction.id
            if nextInstructionId == "create:destination" or nextInstructionId == "railways:waypoint_destination" then
                local address = getAddress(nextInstruction.data.text)
                if address then
                    return nextIndex
                end
            end
        end
    end
    return nil
end

local isTrainEnrouteOutgoing = concurrent.property(false)

job.async(function()
    while true do
        isTrainEnrouteOutgoing:set(outgoing.isTrainEnroute())
        sleep(1)
    end
end)

job.livedata.subscribe(isTrainEnrouteOutgoing, function(isTrainEnroute)
    if not isTrainEnroute then
        broadcast {
            type = 'train_passed',
            name = solarSystemNameProperty.value,
        }
    end
end)

while true do
    -- wait for train
    while true do
        if incoming.isTrainPresent() and incoming.hasSchedule() then
            break
        end
        sleep(1)
    end
    job.async(function()
        local schedule = incoming.getSchedule()
        local index = assert(currentEntryIndex(schedule), "next station not found")
        local entry = schedule.entries[index]
        local next = entry.instruction.data.text
        local address = assert(getAddress(next), "no address found")
        local gates = { solarSystemNameProperty.value, next }
        table.sort(gates)
        local firstName, secondName = table.unpack(gates)
        local first = gateBucket:acquire(firstName)
        local firstJob = job.async(function()
            while true do
                sleep(1)
                first:revive()
            end
        end)
        firstJob:finnalize(function()
            first:release()
        end)
        local second = gateBucket:acquire(secondName)
        local secondJob = job.async(function()
            while true do
                sleep(1)
                second:revive()
            end
        end)
        secondJob:finnalize(function()
            second:release()
        end)
        statsProperty:wait_until(function(stats) return not stats.basic.isConnected end)
        sgsClient.dial(address, true)
        statsProperty:wait_until(function(stats) return stats.basic.isWormholeOpen end)
        job.async(function()
            while true do
                local _, name = os.pullEvent('train_passed')
                if name == next then
                    sgsClient.disconnect()
                    break
                end
            end
        end)
        statsProperty:wait_until(function(stats) return not stats.basic.isConnected end)
        job.cancel()
    end):await()
end

end)
