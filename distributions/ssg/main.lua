local TIMEOUT = 2
local SECURITY_COMMAND = 48
local SECURITY_EVENT = 49

local THEME = {
    FrameBG = colors.lightBlue;
    FrameFG = colors.black;
    ButtonBG = colors.cyan;
    MenubarBG = colors.cyan;
    SelectionBG = colors.blue;
    SelectionText = colors.white;
    ListBG = colors.cyan;
    InputBG = colors.lightBlue;
    CheckboxBG = colors.white;
    CheckboxText = colors.black;
}

local basalt = require 'basalt'
local job = require 'job'
local rpc = require 'rpc'
local keys = require 'keys'
local concurrent = require 'concurrent'
local printer = require 'printer'
local resources = require 'resources'

local modem = peripheral.find("modem", function(_, modem) return not modem.isWireless() end)
if not modem then
    error "No modem found; exiting..."
end
modem = peripheral.getName(modem)

local client = rpc.client_network(modem, SECURITY_COMMAND, TIMEOUT)

local initializedProperty = concurrent.property(false)

local function dom(path)
    local current = basalt.getActiveFrame()
    for _, segment in ipairs(path) do
        current = current:getObject(segment)
    end
    return current
end

basalt.setVariable("selectFrame", function(self)
    local index = self:getItemIndex()
    local tabs = {
        dom { 'root', 'main', 'keys' },
        dom { 'root', 'main', 'audit' },
        dom { 'root', 'main', 'settings' },
        dom { 'root', 'main', 'filter' },
    }
    for i, tab in ipairs(tabs) do
        if i == index then
            tab:show()
        else
            tab:hide()
        end
    end
end)

local alertResult, alert

basalt.setVariable("alertAccept", function()
    alertResult:submit(true)
end)

basalt.setVariable("alertCancel", function()
    alertResult:submit(false)
end)

local selectedFilterListProperty = concurrent.property(1)

basalt.setVariable("selectFilterList", function(self)
    local index = self:getItemIndex()
    selectedFilterListProperty:set(index)
end)

local keysList

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

basalt.setVariable("allow", function()
    job.async(function()
        local i = keysList:getItemIndex()
        if i then
            local key = keysList:getItem(i).args[1].key
            client.allow(key)
        end
    end)
end)

basalt.setVariable("deny", function()
    job.async(function()
        local i = keysList:getItemIndex()
        if i then
            local key = keysList:getItem(i).args[1].key
            client.deny(key)
        end
    end)
end)

basalt.setVariable("inputDigit", function(button)
    local input = dom { 'root', 'number', 'input' }
    local digit = button:getValue()
    input:setValue(tostring(tonumber(input:getValue()..digit)))
    input:setFocus()
end)

basalt.setVariable("numberErase", function()
    local input = dom { 'root', 'number', 'input' }
    local value = tostring(input:getValue())
    if #value ~= 0 then
        input:setValue(value:sub(1, -2))
    end
    input:setFocus()
end)

local numberDialogResult

basalt.setVariable("numberDone", function()
    local input = dom { 'root', 'number', 'input' }
    local value = input:getValue()
    numberDialogResult:submit(tonumber(value) or 0)
end)

basalt.setVariable("numberBack", function()
    numberDialogResult:submit(nil)
end)

local inputAddressProperty = concurrent.property({})

basalt.setVariable("inputSymbol", function(element)
    local symbol = tonumber(element:getValue())
    local address = inputAddressProperty.value
    local length = #address
    if length < 8 then
        for i=1, length do
            if address[i] == symbol then
                return
            end
        end
        local newAddress = { table.unpack(address) }
        newAddress[length + 1] = symbol
        inputAddressProperty:set(newAddress)
    end
end)

basalt.setVariable("eraseSymbol", function()
    local address = inputAddressProperty.value
    local length = #address
    if length > 0 then
        local newAddress = { table.unpack(address, 1, length - 1) }
        inputAddressProperty:set(newAddress)
    end
end)

local addressDialogResult

basalt.setVariable("addressDone", function()
    addressDialogResult:submit(inputAddressProperty.value)
end)

basalt.setVariable("addressBack", function()
    addressDialogResult:submit(nil)
end)

local inputAddressDialog, inputNumberDialog

basalt.setVariable("addAddressToFilter", function()
    local listType = selectedFilterListProperty.value
    job.async(function()
        local newAddress = inputAddressDialog():await()
        if newAddress then
            if listType == 1 then
                client.allowlistAdd(newAddress)
            else
                client.denylistAdd(newAddress)
            end
        end
    end)
end)

local allowlistElement, denylistElement

basalt.setVariable("delAddressFromFilter", function()
    local listType = selectedFilterListProperty.value
    local list
    if listType == 1 then
        list = allowlistElement
    else
        list = denylistElement
    end
    local index = list:getItemIndex()
    if not index then
        return
    end
    local item = list:getItem(index)
    local address = item.args[1]
    job.async(function()
        if listType == 1 then
            client.allowlistDel(address)
        else
            client.denylistDel(address)
        end
    end)
end)

basalt.setVariable("syncFilter", function()
    local listType = selectedFilterListProperty.value
    job.async(function()
        if listType == 1 then
            client.allowlistSync()
        else
            client.denylistSync()
        end
    end)
end)

basalt.setVariable("setFilterMode", function(element)
    local name = element:getName()
    job.async(function()
        client.setFilterMode(name)
    end)
end)

local energyTargetElement, networkIdElement, isNetRestrictedElement, autoIrisElement, enableAuditElement

local function setEnergyTargetText(energyTarget)
    energyTargetElement:setText(tostring(energyTarget).." FE")
end

basalt.setVariable("setEnergyTarget", function()
    local init = tonumber(energyTargetElement:getValue():sub(1, -4))
    job.async(function()
        local result = inputNumberDialog(init):await()
        if result then
            client.setEnergyTarget(result)
        end
    end)
end)

basalt.setVariable("setNetworkId", function()
    local init = tonumber(networkIdElement:getValue())
    job.async(function()
        local result = inputNumberDialog(init):await()
        if result then
            client.setNetwork(result)
        end
    end)
end)

local function checkboxButtonState(element)
    return element:getValue() == "*"
end

basalt.setVariable("setNetRestricted", function(element)
    local value = checkboxButtonState(element)
    job.async(function()
        client.restrictNetwork(not value)
    end)
end)

basalt.setVariable("setAutoIris", function(element)
    local value = checkboxButtonState(element)
    job.async(function()
        client.setAutoIris(not value)
    end)
end)

basalt.setVariable("setEnableAudit", function(element)
    local value = checkboxButtonState(element)
    job.async(function()
        client.setEnableAudit(not value)
    end)
end)

basalt.setVariable("openIris", function()
    job.async(function()
        client.openIris()
    end)
end)

basalt.setVariable("closeIris", function()
    job.async(function()
        client.closeIris()
    end)
end)

local newAuditEventsProperty = concurrent.property(0)
local auditPageNumberProperty = concurrent.property(1)
local auditDirectionProperty = concurrent.property('tail')
local shouldFetchAuditProperty = concurrent.property(false)
local auditListElement, auditDirectionElement, auditEventWindow

basalt.setVariable("auditEventBack", function()
    dom { 'root', 'main' }:enable()
    auditEventWindow:hide()
end)

local function getAuditListElement()
    if auditListElement then
        return auditListElement
    end
    auditListElement = dom { 'root', 'main', 'audit', 'list' }
    return auditListElement
end

local function getAuditDirectionElement()
    if auditDirectionElement then
        return auditDirectionElement
    end
    auditDirectionElement = dom { 'root', 'main', 'audit', 'direction' }
    return auditDirectionElement
end

local function getAuditDirection()
    return getAuditDirectionElement():getItemIndex() == 1 and 'tail' or 'head'
end

basalt.setVariable("switchAuditDirection", function()
    local direction = getAuditDirection()
    auditDirectionProperty:set(direction)
end)

local auditEventDialog

basalt.setVariable("auditShowEvent", function()
    local list = getAuditListElement()
    local i = list:getItemIndex()
    local item = list:getItem(i)
    auditEventDialog(item.args[1])
end)

basalt.setVariable("auditPrevPage", function()
    auditPageNumberProperty:set(auditPageNumberProperty.value - 1)
end)

basalt.setVariable("auditNextPage", function()
    auditPageNumberProperty:set(auditPageNumberProperty.value + 1)
end)

basalt.setVariable("auditDeletePage", function()
    local size = getAuditListElement():getHeight()
    job.async(function()
        client.erase(size)
        shouldFetchAuditProperty:set(true)
    end)
end)

basalt.setVariable("printAuditEvent", function()
    local conentElement = dom { 'root', 'event', 'content' }
    local context = printer.print("Event", conentElement:getValue())
    local eventFrame = dom { 'root', 'event' }
    eventFrame:disable()
    job.async(function()
        while true do
            local ok, err = context:continue()
            if ok then
                break
            end
            local continue = alert(err, "Continue", "Cancel"):await()
            if not continue then
                context:cancel()
                break
            end
        end
    end):finnalize(function()
        eventFrame:enable()
    end)
end)

basalt.setVariable("printAuditPage", function()
    local items = getAuditListElement():getAll()
    local events = {}
    for _, item in ipairs(items) do
        table.insert(events, item.args[1])
    end
    local context = printer.print("Audit", textutils.serialise(events))
    job.async(function()
        while true do
            local ok, err = context:continue()
            if ok then
                break
            end
            local continue = alert(err, "Continue", "Cancel"):await()
            if not continue then
                context:cancel()
                break
            end
        end
    end)
end)

job.run(function()

basalt.createFrame()
    :setTheme(THEME)
    :addLayoutFromString(resources.load("ssg.xml"))

local mainFrame = dom { 'root', 'main' }
local alertFrame = dom { 'root', 'alert' }
local alertContentElement = dom { 'root', 'alert', 'content' }
local alertAcceptElement = dom { 'root', 'alert', 'control', 'accept' }
local alertCancelElement = dom { 'root', 'alert', 'control', 'cancel' }

local function showOnText(element, text)
    if text then
        element:setText(text)
        element:show()
    else
        element:hide()
    end
end

function alert(message, accept, cancel)
    alertContentElement:setText(message)
    showOnText(alertAcceptElement, accept)
    showOnText(alertCancelElement, cancel)
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
    return j
end

job.livedata.subscribe(selectedFilterListProperty, function(index)
    local allowlist = dom { 'root', 'main', 'filter', 'allowlist' }
    local denylist = dom { 'root', 'main', 'filter', 'denylist' }
    if index == 1 then
        allowlist:show()
        denylist:hide()
    else
        allowlist:hide()
        denylist:show()
    end
end)

local addressDialogWindow = dom { 'root', 'address' }
local numberDialogWindow = dom { 'root', 'number' }
auditEventWindow = dom { 'root', 'event' }

if printer.exists() then
    auditEventWindow:getObject('control'):getObject('print'):show()
    dom { 'root', 'main', 'audit', 'op', 'print' }:show()
end

job.livedata.subscribe(inputAddressProperty, function(value)
    local input = addressDialogWindow:getObject('input')
    for i=1, 8 do
        local display = input:getObject("s"..i)
        local symbol = value[i]
        if symbol then
            display:setText(string.format("%02d", symbol))
        else
            display:setText("")
        end
    end
    local doneButton = addressDialogWindow:getObject("control"):getObject("done")
    if #value >= 6 then
        doneButton:setBackground(colors.green)
        doneButton:enable()
    else
        doneButton:setBackground(colors.gray)
        doneButton:disable()
    end
end)

job.async(function()
    while true do
        local _, text = os.pullEvent('paste')
        if addressDialogWindow:isVisible() then
            local address = { table.unpack(inputAddressProperty.value) }
            local symbols = {}
            for _, symbol in ipairs(address) do
                symbols[symbol] = true
            end
            for value in text:gmatch("%d+") do
                local symbol = assert(tonumber(value))
                if symbol > 0 and symbol < 48 and not symbols[symbol] then
                    symbols[symbol] = true
                    table.insert(address, symbol)
                    if #address >= 8 then
                        break
                    end
                end
            end
            inputAddressProperty:set(address)
        end
    end
end)

inputAddressDialog = function()
    local main = dom { 'root', 'main' }
    local task = job.async(function()
        addressDialogResult = concurrent.future()
        inputAddressProperty:set({})
        main:disable()
        addressDialogWindow:show()
        addressDialogWindow:setFocus()
        return addressDialogResult:get()
    end)
    task:finnalize(function()
        addressDialogWindow:hide()
        main:enable()
        addressDialogResult = nil
    end)
    return task
end

inputNumberDialog = function(initial)
    local main = dom { 'root', 'main' }
    local input = numberDialogWindow:getObject('input')
    local task = job.async(function()
        numberDialogResult = concurrent.future()
        input:setValue(initial)
        main:disable()
        numberDialogWindow:show()
        numberDialogWindow:setFocus()
        return numberDialogResult:get()
    end)
    task:finnalize(function()
        numberDialogWindow:hide()
        main:enable()
        numberDialogResult = nil
    end)
    return task
end

auditEventDialog = function(event)
    local main = dom { 'root', 'main' }
    local content = auditEventWindow:getObject('content')
    content:setText(textutils.serialise(event))
    main:disable()
    auditEventWindow:show()
    auditEventWindow:setFocus()
end

keysList = dom { 'root', 'main', 'keys', 'list' }

energyTargetElement = dom { 'root', 'main', 'settings', 'energyTarget' }
networkIdElement = dom { 'root', 'main', 'settings', 'advanced', 'networkId' }
isNetRestrictedElement = dom { 'root', 'main', 'settings', 'advanced', 'isNetRestricted' }
autoIrisElement = dom { 'root', 'main', 'settings', 'iris', 'autoIris' }
local irisElement = dom { 'root', 'main', 'settings', 'iris', 'iris' }
local irisDurabilityBarElement = dom { 'root', 'main', 'settings', 'iris', 'irisDurabilityBar' }
local irisDurabilityElement = dom { 'root', 'main', 'settings', 'iris', 'irisDurability' }
enableAuditElement = dom { 'root', 'main', 'settings', 'enableAudit' }
allowlistElement = dom { 'root', 'main', 'filter', 'allowlist', 'list' }
denylistElement = dom { 'root', 'main', 'filter', 'denylist', 'list' }
local filterModeElement = dom { 'root', 'main', 'filter', 'mode' }
local allowModeElement = filterModeElement:getObject('allow')
local noneModeElement = filterModeElement:getObject('none')
local denyModeElement = filterModeElement:getObject('deny')

local function addFilterItem(list, address)
    list:addItem("-"..table.concat(address, "-").."-", nil, nil, address)
end

local function setSelected(button)
    button:setForeground(colors.white)
    button:setBackground(colors.blue)
    button:disable()
end

local function setDeselected(button, bgColor)
    button:setForeground(colors.black)
    button:setBackground(bgColor)
    button:enable()
end

local function updateFilterModeElement(mode)
    if mode == 'allow' then
        setSelected(allowModeElement)
        setDeselected(noneModeElement, colors.yellow)
        setDeselected(denyModeElement, colors.red)
    elseif mode == 'deny' then
        setDeselected(allowModeElement, colors.green)
        setDeselected(noneModeElement, colors.yellow)
        setSelected(denyModeElement)
    else
        setDeselected(allowModeElement, colors.green)
        setSelected(noneModeElement)
        setDeselected(denyModeElement, colors.red)
    end
end

local function setButtonCheckbox(element, value)
    if value then
        element:setText("*")
    else
        element:setText("")
    end
end

local auditPageLabel = dom { 'root', 'main', 'audit', 'page' }
local auditNewLabel = dom { 'root', 'main', 'audit', 'new' }
local auditDeleteButton = dom { 'root', 'main', 'audit', 'op', 'delete' }
local auditPrevButton = dom { 'root', 'main', 'audit', 'control', 'prev' }

job.livedata.subscribe(auditPageNumberProperty, function(pageNumber)
    auditPageLabel:setText(tostring(pageNumber))
    if pageNumber == 1 then
        auditPrevButton:setBackground(colors.gray)
        auditPrevButton:disable()
    else
        auditPrevButton:setBackground(colors.cyan)
        auditPrevButton:enable()
    end
end)

local showAuditDeleteButtonProperty = job.livedata.combine(function(pageNumber, direction)
    return pageNumber == 1 and direction == 'head'
end, auditPageNumberProperty, auditDirectionProperty)

job.livedata.subscribe(showAuditDeleteButtonProperty, function(show)
    if show then
        auditDeleteButton:show()
    else
        auditDeleteButton:hide()
    end
end)

job.livedata.subscribe(newAuditEventsProperty, function(value)
    auditNewLabel:setText(value)
end)

local function minimizeDirection(direction)
    if direction == 'incoming' then
        return 'in'
    else
        return 'out'
    end
end

local function populateEvent(event)
    local type = event.event
    local description = event.timestamp:sub(12, -2)..","..type
    if type == 'auth' then
        local fingerprint = keys.fingerprint(event.key)
        event.fingerprint = fingerprint
        description = description..","..fingerprint
    elseif type == 'wormhole' then
        local direction = minimizeDirection(event.direction)
        description = description..","..direction..","..event.address
    elseif type == 'travel' then
        local direction = minimizeDirection(event.direction)
        description = description..","..direction..","..event.name
    end
    return { event=event, description=description }
end

local function populateEvents(events)
    local result = {}
    for _, event in ipairs(events) do
        local record = populateEvent(event)
        table.insert(result, record)
    end
    return result
end

local function fetchAuditEvents(direction, new, pageNumber)
    if pageNumber == 1 and new > 0 then
        new = 0
        newAuditEventsProperty:set(0)
    end
    local list = getAuditListElement()
    local pageSize = list:getHeight()
    local skip = new + (pageNumber - 1) * pageSize
    local records = populateEvents(client[direction](skip, pageSize))
    list:clear()
    for _, record in ipairs(records) do
        list:addItem(record.description, nil, nil, record.event)
    end
end

job.livedata.subscribe(shouldFetchAuditProperty, function(value)
    if value then
        initializedProperty:wait_until(function(value)
            return value
        end)
        fetchAuditEvents(auditDirectionProperty.value, newAuditEventsProperty.value, auditPageNumberProperty.value)
        shouldFetchAuditProperty:set(false)
    end
end)

job.livedata.subscribe(auditDirectionProperty, function()
    newAuditEventsProperty:set(0)
    auditPageNumberProperty:set(1)
    shouldFetchAuditProperty:set(true)
end)

job.livedata.subscribe(auditPageNumberProperty, function(pageNumber)
    shouldFetchAuditProperty:set(true)
end)

local function updateIris(iris)
    if iris then
        irisElement:setText(iris)
    else
        irisElement:setText("none")
    end
end

local function updateIrisDurability(current, max)
    irisDurabilityBarElement:setProgress(max == 0 and 0 or current/max * 100)
    irisDurabilityElement:setText(string.format("%d/%d", current, max))
end

job.async(function()
    local state = job.retry(5, client.getState)
    local hostKey = dom { 'root', 'main', 'keys', 'hostKey' }
    hostKey:setText(keys.fingerprint(state.settings.key))
    for _, keyinfo in ipairs(state.keyring) do
        keysList:addItem(keys.fingerprint(keyinfo.key), nil, nil, keyinfo)
    end
    setEnergyTargetText(state.settings.energyTarget)
    setButtonCheckbox(autoIrisElement, state.settings.autoIris)
    setButtonCheckbox(enableAuditElement, state.settings.enableAudit)
    updateIris(state.settings.iris)
    updateIrisDurability(state.settings.irisDurability, state.settings.irisMaxDurability)
    local advanced = state.advanced
    if advanced then
        networkIdElement:setText(tostring(advanced.network.id))
        setButtonCheckbox(isNetRestrictedElement, advanced.network.isRestricted)
        local filter = advanced.filter
        for _, address in ipairs(filter.allowlist) do
            addFilterItem(allowlistElement, address)
        end
        for _, address in ipairs(filter.denylist) do
            addFilterItem(denylistElement, address)
        end
        updateFilterModeElement(filter.mode)
    else
        dom { 'root', 'main', 'settings', 'advanced' }:hide()
        dom { 'root', 'main', 'selector' }:removeItem(4)
    end
    dom { 'root', 'main' }:show()
    initializedProperty:set(true)
end)

local function findKey(key)
    for i, item in ipairs(keysList:getAll()) do
        if item.args[1].key == key then
            return i, item
        end
    end
    return nil
end

local function addressEquals(a, b)
    if #a ~= #b then
        return false
    end
    for i=1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

rpc.subscribe_network(modem, SECURITY_EVENT, function(event)
    local t = event.type
    if t == 'register' then
        local key = event.key
        local i = findKey(key)
        if not i then
            keysList:addItem(keys.fingerprint(key), nil, colors.yellow, { key=key })
        end
    elseif t == 'allow' then
        local key = event.key
        local i = findKey(key)
        if i then
            keysList:removeItem(i)
        end
        keysList:addItem(keys.fingerprint(key), nil, nil, { key=key, name=event.name })
    elseif t == 'deny' then
        local key = event.key
        local i = findKey(key)
        if i then
            keysList:removeItem(i)
        end
    elseif t == 'filter' then
        local action = event.action
        local listType = event.list
        local list
        if listType == 'allow' then
            list = allowlistElement
        elseif listType == 'deny' then
            list = denylistElement
        else
            return
        end
        if action == 'add' then
            addFilterItem(list, event.address)
        elseif action == 'del' then
            local address = event.address
            for i, item in ipairs(list.getAll()) do
                if addressEquals(item.args[1], address) then
                    list:removeItem(i)
                    break
                end
            end
        end
    elseif t == 'setting' then
        local setting = event.setting
        local value = event.value
        if setting == 'filter_mode' then
            updateFilterModeElement(value)
        elseif setting == 'energy_target' then
            setEnergyTargetText(value)
        elseif setting == 'network' then
            networkIdElement:setText(tostring(value))
        elseif setting == 'is_network_restricted' then
            setButtonCheckbox(isNetRestrictedElement, value)
        elseif setting == 'auto_iris' then
            setButtonCheckbox(autoIrisElement, value)
        elseif setting == 'enable_audit' then
            setButtonCheckbox(enableAuditElement, value)
        elseif setting == 'iris' then
            updateIris(value.iris)
            updateIrisDurability(value.durability or 0, value.maxDurability or 0)
        end
    elseif t == 'audit' then
        if auditPageNumberProperty.value == 1 then
            local record = populateEvent(event.record)
            local list = getAuditListElement()
            local items = list:getAll()
            items[#items] = nil
            list:clear()
            list:addItem(record.description, nil, nil, record.event)
            for _, item in ipairs(items) do
                list:addItem(item.text, nil, nil, item.args[1])
            end
        else
            newAuditEventsProperty:set(newAuditEventsProperty.value + 1)
        end
    end
end)

basalt.autoUpdate()

end)
