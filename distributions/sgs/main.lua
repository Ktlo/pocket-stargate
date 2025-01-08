local CHANNEL_COMMAND = 46
local CHANNEL_EVENT = 47
local SECURITY_COMMAND = 48
local SECURITY_EVENT = 49
local DISCOVER_PERIOD = 1

-------------------------------

local concurrent = require 'ktlo.concurrent'
local job = require 'ktlo.job'
local rpc = require 'ktlo.rpc'
local spkey = require 'psg.spkey'
local keyring = require 'psg.keyring'
local filter = require 'psg.filter'
local audit = require 'psg.audit'
local random = require 'ccryptolib.random'
local container = require 'ktlo.container'

local version = VERSION or 'dev'

local speakers = { peripheral.find("speaker") }
local modems = { peripheral.find("modem", function(_, modem) return modem.isWireless end) }
if #modems == 0 then
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

settings.define("preferManual", {
    description = "Prefer manual dialing to direct",
    default = false,
    type = "boolean",
})

settings.define("autoIris", {
    description = "Enable automatic iris activation on incoming wormhole",
    default = true,
    type = "boolean",
})

settings.define("enableAudit", {
    description = "Write audit events into local journal",
    default = false,
    type = "boolean",
})

local galaxies = settings.get("galaxies", {"sgjourney:milky_way"})

local solarSystem = settings.get("solarSystem", "sgjourney:terra")

local preferManual = settings.get("preferManual", false)
local autoIrisProperty = concurrent.property(settings.get("autoIris", true))
local enableAuditProperty = concurrent.property(settings.get("enableAudit", false))

local id = os.getComputerID()

local handlers = {}

local function playChunk(speaker, chunk)
    while not speaker.playAudio(chunk, 100) do
        os.pullEvent('speaker_audio_empty')
    end
end

local function playSound(sound)
    return job.async(function()
        if #speakers > 0 and fs.exists(sound) then
            local dfpwm = require 'cc.audio.dfpwm'
            local decoder = dfpwm.make_decoder()
            while true do
                for chunk in io.lines(sound, 16 * 1024) do
                    local buffer = decoder(chunk)

                    job.async(function()
                        for _, speaker in ipairs(speakers) do
                            job.async(function() playChunk(speaker, buffer) end)
                        end
                    end):await()
                end
            end
        end
    end)
end

local function callOrDefault(method, default)
    if method then
        return method()
    else
        return default
    end
end

job.run(function()

local mStargateGeneration = stargate.getStargateGeneration()
local mStargateVariant = stargate.getStargateVariant()
local mStargateType = stargate.getStargateType()
local mLocalAddress = callOrDefault(stargate.getLocalAddress, {})

local emptyJob = job.async(function()end)

local irisProperty = concurrent.property(callOrDefault(stargate.getIris, nil))
local irisDurabilityProperty = concurrent.property(callOrDefault(stargate.getIrisDurability, 0))
local irisMaxDurabilityProperty = concurrent.property(callOrDefault(stargate.getIrisMaxDurability, 0))
local isStargateConnectedProperty = concurrent.property(stargate.isStargateConnected())
local isStargateDialingOutProperty = concurrent.property(stargate.isStargateDialingOut())
local isIncomingConnectionProperty = job.livedata.combine(function(isStargateConnected, isStargateDialingOut)
    return isStargateConnected and not isStargateDialingOut
end, isStargateConnectedProperty, isStargateDialingOutProperty)

local playAlarmTask = emptyJob
job.livedata.subscribe(isIncomingConnectionProperty, function(isIncomingConnection)
    playAlarmTask:cancel()
    if isIncomingConnection then
        if autoIrisProperty.value and irisProperty.value then
            stargate.closeIris()
        end
        playAlarmTask = playSound("offworld.dfpwm")
    else
        if autoIrisProperty.value and irisProperty.value then
            stargate.openIris()
        end
    end
end)

local discoveryEventBroadcastLatch = concurrent.property(false)
local addressBufferProperty = concurrent.property({})
local isDialingProperty = job.livedata.combine(function(addressBuffer)
    return #addressBuffer > 0
end, addressBufferProperty)
local engagedChevronsProperty = concurrent.property(stargate.getChevronsEngaged())
local dialedAddressProperty = concurrent.property(callOrDefault(stargate.getDialedAddress, {}))
local energyTargetProperty = concurrent.property(stargate.getEnergyTarget())
local connectedAddressProperty = concurrent.property(callOrDefault(stargate.getConnectedAddress, {}))
local isNetworkRestrictedProperty = concurrent.property(callOrDefault(stargate.isNetworkRestricted, false))
local networkProperty = concurrent.property(callOrDefault(stargate.getNetwork, false))
local filterTypeProperty = concurrent.property(callOrDefault(stargate.getFilterType, 0))
local function pollNewValues()
    local feedbackCode, feedbackName = stargate.getRecentFeedback();
    return {
        feedbackCode = feedbackCode;
        feedbackName = feedbackName;
        energy = stargate.getEnergy();
        energyCapacity = stargate.getEnergyCapacity();
        stargateEnergy = stargate.getStargateEnergy();
        openTime = stargate.getOpenTime();
        isWormholeOpen = stargate.isWormholeOpen();
    }
end
local pollValuesProperty = concurrent.property(pollNewValues())
local function buildDiscoverEvent()
    local result = {}
    local values = pollValuesProperty.value
    result.id = id
    result.version = version
    result.galaxies = galaxies
    result.solarSystem = solarSystem
    result.tier = tier
    local dialedAddress = dialedAddressProperty.value
    local addressBuffer = addressBufferProperty.value
    local skip = 0
    if dialedAddress[#dialedAddress] == addressBuffer[1] then
        skip = 1
    end
    local sendAddressBuffer = {}
    for i = 1+skip, #addressBuffer do
        if addressBuffer[i] == 0 then break end
        table.insert(sendAddressBuffer, addressBuffer[i])
    end
    result.addressBuffer = sendAddressBuffer
    result.dialedAddress = dialedAddress;
    local isConnected = isStargateConnectedProperty.value
    result.pooPressed = isConnected or addressBuffer[#addressBuffer] == 0
    result.basic = {
        energy = values.energy;
        energyCapacity = values.energyCapacity;
        energyTarget = energyTargetProperty.value;
        generation = mStargateGeneration;
        variant = mStargateVariant;
        type = mStargateType;
        stargateEnergy = values.stargateEnergy;
        chevronsEngaged = engagedChevronsProperty.value;
        openTime = values.openTime;
        isConnected = isConnected;
        isDialingOut = isStargateDialingOutProperty.value;
        isWormholeOpen = values.isWormholeOpen;
        recentFeedbackCode = values.feedbackCode;
    }
    if tier >= 2 then
        result.crystal = {
            recentFeedbackName = values.feedbackName;
        }
    end
    if tier >= 3 then
        result.advanced = {
            connectedAddress = connectedAddressProperty.value;
            localAddress = mLocalAddress;
        }
    end
    return result
end
local discoveryMessageProperty = job.livedata.combine(
    buildDiscoverEvent,
    pollValuesProperty,
    engagedChevronsProperty,
    isStargateConnectedProperty,
    dialedAddressProperty,
    energyTargetProperty,
    isStargateDialingOutProperty,
    connectedAddressProperty,
    addressBufferProperty
)
job.livedata.subscribe(discoveryMessageProperty, function() discoveryEventBroadcastLatch:set(true) end)
local function insertAddressSymbol(property, index, symbol)
    local prevAddress = property.value
    if symbol ~= 0 and prevAddress[index] ~= symbol then
        local address = { table.unpack(prevAddress) }
        address[index] = symbol
        property:set(address)
    end
end
local function insertDialedSymbol(index, symbol)
    insertAddressSymbol(dialedAddressProperty, index, symbol)
    insertAddressSymbol(connectedAddressProperty, index, symbol)
end
job.async(function()
    local timer = concurrent.timer(DISCOVER_PERIOD)
    while true do
        pollValuesProperty:set(pollNewValues())
        timer:sleep()
        timer:skip_missed()
    end
end)
job.async(function()
    while true do
        os.pullEvent('stargate_incoming_connection')
        isStargateConnectedProperty:set(true)
    end
end)

job.async(function()
    while true do
        local _, _, engagedCount, chevron, isIncoming, symbol = os.pullEvent('stargate_chevron_engaged')
        engagedChevronsProperty:set(engagedCount)
        if chevron == 0 then
            isStargateConnectedProperty:set(true)
            isStargateDialingOutProperty:set(not isIncoming)
        end
        if symbol then
            if isIncoming then
                insertAddressSymbol(connectedAddressProperty, engagedCount, symbol)
            else
                insertDialedSymbol(engagedCount, symbol)
            end
        end
    end
end)
job.async(function()
    while true do
        local _, _, address = os.pullEvent('stargate_incoming_wormhole')
        isStargateConnectedProperty:set(true)
        if address then
            connectedAddressProperty:set(address)
        end
    end
end)
job.async(function()
    while true do
        os.pullEvent('stargate_outgoing_wormhole')
        isStargateConnectedProperty:set(true)
        isStargateDialingOutProperty:set(true)
    end
end)
job.async(function()
    while true do
        os.pullEvent('stargate_reset')
        engagedChevronsProperty:set(0)
        isStargateConnectedProperty:set(false)
        isStargateDialingOutProperty:set(false)
        dialedAddressProperty:set({})
        connectedAddressProperty:set({})
        addressBufferProperty:set({})
    end
end)

function handlers.tell(message)
    stargate.sendStargateMessage(message)
    return true
end

local otherside = {}

function otherside.info(nonce)
    return spkey.auth_request(nonce, { isIrisClosed = stargate.getIrisProgress and stargate.getIrisProgress() ~= 0 })
end

local function broadcast(modemFilter, channel, message)
    for _, modem in ipairs(modems) do
        if modemFilter(modem) then
            rpc.broadcast_network(modem, channel, message)
        end
    end
end

local function returnTrue()
    return true
end

local function broadcast_public(message)
    broadcast(returnTrue, CHANNEL_EVENT, message)
end

local function isWiredModem(modem)
    return not modem.isWireless()
end

local function broadcast_security(message)
    broadcast(isWiredModem, SECURITY_EVENT, message)
end

local function saveAuditEvent(event, record)
    local timestamp = audit.save(event, record)
    record.event = event
    record.timestamp = timestamp
    broadcast_security {
        type = 'audit';
        record = record;
    }
end

audit.define('auth', { 'key', 'error' })

function otherside.auth(request)
    local result, reason, key = spkey.auth_continue(request)
    if enableAuditProperty.value then
        saveAuditEvent('auth', { key=key, error=(reason or "") })
    end
    if result and irisProperty.value then
        stargate.openIris()
    end
    return result, reason
end

local function encodeSymbolManual(symbol, slow)
    local current = stargate.getCurrentSymbol()
    local diff
    if symbol > current then
        local currentAlt = current + 39
        local diff1 = symbol - current
        local diff2 = symbol - currentAlt
        if math.abs(diff1) < math.abs(diff2) then
            diff = diff1
        else
            diff = diff2
        end
    else
        local symbolAlt = symbol + 39
        local diff1 = symbol - current
        local diff2 = symbolAlt - current
        if math.abs(diff1) < math.abs(diff2) then
            diff = diff1
        else
            diff = diff2
        end
    end
    if diff > 0 then
        stargate.rotateAntiClockwise(symbol)
    else
        stargate.rotateClockwise(symbol)
    end
    repeat os.sleep(0.2)
    until stargate.isCurrentSymbol(symbol)
    if slow then
        os.sleep(1)
    end
        stargate.openChevron()
        if slow then
            os.sleep(0.5)
            if symbol ~= 0 then
                stargate.encodeChevron()
            end
            os.sleep(0.5)
        end
        stargate.closeChevron()
    if slow then
        os.sleep(1)
    end
end

local canEngageImmediatly = {
    ["sgjourney:milky_way_stargate"] = true;
    ["sgjourney:classic_stargate"] = true;
    ["sgjourney:tollan_stargate"] = true;
}

local isMW = mStargateType == "sgjourney:milky_way_stargate"
canEngageImmediatly = canEngageImmediatly[mStargateType]

local function encodeSymbol(symbol, slow)
    if preferManual and isMW and slow then
        encodeSymbolManual(symbol, slow)
    elseif tier >= 2 then
        local engagedTarget = engagedChevronsProperty.value + 1
        coroutine.wrap(function()
            stargate.engageSymbol(symbol)
        end)()
        if slow then
            os.sleep(0.5)
        end
        if slow or not canEngageImmediatly then
            engagedChevronsProperty:wait_until(function(value) return value == engagedTarget end)
        end
    elseif isMW then
        encodeSymbolManual(symbol, slow)
    end
    insertDialedSymbol(engagedChevronsProperty.value, symbol)
end

local slowDialingEnabled = true

local function queuePop(queue)
    return { table.unpack(queue, 2) }
end

local function queuePush(queue, value)
    local new = { table.unpack(queue) }
    table.insert(new, value)
    return new
end

job.livedata.determines(isDialingProperty, function()
    playSound("dialing.dfpwm")
    while true do
        local addressBuffer = addressBufferProperty.value
        local symbol = addressBuffer[1]
        if not symbol then break end
        encodeSymbol(symbol, slowDialingEnabled)
        addressBufferProperty:set(queuePop(addressBufferProperty.value))
    end
end)

function handlers.engage(symbol)
    if isStargateConnectedProperty.value then
        return false
    end
    local dialedAddress = dialedAddressProperty.value
    local addressBuffer = addressBufferProperty.value
    local bufferLength = #addressBuffer
    if bufferLength + #dialedAddress >= 9 then
        return false
    end
    if addressBuffer[bufferLength] == 0 then
        return false
    end
    for _, it in ipairs(dialedAddress) do
        if it == symbol then
            return false
        end
    end
    for _, it in ipairs(addressBuffer) do
        if it == symbol then
            return false
        end
    end
    slowDialingEnabled = true
    addressBufferProperty:set(queuePush(addressBuffer, symbol))
    return true
end

function handlers.dial(address, slow)
    if not address then return false end
    if isDialingProperty.value then
        return
    end
    slowDialingEnabled = slow
    local addressBuffer = address
    addressBuffer[#addressBuffer+1] = 0
    addressBufferProperty:set(addressBuffer)
    local setChevronConfiguration = stargate.setChevronConfiguration
    if setChevronConfiguration then
        if #addressBuffer == 8 then
            setChevronConfiguration({1,2,3,4,6,7,8,5})
        elseif #addressBuffer == 9 then
            setChevronConfiguration({1,2,3,4,5,6,7,8})
        end
    end
end

function handlers.disconnect()
    stargate.disconnectStargate()
end

function handlers.register(pkey, name)
    if not keyring.exists(pkey) then
        broadcast_security { type = 'register', key = pkey, name = name }
    end
    return spkey.public_key()
end

local security = {}

local function filterTypeToMode(type)
    if type == 1 then
        return 'allow'
    elseif type == -1 then
        return 'deny'
    else
        return 'none'
    end
end

local function filterModeToType(mode)
    if mode == 'allow' then
        return 1
    elseif mode == 'deny' then
        return -1
    else
        return 0
    end
end

function security.getState()
    local result = {
        version = version;
        keyring = keyring.get_all();
        tier = tier;
        settings = {
            key = spkey.public_key();
            galaxies = galaxies;
            solarSystem = solarSystem;
            energyTarget = energyTargetProperty.value;
            autoIris = autoIrisProperty.value;
            enableAudit = enableAuditProperty.value;
            iris = irisProperty.value;
            irisDurability = irisDurabilityProperty.value;
            irisMaxDurability = irisMaxDurabilityProperty.value;
        };
    }
    if tier >= 3 then
        result.advanced = {
            network = {
                id = networkProperty.value;
                isRestricted = isNetworkRestrictedProperty.value;
            };
            filter = {
                allowlist = filter.allowlist_getall();
                denylist = filter.denylist_getall();
                mode = filterTypeToMode(filterTypeProperty.value);
            };
        }
    end
    return result
end

local function broadcastSetting(setting, value)
    broadcast_security { type = 'setting', setting = setting, value = value }
end

function security.setEnergyTarget(target)
    stargate.setEnergyTarget(target)
    energyTargetProperty:set(stargate.getEnergyTarget())
end
job.livedata.subscribe(energyTargetProperty, function(value)
    broadcastSetting("energy_target", value)
end)

function security.setNetwork(network)
    stargate.setNetwork(network)
    networkProperty:set(stargate.getNetwork())
end
job.livedata.subscribe(networkProperty, function(value)
    broadcastSetting("network", value)
end)

function security.restrictNetwork(value)
    stargate.restrictNetwork(value)
    isNetworkRestrictedProperty:set(value)
end
job.livedata.subscribe(isNetworkRestrictedProperty, function(value)
    broadcastSetting("is_network_restricted", value)
end)

function security.setFilterMode(mode)
    stargate.setFilterType(filterModeToType(mode))
    filterTypeProperty:set(stargate.getFilterType())
end
job.livedata.subscribe(filterTypeProperty, function(value)
    local mode = filterTypeToMode(value)
    broadcastSetting('filter_mode', mode)
end)

function security.deny(pkey)
    keyring.forget(pkey)
    broadcast_security { type = 'deny', key = pkey }
end

function security.allow(pkey, name)
    local r = keyring.trust(pkey, name)
    if r then
        broadcast_security { type = 'allow', key = pkey, name = name }
    end
end

local function broadcastFilterUpdate(list, action, address)
    broadcast_security {
        type = 'filter';
        list = list;
        action = action;
        address = address;
    }
end

function security.allowlistAdd(address)
    if filter.allowlist_add(address) then
        broadcastFilterUpdate('allow', 'add', address)
    end
end

function security.denylistAdd(address)
    if filter.denylist_add(address) then
        broadcastFilterUpdate('deny', 'add', address)
    end
end

function security.allowlistDel(address)
    if filter.allowlist_del(address) then
        broadcastFilterUpdate('allow', 'del', address)
    end
end

function security.denylistDel(address)
    if filter.denylist_del(address) then
        broadcastFilterUpdate('deny', 'del', address)
    end
end

function security.allowlistSync()
    filter.allowlist_synch()
end

function security.denylistSync()
    filter.denylist_synch()
end

function security.setAutoIris(value)
    autoIrisProperty:set(value)
end
job.livedata.subscribe(autoIrisProperty, function(value)
    broadcastSetting('auto_iris', value)
end)

function security.setEnableAudit(value)
    enableAuditProperty:set(value)
end
job.livedata.subscribe(enableAuditProperty, function(value)
    broadcastSetting('enable_audit', value)
end)

function security.openIris()
    if irisProperty.value then
        stargate.openIris()
    end
end

function security.closeIris()
    if irisProperty.value then
        stargate.closeIris()
    end
end

function security.tail(skip, size)
    return audit.tail(skip, size)
end

function security.head(skip, size)
    return audit.head(skip, size)
end

function security.erase(size)
    return audit.erase(size)
end

audit.define('wormhole', { 'direction', 'address' })
audit.define('travel', { 'direction', 'type', 'name', 'uuid', 'destroyed' })

job.livedata.determines(enableAuditProperty, function()
    job.async(function()
        while true do
            local _, _, address = os.pullEvent('stargate_incoming_wormhole')
            local record = {
                direction = 'incoming';
                address = address and stargate.addressToString(address) or ""
            }
            saveAuditEvent('wormhole', record)
        end
    end)
    job.async(function()
        while true do
            local _, _, address = os.pullEvent('stargate_outgoing_wormhole')
            local record = {
                direction = 'outgoing';
                address = address and stargate.addressToString(address) or ""
            }
            saveAuditEvent('wormhole', record)
        end
    end)
    job.async(function()
        while true do
            local _, _, type, name, uuid, destroyed = os.pullEvent('stargate_deconstructing_entity')
            local record = {
                direction = 'outgoing';
                type = type;
                name = name;
                uuid = uuid;
                destroyed = tostring(destroyed);
            }
            saveAuditEvent('travel', record)
        end
    end)
    job.async(function()
        while true do
            local _, _, type, name, uuid = os.pullEvent('stargate_reconstructing_entity')
            local record = {
                direction = 'incoming';
                type = type;
                name = name;
                uuid = uuid;
                destroyed = 'false';
            }
            saveAuditEvent('travel', record)
        end
    end)
    job.async(function()
        local _, _, type, name, uuid = os.pullEvent('iris_thud')
        local record = {
            direction = 'incoming';
            type = type;
            name = name;
            uuid = uuid;
            destroyed = 'true';
        }
        saveAuditEvent('travel', record)
    end)
end)

job.livedata.subscribe(discoveryEventBroadcastLatch, function(value)
    if value then
        sleep()
        broadcast_public {
            type = 'discover';
            data = discoveryMessageProperty.value;
        }
        discoveryEventBroadcastLatch:set(false)
    end
end)

job.async(function()
    while true do
        local _, _, message = os.pullEvent('stargate_message_received')
        job.async(function ()
            broadcast_public {
                type = 'message';
                data = message;
            }
        end)
    end
end)

do
    local commands = rpc.simple_commands(handlers)
    for _, modem in ipairs(modems) do
        rpc.server_network(commands, modem, CHANNEL_COMMAND) -- backward compatibility
        rpc.server_network(commands, modem, CHANNEL_COMMAND, id)
    end
end

do
    local commands = rpc.simple_commands(security)
    for _, modem in ipairs(modems) do
        if isWiredModem(modem) then
            rpc.server_network(commands, modem, SECURITY_COMMAND)
        end
    end
end

local function stargateMessageExchanger(handler)
    local _, _, message = os.pullEvent('stargate_message_received')
    local request = textutils.unserialize(message)
    if request then
        local response = handler(request)
        if response then
            job.async(function()
                stargate.sendStargateMessage(tostring(container.datum(response, true)))
            end)
        end
    end
end

rpc.server(rpc.simple_commands(otherside), stargateMessageExchanger)

job.livedata.subscribe(enableAuditProperty, function(value)
    settings.set("enableAudit", value)
    settings.save()
end)

job.livedata.subscribe(autoIrisProperty, function(value)
    settings.set("autoIris", value)
    settings.save()
end)

if stargate.getIris then
    job.async(function()
        while true do
            os.pullEvent('iris_thud')
            irisDurabilityProperty:set(irisDurabilityProperty.value - 1)
        end
    end)

    job.async(function()
        while true do
            sleep(1)
            irisProperty:set(stargate.getIris())
            irisDurabilityProperty:set(stargate.getIrisDurability())
            irisMaxDurabilityProperty:set(stargate.getIrisMaxDurability())
        end
    end)

    job.livedata.subscribe(irisDurabilityProperty, function(durabiliy)
        if durabiliy == 0 then
            irisMaxDurabilityProperty:set(0)
            irisProperty:set(nil)
        end
    end)

    local irisStateProperty = job.livedata.combine(function(iris, durability, maxDurability)
        return {
            iris = iris;
            durability = durability;
            maxDurability = maxDurability;
        }
    end, irisProperty, irisDurabilityProperty, irisMaxDurabilityProperty)

    job.livedata.subscribe(irisStateProperty, function(irisState)
        broadcastSetting('iris', irisState)
    end)
end

if not random.isInit() then
    random.initWithTiming()
end

settings.save()

print("Stargate Server (SGS)", version)

end)
