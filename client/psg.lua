
local TIMEOUT = 2

-------------------------

local basalt = require 'basalt'
local stargate = require 'stargate'
local addresses = require 'addresses'

basalt.setVariable("addressLength", 0)

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

local deepEquals
deepEquals = function(a, b)
    if a == b then
        return true
    end
    if type(a) ~= 'table' or type(b) ~= 'table' then
        return false
    end
    for k in pairs(a) do
        if not deepEquals(a[k], b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if not deepEquals(a[k], b[k]) then
            return false
        end
    end
    return true
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
        if not deepEquals(newAddresses, currentAddresses) then
            currentAddresses = newAddresses
            addressesList:clear()
            for _, record in ipairs(currentAddresses) do
                addressesList:addItem(record.name)
            end
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

local function selectSubFrame(self)
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
end

basalt.setVariable("selectSubFrame", selectSubFrame)

local function listScroll(increment)
    local offset = addressesList:getOffset()
    if increment < 0 and offset <= 0 then
        return
    end
    if increment > 0 and offset > #(addressesList:getAll()) - addressesList:getHeight() then
        return
    end
    addressesList:setOffset(offset + increment)
end

local function listUp()
    listScroll(-1)
end

basalt.setVariable("listUp", listUp)

local function listDown()
    listScroll(1)
end

basalt.setVariable("listDown", listDown)

local function saveCall(f)
    local g = function(...)
        pcall(f, ...)
    end
    return basalt.schedule(g)
end

local function dial()
    if stats.basic.isConnected then
        stargate.disconnect()
    else
        local fast = dom { 'root', 'main', 'addressbook', 'fast' }
        local index = addressesList:getItemIndex()
        if index > 0 then
            local dialAddress = {}
            for _, symbol in ipairs(currentAddresses[index].address) do
                table.insert(dialAddress, symbol)
            end
            table.insert(dialAddress, 0)
            stargate.dial(dialAddress, fast:getValue())
        end
    end
end

dial = saveCall(dial)
basalt.setVariable("dial", dial)

local function engage(self)
    local symbol = tonumber(self:getValue())
    stargate.dial({symbol})
end

engage = saveCall(engage)
basalt.setVariable("engage", engage)

local function engagePoo()
    if stats.basic.isConnected then
        stargate.disconnect()
    else
        stargate.dial({0})
    end
end

engagePoo = saveCall(engagePoo)
basalt.setVariable("engagePoo", engagePoo)

local function reset()
    stargate.disconnect()
end

reset = saveCall(reset)
basalt.setVariable("reset", reset)

local function restrictNetwork(self)
    os.sleep(0)
    if not stargate.restrict(self:getValue()) then
        self:setValue(stats.advanced and stats.advanced.isNetworkRestricted or false)
    end
end

restrictNetwork = saveCall(restrictNetwork)
basalt.setVariable("restrictNetwork", restrictNetwork)

local function setNetwork()
    local newNetworkId = dom { 'root', 'main', 'stats', 'general', 'newNetworkId' }
    local value = newNetworkId:getValue()
    if stargate.network(tonumber(value)) then
        local network = dom { 'root', 'main', 'stats', 'general', 'networkId' }
        network:setText(value)
    end
end

setNetwork = saveCall(setNetwork)
basalt.setVariable("setNetwork", setNetwork)

local function hideMessage()
    (dom { 'root', 'message' }):hide()
end

basalt.setVariable("hideMessage", hideMessage)

local function setEnergyTarget()
    local newTarget = dom { 'root', 'main', 'stats', 'energy', 'newTarget' }
    local value = newTarget:getValue()
    local newValue = stargate.target(tonumber(value))
    if newValue then
        local targetEnergy = dom { 'root', 'main', 'stats', 'energy', 'targetEnergy' }
        targetEnergy:setText(tostring(newValue).." RF")
    end
end

setEnergyTarget = saveCall(setEnergyTarget)
basalt.setVariable("setEnergyTarget", setEnergyTarget)

local function tell()
    local message = dom { 'root', 'main', 'stats', 'status', 'message' }
    local value = table.concat(message:getLines(), '\n')
    stargate.tell(value)
end

tell = saveCall(tell)
basalt.setVariable("tell", tell)

local root = basalt.createFrame()
    :setTheme({FrameBG = colors.lightGray, FrameFG = colors.black})
    :addLayout("psg.xml")

local mainFrame = dom { 'root', 'main' }
addressesTypeMenubar = dom { 'root', 'main', 'addressbook', 'addressType' }
addressesList = dom { 'root', 'main', 'addressbook', 'addresses' }
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

local dialAddress = dom { 'root', 'main', 'dhd', 'dialAddress' }
local bufferAddress = dom { 'root', 'main', 'dhd', 'bufferAddress' }

local function addressToString(address)
    return table.concat(address, '-')
end

local function updateDialAddress()
    local dialAddressText, bufferAddressText
    if stats.crystal then
        dialAddressText = addressToString(stats.crystal.dialedAddress)
    else
        dialAddressText = ""
    end
    bufferAddressText = addressToString(stats.addressBuffer)
    if dialAddressText ~= "" and bufferAddressText ~= "" then
        bufferAddressText = "-"..bufferAddressText
    end
    local totalWidth = #dialAddressText + #bufferAddressText
    dialAddress:setText(dialAddressText)
    dialAddress:setPosition("(parent.w - "..totalWidth..")/2")
    bufferAddress:setText(bufferAddressText)
end

-- stats begin

local localAddressLabel = dom { 'root', 'main', 'stats', 'general', 'localAddress' }
local generationLabel = dom { 'root', 'main', 'stats', 'general', 'generation' }
local typeLabel = dom { 'root', 'main', 'stats', 'general', 'type' }
local networkIdLabel = dom { 'root', 'main', 'stats', 'general', 'networkId' }
local networkRestrictedCheckbox = dom { 'root', 'main', 'stats', 'general', 'networkRestricted' }
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
local connectedAddressLabel = dom { 'root', 'main', 'stats', 'status', 'connectedAddress' }

local function updateStats()
    if stats then
        generationLabel:setText(tostring(stats.basic.generation))
        typeLabel:setText(tostring(stats.basic.type))
        if stats.advanced then
            localAddressLabel:setText(addressToString(stats.advanced.localAddress))
            networkIdLabel:setText(tostring(stats.advanced.network))
        else
            localAddressLabel:setText("N/A")
            networkIdLabel:setText("N/A")
        end
        networkRestrictedCheckbox:setValue(stats.advanced and stats.advanced.isNetworkRestricted)
        feedbackCodeLabel:setText(tostring(stats.basic.recentFeedbackCode))
        if stats.crystal then
            feedbackMessageLabel:setText(stats.crystal.recentFeedbackName)
        else
            feedbackMessageLabel:setText("N/A")
        end

        energyLabel:setText(tostring(stats.basic.energy).." RF")
        stargateEnergyLabel:setText(tostring(stats.basic.stargateEnergy).." RF")
        targetEnergyLabel:setText(tostring(stats.basic.energyTarget).." RF")
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
            connectedAddressLabel:setText(addressToString(stats.advanced.connectedAddress))
        else
            connectedAddressLabel:setText("N/A")
        end
    end
end

-- stats end

local haltTimer

root:addThread():start(function()
    stargate.eventLoop(function(command, data)
        if command == 'discover' then
            if haltTimer then
                os.cancelTimer(haltTimer)
            end
            haltTimer = os.startTimer(TIMEOUT)
            mainFrame:show()
            stats = data
            loadAddresses()
            updateDialButtonText()
            updateDialAddress()
            updateStats()
        elseif command == 'event' then
            local eventType = data[1]
            if eventType == "stargate_message_received" then
                local messageFrame = dom { 'root', 'message' }
                local content = dom { 'root', 'message', 'content' }
                content:clear()
                content:addLine(data[2])
                messageFrame:show()
            end
        end
    end)
end)

root:addThread():start(function()
    while true do
        local _, timer = os.pullEvent('timer')
        if timer == haltTimer then
            haltTimer = nil
            stats = nil
            mainFrame:hide()
        end
    end
end)

basalt.autoUpdate()
