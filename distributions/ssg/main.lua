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
local job = require 'ktlo.job'
local rpc = require 'ktlo.rpc'
local keys = require 'psg.keys'
local concurrent = require 'ktlo.concurrent'
local printer = require 'psg.printer'
local resources = require 'ktlo.resources'
local modal = require 'psg.modal'

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
            local keyInfo = keysList:getItem(i).args[1]
            client.allow(keyInfo.key, keyInfo.name)
        end
    end)
end)

basalt.setVariable("deny", function()
    job.async(function()
        local i = keysList:getItemIndex()
        if i then
            local item = keysList:getItem(i)
            local key = item.args[1].key
            client.deny(key)
        end
    end)
end)

basalt.setVariable("addAddressToFilter", function()
    local listType = selectedFilterListProperty.value
    job.async(function()
        local newAddress = modal.address()
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
        local result = modal.number(init or 0)
        if result then
            client.setEnergyTarget(result)
        end
    end)
end)

basalt.setVariable("setNetworkId", function()
    local init = tonumber(networkIdElement:getValue())
    job.async(function()
        local result = modal.number(init or 0)
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
    if i then
        local item = list:getItem(i)
        auditEventDialog(item.args[1])
    end
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
            local continue = modal.alert(err, "Continue", "Cancel")
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
            local continue = modal.alert(err, "Continue", "Cancel")
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

auditEventWindow = dom { 'root', 'event' }

if printer.exists() then
    auditEventWindow:getObject('control'):getObject('print'):show()
    dom { 'root', 'main', 'audit', 'op', 'print' }:show()
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

local function addKeyToKeylist(event, color)
    local key = event.key
    local fingerprint = keys.fingerprint(key)
    local name = event.name
    local text
    if name then
        text = name.." "..fingerprint
    else
        text = fingerprint
    end
    keysList:addItem(text, nil, color, { key=key, name=name, fingerprint=fingerprint })
end

job.async(function()
    local state = job.retry(5, client.getState)
    local versionLabel = dom { 'root', 'main', 'keys', 'version' }
    versionLabel:setText("SSG "..(VERSION or "dev").."; SGS "..(state.version or "?"))
    local hostKey = dom { 'root', 'main', 'keys', 'hostKey' }
    hostKey:setText(keys.fingerprint(state.settings.key))
    for _, keyinfo in ipairs(state.keyring) do
        addKeyToKeylist(keyinfo)
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
            addKeyToKeylist(event, colors.yellow)
        end
    elseif t == 'allow' then
        local key = event.key
        local i = findKey(key)
        if i then
            keysList:removeItem(i)
        end
        addKeyToKeylist(event)
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
