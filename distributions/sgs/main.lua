local CHANNEL_COMMAND = 46
local CHANNEL_EVENT = 47
local SECURITY_COMMAND = 48
local SECURITY_EVENT = 49
local DISCOVER_PERIOD = 1

-------------------------------

local concurrent = require 'concurrent'
local job = require 'job'
local rpc = require 'rpc'
local spkey = require 'spkey'
local keyring = require 'keyring'
local filter = require 'filter'
local audit = require 'audit'
local random = require 'ccryptolib.random'

local speaker = peripheral.find("speaker")
if speaker then
    speaker = peripheral.getName(speaker)
end
local anyModem = peripheral.find("modem")
local wiredModem = peripheral.find("modem", function(_, modem) return not modem.isWireless() end)
if wiredModem then
    wiredModem = peripheral.getName(wiredModem)
end
local modem = peripheral.find("modem", function(_, modem) return modem.isWireless() end) or anyModem
if not modem then
    error "No modem found; exiting..."
end
modem = peripheral.getName(modem)

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

local solarSystem = settings.get("solarSystem", "minecraft:overworld")

local preferManual = settings.get("preferManual", false)
local autoIrisProperty = concurrent.property(settings.get("autoIris", true))
local enableAuditProperty = concurrent.property(settings.get("enableAudit", false))

local id = math.random(100000000000000)

local handlers = {}

local addressBuffer = {}

local function playSound(sound)
    return job.async(function()
        if speaker and fs.exists(sound) then
            local dfpwm = require 'cc.audio.dfpwm'
            local decoder = dfpwm.make_decoder()
            while true do
                for chunk in io.lines(sound, 16 * 1024) do
                    local buffer = decoder(chunk)

                    while not peripheral.call(speaker, 'playAudio', buffer, 100) do
                        os.pullEvent('speaker_audio_empty')
                    end
                end
            end
        end
    end)
end

job.run(function()

local mStargateGeneration = stargate.getStargateGeneration()
local mStargateVariant = stargate.getStargateVariant()
local mStargateType = stargate.getStargateType()
local mLocalAddress
if tier >= 3 then
    mLocalAddress = stargate.getLocalAddress()
else
    mLocalAddress = {}
end

local emptyJob = job.async(function()end)

local function callOrDefault(method, default)
    if method then
        return method()
    else
        return default
    end
end

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
        if autoIrisProperty.value then
            stargate.closeIris()
        end
        playAlarmTask = playSound("offworld.dfpwm")
    else
        if autoIrisProperty.value then
            stargate.openIris()
        end
    end
end)

local isDialingProperty = concurrent.property(false)
local engagedChevronsProperty = concurrent.property(stargate.getChevronsEngaged())
local dialedAddressProperty
do
    local dialedAddress
    if tier >= 2 then
        dialedAddress = stargate.getDialedAddress()
    else
        dialedAddress = {}
    end
    dialedAddressProperty = concurrent.property(dialedAddress)
end
local energyTargetProperty = concurrent.property(stargate.getEnergyTarget())
local connectedAddressProperty
do
    local connectedAddress
    if tier >= 3 then
        connectedAddress = stargate.getConnectedAddress()
    else
        connectedAddress = {}
    end
    connectedAddressProperty = concurrent.property(connectedAddress)
end
local isNetworkRestrictedProperty
do
    local isNetworkRestricted
    if tier >=3 then
        isNetworkRestricted = stargate.isNetworkRestricted()
    else
        isNetworkRestricted = false
    end
    isNetworkRestrictedProperty = concurrent.property(isNetworkRestricted)
end
local networkProperty
do
    local network
    if tier >=3 then
        network = stargate.getNetwork()
    else
        network = false
    end
    networkProperty = concurrent.property(network)
end
local filterTypeProperty
do
    local filterType
    if tier >= 3 then
        filterType = stargate.getFilterType()
    else
        filterType = 0
    end
    filterTypeProperty = concurrent.property(filterType)
end
local function pollNewValues()
    local feedbackCode, feedbackName = stargate.getRecentFeedback();
    return {
        feedbackCode = feedbackCode;
        feedbackName = feedbackName;
        energy = stargate.getEnergy();
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
    result.galaxies = galaxies
    result.solarSystem = solarSystem
    result.tier = tier
    local dialedAddress = dialedAddressProperty.value
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
    result.dialedAddress = dialedAddress;
    result.basic = {
        energy = values.energy;
        energyTarget = energyTargetProperty.value;
        generation = mStargateGeneration;
        variant = mStargateVariant;
        type = mStargateType;
        stargateEnergy = values.stargateEnergy;
        chevronsEngaged = engagedChevronsProperty.value;
        openTime = values.openTime;
        isConnected = isStargateConnectedProperty.value;
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
    connectedAddressProperty
)
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
    while true do
        sleep(DISCOVER_PERIOD)
        pollValuesProperty:set(pollNewValues())
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
        os.pullEvent('stargate_incoming_wormhole')
        isStargateConnectedProperty:set(true)
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
        isDialingProperty:set(false)
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

local function saveAuditEvent(event, record)
    local timestamp = audit.save(event, record)
    record.event = event
    record.timestamp = timestamp
    if wiredModem then
        local message = {
            type = 'audit';
            record = record;
        }
        rpc.broadcast_network(wiredModem, SECURITY_EVENT, message)
    end
end

audit.define('auth', { 'key', 'error' })

function otherside.auth(request)
    local result, reason, key = spkey.auth_continue(request)
    if enableAuditProperty.value then
        saveAuditEvent('auth', { key=key, error=(reason or "") })
    end
    if result then
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

local function encodeSymbol(symbol, slow)
    local isMW = stargate.getStargateType() == "sgjourney:milky_way_stargate"
    if preferManual and isMW and slow then
        encodeSymbolManual(symbol, slow)
    elseif tier >= 2 then
        local engagedTarget = engagedChevronsProperty.value + 1
        stargate.engageSymbol(symbol)
        if slow then
            os.sleep(0.5)
        end
        engagedChevronsProperty:wait_until(function(value) return value == engagedTarget end)
    elseif isMW then
        encodeSymbolManual(symbol, slow)
    end
    insertDialedSymbol(engagedChevronsProperty.value, symbol)
end

local slowDialingEnabled = true

local dialingSequenceTask = emptyJob
local function startDialingSequence()
    return job.async(function()
        playSound("dialing.dfpwm")
        while next(addressBuffer) do
            local symbol = addressBuffer[1]
            encodeSymbol(symbol, slowDialingEnabled)
            table.remove(addressBuffer, 1)
        end
        isDialingProperty:set(false)
    end)
end
job.livedata.subscribe(isDialingProperty, function(isDialing)
    if isDialing then
        dialingSequenceTask = startDialingSequence()
    else
        addressBuffer = {}
        dialingSequenceTask:cancel()
    end
end)

function handlers.engage(symbol)
    local bufferLength = #addressBuffer
    if bufferLength >= 9 then
        return false
    end
    if addressBuffer[bufferLength] == 0 then
        return false
    end
    slowDialingEnabled = true
    addressBuffer[bufferLength + 1] = symbol
    isDialingProperty:set(true)
    return true
end

function handlers.dial(address, slow)
    if not address then return false end
    if isDialingProperty.value then
        return
    end
    slowDialingEnabled = slow
    addressBuffer = address
    addressBuffer[#addressBuffer+1] = 0
    isDialingProperty:set(true)
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

function handlers.register(pkey)
    if wiredModem and not keyring.exists(pkey) then
        rpc.broadcast_network(wiredModem, SECURITY_EVENT, { type = 'register', key = pkey })
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
    if wiredModem then
        rpc.broadcast_network(wiredModem, SECURITY_EVENT, { type = 'setting', setting = setting, value = value })
    end
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
    local r = keyring.forget(pkey)
    if wiredModem and r then
        rpc.broadcast_network(wiredModem, SECURITY_EVENT, { type = 'deny', key = pkey })
    end
end

function security.allow(pkey, name)
    local r = keyring.trust(pkey, name)
    if wiredModem and r then
        rpc.broadcast_network(wiredModem, SECURITY_EVENT, { type = 'allow', key = pkey, name = name })
    end
end

local function broadcastFilterUpdate(list, action, address)
    if wiredModem then
        local message = {
            type = 'filter';
            list = list;
            action = action;
            address = address;
        }
        rpc.broadcast_network(wiredModem, SECURITY_EVENT, message)
    end
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
    stargate.openIris()
end

function security.closeIris()
    stargate.closeIris()
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

local function broadcastEvent(event)
    rpc.broadcast_network(modem, CHANNEL_EVENT, event)
    if wiredModem then
        rpc.broadcast_network(wiredModem, CHANNEL_EVENT, event)
    end
end

job.livedata.subscribe(discoveryMessageProperty, function(discover)
    local event = {
        type = 'discover';
        data = discover;
    }
    broadcastEvent(event)
end)

job.async(function()
    while true do
        local _, _, message = os.pullEvent('stargate_message_received')
        local event = {
            type = 'message';
            data = message;
        }
        job.async(function ()
            broadcastEvent(event)
        end)
    end
end)

do
    local commands = rpc.simple_commands(handlers)
    rpc.server_network(commands, modem, CHANNEL_COMMAND)
    if wiredModem then
        rpc.server_network(commands, wiredModem, CHANNEL_COMMAND)
    end
end

if wiredModem then
    rpc.server_network(rpc.simple_commands(security), wiredModem, SECURITY_COMMAND)
end

local serializeOpts = { compact = true }

local function stargateMessageExchanger(handler)
    local _, _, message = os.pullEvent('stargate_message_received')
    local request = textutils.unserialize(message)
    if request then
        local response = handler(request)
        if response then
            job.async(function()
                stargate.sendStargateMessage(textutils.serialize(response, serializeOpts))
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

end)
