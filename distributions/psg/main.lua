local TIMEOUT = 2
local CHANNEL_EVENT = 47
local CHANNEL_COMMAND = 46

local theme = {
    FrameBG = colors.lightGray,
    FrameFG = colors.black,
    SelectionText = colors.white,
}

-------------------------

local basalt = require 'basalt'
local addresses = require 'addresses'
local job = require 'job'
local rpc = require 'rpc'
local keyring = require 'keyring'
local vault = require 'vault'
local keys = require 'keys'
local concurrent = require 'concurrent'
local resources = require 'resources'

local modem = peripheral.find("modem", function(_, modem) return modem.isWireless() end) or peripheral.find("modem")
if not modem then
    error "No modem found; exiting..."
end
modem = peripheral.getName(modem)

settings.define("psg.fastDialMode", {
    description = "Dial as fast as possible",
    default = false,
    type = "boolean",
})

local fastDialModeInit = settings.get("psg.fastDialMode", false)
local fastDialMode = fastDialModeInit

local stargate = rpc.client_network(modem, CHANNEL_COMMAND, TIMEOUT)

local serializeOpts = { compact = true }

local function othersideExchanger(request)
    job.async(function()
        local message = textutils.serialize(request, serializeOpts)
        pcall(stargate.tell, message)
    end)
    while true do
        local _, response = os.pullEvent('otherside_respond')
        if rpc.is_response(request, response) then
            return response
        end
    end
end

local otherside = rpc.client(othersideExchanger, TIMEOUT)

basalt.setVariable("addressLength", 0)

local serverIdProperty = concurrent.property(nil)

local stats
local addressesTypeMenubar
local addressesList

local currentAddresses = {}

local function dom(path)
    local current = basalt.getActiveFrame()
    for _, segment in ipairs(path) do
        current = current:getObject(segment)
    end
    return current
end

local function loadAddresses()
    if stats then
        local index = addressesTypeMenubar:getItemIndex()
        local newAddresses
        if index == 1 then -- interstellar
            newAddresses = addresses.interstellar(stats.galaxies, stats.solarSystem)
        elseif index == 2 then -- extragalactic
            newAddresses = addresses.extragalactic(stats.galaxies)
        else -- direct
            newAddresses = addresses.direct((stats.advanced or {}).localAddress)
        end
        currentAddresses = newAddresses
        addressesList:clear()
        addressesList:setOffset(0)
        for _, record in ipairs(currentAddresses) do
            addressesList:addItem(record.name)
        end
    end
end

basalt.setVariable("loadAddresses", loadAddresses)

local function selectFrame(self)
    local index = self:getItemIndex()
    local tabs = {
        dom { 'root', 'main', 'addressbook' },
        dom { 'root', 'main', 'dhd' },
        dom { 'root', 'main', 'stats' },
    }
    for i, tab in ipairs(tabs) do
        if i == index then
            tab:show()
        else
            tab:hide()
        end
    end
end

basalt.setVariable("selectFrame", selectFrame)

basalt.setVariable("selectSubFrame", function(self)
    local index = self:getItemIndex()
    local tabs = {
        dom { 'root', 'main', 'stats', 'general' },
        dom { 'root', 'main', 'stats', 'energy' },
        dom { 'root', 'main', 'stats', 'status' },
    }
    for i, tab in ipairs(tabs) do
        if i == index then
            tab:show()
        else
            tab:hide()
        end
    end
end)

local function scroll(button, increment)
    local list = button:getParent():getObject("list")
    local offset = list:getOffset()
    if increment < 0 and offset <= 0 then
        return
    end
    if increment > 0 and offset > #(list:getAll()) - list:getHeight() then
        return
    end
    list:setOffset(offset + increment)
end

basalt.setVariable("scrollUp", function(button)
    scroll(button, -1)
end)

basalt.setVariable("scrollDown", function(button)
    scroll(button, 1)
end)

basalt.setVariable("onFast", function(element)
    fastDialMode = element:getValue()
    settings.set("psg.fastDialMode", fastDialMode)
    settings.save()
end)

local function saveCall(f)
    return function(...)
        local args = { ... }
        job.async(function()
            f(table.unpack(args))
        end)
    end
end

local function dial()
    if stats.basic.isConnected then
        stargate.disconnect()
    else
        local index = addressesList:getItemIndex()
        if index > 0 then
            local dialAddress = currentAddresses[index].address
            stargate.dial(dialAddress, not fastDialMode)
        end
    end
end

dial = saveCall(dial)
basalt.setVariable("dial", dial)

local authKeysList

local function addKeyToKeyringList(key, name)
    local fingerprint = keys.fingerprint(key)
    local text
    if name then
        text = name..' '..fingerprint
    else
        text = fingerprint
    end
    authKeysList:addItem(text, nil, nil, { key=key, name=name })
end

local function register()
    local hostKey = stargate.register(vault.public_key())
    local name = addresses.getname_by_key(stats.solarSystem)
    if keyring.trust(hostKey, name) then
        addKeyToKeyringList(hostKey, name)
    end
end

register = saveCall(register)
basalt.setVariable("register", register)

basalt.setVariable("forget", function()
    local i = authKeysList:getItemIndex()
    if i then
        local item = authKeysList:getItem(i)
        keyring.forget(item.args[1].key)
        authKeysList:removeItem(i)
    end
end)

local function openVault()
    dom { "root", "vault" }:show()
end
basalt.setVariable("openVault", openVault)

local function exitVault()
    dom { "root", "vault" }:hide()
end
basalt.setVariable("exitVault", exitVault)

local function engage(self)
    local symbol = tonumber(self:getValue())
    stargate.engage(symbol)
end

engage = saveCall(engage)
basalt.setVariable("engage", engage)

local function engagePoo()
    if stats.basic.isConnected then
        stargate.disconnect()
    else
        stargate.engage(0)
    end
end

engagePoo = saveCall(engagePoo)
basalt.setVariable("engagePoo", engagePoo)

local function reset()
    stargate.disconnect()
end

reset = saveCall(reset)
basalt.setVariable("reset", reset)

local function hideMessage()
    (dom { 'root', 'message' }):hide()
end

basalt.setVariable("hideMessage", hideMessage)

local function tell()
    local message = dom { 'root', 'main', 'stats', 'status', 'message' }
    local value = table.concat(message:getLines(), '\n')
    stargate.tell(value)
end

tell = saveCall(tell)
basalt.setVariable("tell", tell)

local alertResult

basalt.setVariable("alertAccept", function()
    alertResult:submit(true)
end)

basalt.setVariable("alertCancel", function()
    alertResult:submit(false)
end)

local passwdResult, passwdPasswordElement

basalt.setVariable("passwordDone", function()
    passwdResult:submit(passwdPasswordElement:getValue())
end)

basalt.setVariable("passwordCancel", function()
    passwdResult:submit(nil)
end)

local chpassResult, chpassmsgElement, chpassPasswordElement, chpassConfirmElement

basalt.setVariable("chpassDone", function()
    local password = chpassPasswordElement:getValue()
    local confirm = chpassConfirmElement:getValue()
    if password ~= confirm then
        job.async(function()
            chpassmsgElement:setText("Passwords not equal!")
            sleep(5)
            chpassmsgElement:setText("")
        end)
        return
    end
    chpassResult:submit(password)
end)

basalt.setVariable("chpassCancel", function()
    chpassResult:submit(nil)
end)

local function synchPasswordButtonText()
    local passwordButtonElement = dom { 'root', 'vault', 'password' }
    local passwordButtonText
    if vault.is_encrypted() then
        passwordButtonText = "Del password"
    else
        passwordButtonText = "Set password"
    end
    passwordButtonElement:setText(passwordButtonText)
end

local passwd, alert, chpass

basalt.setVariable("setPassword", function(button)
    job.async(function()
        if vault.is_encrypted() then
            local password = passwd()
            if not password then
                return
            end
            local ok, reason = vault.decrypt_key(password)
            if not ok then
                alert({"Failed to decrypt:", reason}, nil, "OK")
                return
            end
            synchPasswordButtonText()
        else
            local password = chpass()
            if not password then
                return
            end
            vault.encrypt_key(password)
            synchPasswordButtonText()
        end
    end)
end)

job.run(function()

basalt.createFrame()
    :setTheme(theme)
    :addLayoutFromString(resources.load("psg.xml"))

local mainFrame = dom { 'root', 'main' }
local alertFrame = dom { 'root', 'alert' }
local alertContentElement = dom { 'root', 'alert', 'content' }
local alertAcceptElement = dom { 'root', 'alert', 'accept' }
local alertCancelElement = dom { 'root', 'alert', 'cancel' }

function alert(text, accept, cancel)
    alertContentElement:clear()
    for _, line in ipairs(text) do
        alertContentElement:addLine(line)
    end
    if accept then
        alertAcceptElement:show()
        alertAcceptElement:setText(accept)
    else
        alertAcceptElement:hide()
    end
    alertCancelElement:setText(cancel)
    local j = job.async(function()
        alertResult = concurrent.future()
        alertFrame:show()
        mainFrame:disable()
        return alertResult:get()
    end)
    j:finnalize(function()
        alertResult = nil
        alertFrame:hide()
        mainFrame:enable()
    end)
    return j:await()
end

local passwdFrame = dom { 'root', 'passwd' }
passwdPasswordElement = dom { 'root', 'passwd', 'password' }

function passwd()
    passwdPasswordElement:setValue("")
    local j = job.async(function()
        passwdResult = concurrent.future()
        passwdFrame:show()
        mainFrame:disable()
        passwdPasswordElement:setFocus()
        return passwdResult:get()
    end)
    j:finnalize(function()
        passwdResult = nil
        passwdFrame:hide()
        mainFrame:enable()
        mainFrame:setFocus()
        passwdPasswordElement:setValue("")
    end)
    return j:await()
end

local chpassFrame = dom { 'root', 'chpass' }
chpassmsgElement = chpassFrame:getObject('chpassmsg')
chpassPasswordElement = chpassFrame:getObject('password')
chpassConfirmElement = chpassFrame:getObject('confirm')

function chpass()
    chpassmsgElement:setText("")
    chpassPasswordElement:setValue("")
    chpassConfirmElement:setValue("")
    local j = job.async(function()
        chpassResult = concurrent.future()
        chpassFrame:show()
        mainFrame:disable()
        chpassPasswordElement:setFocus()
        return chpassResult:get()
    end)
    j:finnalize(function()
        chpassResult = nil
        chpassFrame:hide()
        mainFrame:enable()
        mainFrame:setFocus()
        chpassPasswordElement:setValue("")
        chpassConfirmElement:setValue("")
    end)
    return j:await()
end

authKeysList = dom { 'root', 'vault', 'list' }

do -- setup vault
    dom { 'root', 'vault', 'hostKey' }:setText(keys.fingerprint(vault.public_key()))
    local authKeys = keyring.get_all()
    for _, key in ipairs(authKeys) do
        addKeyToKeyringList(key.key, key.name)
    end
end

addressesTypeMenubar = dom { 'root', 'main', 'addressbook', 'addressType' }
addressesList = dom { 'root', 'main', 'addressbook', 'list' }
local dialButton = dom { 'root', 'main', 'addressbook', 'dial' }

local function updateDialButtonText()
    local text
    if stats.basic.isConnected then
        if stats.basic.isWormholeOpen then
            text = "Disconnect"
        else
            text = "Dialing..."
        end
    else
        text = "Dial"
    end
    dialButton:setText(text)
end

local dialNameLabel = dom { 'root', 'main', 'dhd', 'name' }
local dialAddress = dom { 'root', 'main', 'dhd', 'dialAddress' }
local bufferAddress = dom { 'root', 'main', 'dhd', 'bufferAddress' }

local function updateDialAddress()
    local dialAddressText, bufferAddressText
    local dialedAddress = stats.dialedAddress
    dialAddressText = addresses.tostring(dialedAddress)
    bufferAddressText = addresses.tostring(stats.addressBuffer)
    if dialAddressText ~= "" and bufferAddressText ~= "" then
        bufferAddressText = "-"..bufferAddressText
    end
    local totalWidth = #dialAddressText + #bufferAddressText
    dialAddress:setText(dialAddressText)
    dialAddress:setPosition("(parent.w - "..totalWidth..")/2")
    bufferAddress:setText(bufferAddressText)
    if not next(dialedAddress) then
        dialNameLabel:setText("")
    elseif stats.basic.isWormholeOpen or stats.basic.isDialingOut then
        dialNameLabel:setText(addresses.getname(dialedAddress, stats.galaxies) or "")
    end
end

-- stats begin

local localAddressLabel = dom { 'root', 'main', 'stats', 'general', 'localAddress' }
local generationLabel = dom { 'root', 'main', 'stats', 'general', 'generation' }
local typeLabel = dom { 'root', 'main', 'stats', 'general', 'type' }
local variantLabel = dom { 'root', 'main', 'stats', 'general', 'variant' }
local feedbackCodeLabel = dom { 'root', 'main', 'stats', 'general', 'feedbackCode' }
local feedbackMessageLabel = dom { 'root', 'main', 'stats', 'general', 'feedbackMessage' }

local energyLabel = dom { 'root', 'main', 'stats', 'energy', 'energy' }
local stargateEnergyLabel = dom { 'root', 'main', 'stats', 'energy', 'stargateEnergy' }
local targetEnergyLabel = dom { 'root', 'main', 'stats', 'energy', 'targetEnergy' }
local energyProgressbar = dom { 'root', 'main', 'stats', 'energy', 'energyProgress' }

local isConnectedCheckbox = dom { 'root', 'main', 'stats', 'status', 'isConnected' }
local isWormholeCheckbox = dom { 'root', 'main', 'stats', 'status', 'isWormhole' }
local isDialingOutCheckbox = dom { 'root', 'main', 'stats', 'status', 'isDialingOut' }
local openTimeLabel = dom { 'root', 'main', 'stats', 'status', 'openTime' }
local chevronsLabel = dom { 'root', 'main', 'stats', 'status', 'chevrons' }
local connectedNameLabel = dom { 'root', 'main', 'stats', 'status', 'connectedName' }
local connectedAddressLabel = dom { 'root', 'main', 'stats', 'status', 'connectedAddress' }

local function updateConnectedAddresds(address)
    if not next(address) then
        connectedNameLabel:setText("")
    elseif stats.basic.isWormholeOpen or stats.basic.isDialingOut then
        connectedNameLabel:setText(addresses.getname(address, stats.galaxies) or "")
    end
    connectedAddressLabel:setText(addresses.tostring(address))
end

local function updateStats()
    if stats then
        generationLabel:setText(tostring(stats.basic.generation))
        typeLabel:setText(tostring(stats.basic.type))
        variantLabel:setText(tostring(stats.basic.variant))
        if stats.advanced then
            localAddressLabel:setText(addresses.tostring(stats.advanced.localAddress))
        else
            localAddressLabel:setText("N/A")
        end
        feedbackCodeLabel:setText(tostring(stats.basic.recentFeedbackCode))
        if stats.crystal then
            feedbackMessageLabel:setText(stats.crystal.recentFeedbackName)
        else
            feedbackMessageLabel:setText("N/A")
        end

        energyLabel:setText(tostring(stats.basic.energy).." FE")
        stargateEnergyLabel:setText(tostring(stats.basic.stargateEnergy).." FE")
        targetEnergyLabel:setText(tostring(stats.basic.energyTarget).." FE")
        if stats.basic.stargateEnergy > stats.basic.energyTarget then
            energyProgressbar:setProgress(100)
        else
            energyProgressbar:setProgress(stats.basic.stargateEnergy/stats.basic.energyTarget*100)
        end

        isConnectedCheckbox:setValue(stats.basic.isConnected)
        isWormholeCheckbox:setValue(stats.basic.isWormholeOpen)
        isDialingOutCheckbox:setValue(stats.basic.isDialingOut)
        openTimeLabel:setValue(tostring(stats.basic.openTime).." ticks")
        chevronsLabel:setText(tostring(stats.basic.chevronsEngaged))
        if stats.advanced then
            updateConnectedAddresds(stats.advanced.connectedAddress)
        else
            connectedAddressLabel:setText("N/A")
            connectedNameLabel:setText("")
        end
    end
end

-- stats end

job.livedata.subscribe(serverIdProperty, function()
    loadAddresses()
end)

local isWormholeProperty = concurrent.property(false)

local lastJob = job.async(function()end)

job.livedata.subscribe(isWormholeProperty, function(isWormhole)
    if isWormhole then
        if not stats.basic.isDialingOut then
            return
        end
        lastJob = job.running()
        local nonce = vault.gen_nonce()
        local ok, response = pcall(job.retry, 5, otherside.info, nonce)
        if ok then
            local valid, reason = vault.verify(nonce, response)
            local message = textutils.unserialise(response.message)
            local isIrisClosed = message.payload.isIrisClosed
            if valid and not isIrisClosed then
                return
            end
            local verificationMessage
            if valid then
                verificationMessage = "Known destination"
            else
                verificationMessage = "WARN: "..reason
            end
            local irisMessage
            local acceptText
            if isIrisClosed then
                irisMessage = "Iris is closed!"
                acceptText = "Open iris"
            else
                irisMessage = "Iris is opened, trust?"
                acceptText = false
            end
            local doOpen = alert(
                {
                    "Dest: ".. keys.fingerprint(message.key);
                    verificationMessage;
                    irisMessage;
                },
                acceptText, "Cancel"
            )
            if doOpen then
                local key = vault.private_key()
                if not key then
                    while true do
                        local password = passwd()
                        if not password then
                            return
                        end
                        key, reason = vault.private_key(password)
                        if key then
                            break
                        end
                        alert({reason}, nil, "Retry")
                    end
                end
                local request = vault.make_auth_request(key, message.session)
                ok, reason = otherside.auth(request)
                if not ok then
                    alert({"NOT AUTHORIZED:", reason}, false, "OK")
                else
                    alert({"Authorized!"}, false, "OK")
                end
            end
        else
            alert({"No response!", "Iris state is unknown!"}, false, "OK")
        end
    else
        lastJob:cancel()
    end
end)

local function spawnHaltTimeout()
    return job.async(function()
        sleep(TIMEOUT)
        mainFrame:hide()
        isWormholeProperty:set(false)
    end)
end

local haltJob = spawnHaltTimeout()

rpc.subscribe_network(modem, CHANNEL_EVENT, function(event)
    local type = event.type
    local data = event.data
    haltJob:cancel()
    haltJob = spawnHaltTimeout()
    if type == 'discover' then
        mainFrame:show()
        stats = data
        serverIdProperty:set(stats.id)
        updateDialButtonText()
        updateDialAddress()
        updateStats()
        isWormholeProperty:set(stats.basic.isWormholeOpen)
    elseif type == 'message' then
        local message = data
        local decoded = textutils.unserialise(message)
        if _G.type(decoded) == 'table' and decoded.magic == 'rpc' then
            os.queueEvent('otherside_respond', decoded)
        else
            local messageFrame = dom { 'root', 'message' }
            local content = dom { 'root', 'message', 'content' }
            content:clear()
            content:addLine(message)
            messageFrame:show()
        end
    end
end)

job.async(basalt.autoUpdate)

do
    local fastElement = dom { 'root', 'main', 'addressbook', 'fast' }
    fastElement:setValue(fastDialModeInit)
    synchPasswordButtonText()
end

end)