local theme = {
    FrameBG = colors.lightGray,
    FrameFG = colors.black,
    SelectionText = colors.white,
    InputText = colors.white,
}

-------------------------

local basalt = require 'basalt'
local address = require 'psg.address'
local resources = require 'ktlo.resources'
local concurrent = require 'ktlo.concurrent'
local job = require 'ktlo.job'
local modal = require 'psg.modal'
local addressbook = require 'psg.addressbook'

local version = VERSION or "dev"

local function dom(path)
    local current = basalt.getActiveFrame()
    for _, segment in ipairs(path) do
        current = current:getObject(segment)
    end
    return current
end

local function selectFrom(bar, ...)
    local index = bar:getItemIndex()
    for i=1, select('#', ...) do
        local tab = select(i, ...)
        if tab then
            if i == index then
                tab:show()
            else
                tab:hide()
            end
        end
    end
    local tab = select(index, ...)
    return tab
end

basalt.setVariable("selectFrame", function(bar)
    selectFrom(
        bar,
        dom { 'root', 'main', 'edit' },
        dom { 'root', 'main', 'file' }
    )
end)

local positionList, identityList, activeList, addressbookLocationInput

basalt.setVariable("selectList", function(bar)
    activeList = selectFrom(
        bar,
        positionList,
        identityList
    )
end)

local function scroll(list, increment)
    local offset = list:getOffset()
    if increment < 0 and offset <= 0 then
        return
    end
    if increment > 0 and offset > #(list:getAll()) - list:getHeight() then
        return
    end
    list:setOffset(offset + increment)
end

local function scrollParentList(button, increment)
    local list = button:getParent():getObject("list")
    scroll(list, increment)
end

local modalMutex = concurrent.mutex()
local modalMutexPosition = concurrent.mutex()

local function getInputOrNil(input)
    local value = input:getValue()
    if value == "" then
        return nil
    else
        return value
    end
end

local function addressForm(mutex, record, kind)
    record = record or {}
    return modal.open(function(frame, future)
        local width = math.min(30, frame:getParent():getSize() - 2)
        frame:setSize(width, 12)
        frame:setPosition("(parent.w - self.w)/2 + 1", "(parent.h - self.h)/2")
        frame:addLayoutFromString(resources.load "record.xml")
        local window = frame:getObject("window")
        local nameInput = window:getObject("name")
        nameInput:setValue(record.name or "")
        local addressInput = window:getObject("address")
        addressInput:setValue(record.address and tostring(record.address) or "")

        window:getObject("submit"):onClick(function()
            local ok, value = pcall(address.parse, addressInput:getValue())
            if not ok then
                job.async(function()
                    mutex:with_lock(modal.alert, "Invalid address:\n"..value, nil, "OK")
                end)
                return
            end
            if value.kind ~= kind then
                job.async(function()
                    mutex:with_lock(
                        modal.alert,
                        "Invalid address:\nexpected "..kind.." ("..address.sizeof(kind).." symbols), but got "
                        ..value.kind.." ("..value.n.." symbols)", nil, "OK"
                    )
                end)
                return
            end
            future:complete {
                name = nameInput:getValue();
                address = value;
            }
        end)
        window:getObject("cancel"):onClick(function()
            future:complete(nil)
        end)
    end)
end

local function positionForm(position)
    position = position or { interstellar = {} }
    return modalMutex:with_lock(modal.open, function(frame, future)
        local recordMutex = concurrent.mutex()
        frame:addLayoutFromString(resources.load "position.xml")
        local window = frame:getObject("window")
        local nameInput = window:getObject("name")
        nameInput:setValue(position.name or "")
        local keyInput = window:getObject("key")
        keyInput:setValue(position.key or "")
        local extragalacticInput = window:getObject("extragalactic")
        extragalacticInput:setValue(position.extragalactic and tostring(position.extragalactic) or "")
        local interstellarList = window:getObject("list")
        local function interstellarItem(galaxy, addr)
            return galaxy.." "..tostring(addr), nil, nil, { galaxy = galaxy, address = addr }
        end
        local function addInterstellar(galaxy, addr)
            interstellarList:addItem(interstellarItem(galaxy, addr))
        end
        for galaxy, addr in pairs(position.interstellar) do
            addInterstellar(galaxy, addr)
        end
        window:getObject("add"):onClick(function()
            job.async(function()
                local record = modalMutexPosition:with_lock(addressForm, recordMutex, nil, 'interstellar')
                if record then
                    addInterstellar(record.name, record.address)
                end
            end)
        end)
        window:getObject("edit"):onClick(function()
            local index = interstellarList:getItemIndex()
            if not index or index <= 0 then
                return
            end
            local item = interstellarList:getItem(index)
            local record = item.args[1]
            job.async(function()
                local newRecord = modalMutexPosition:with_lock(
                    addressForm, recordMutex, {name = record.galaxy, address = record.address}, 'interstellar'
                )
                if newRecord then
                    interstellarList:editItem(index, interstellarItem(newRecord.name, newRecord.address))
                end
            end)
        end)
        window:getObject("delete"):onClick(function()
            local index = interstellarList:getItemIndex()
            if not index or index <= 0 then
                return
            end
            job.async(function()
                local isSure = modalMutexPosition:with_lock(modal.alert, "Are you sure?", "Yes", "No")
                if isSure then
                    interstellarList:removeItem(index)
                end
            end)
        end)

        window:getObject("submit"):onClick(function()
            local extragalactic = getInputOrNil(extragalacticInput)
            if extragalactic then
                local ok, value = pcall(address.parse, extragalactic)
                if not ok then
                    job.async(function()
                        modalMutexPosition:with_lock(
                            modal.alert,
                            "Invalid extragalactic address:\n"..value, nil, "OK"
                        )
                    end)
                    return
                end
                if value.kind ~= 'extragalactic' then
                    job.async(function()
                        modalMutexPosition:with_lock(
                            modal.alert,
                            "Invalid extragalactic address:\nexpected extragalactic address (7 symbols), but got "
                            ..value.kind.." ("..value.n.." symbols)", nil, "OK"
                        )
                    end)
                    return
                end
                extragalactic = value
            end
            local interstellar = {}
            local count = interstellarList:getItemCount()
            for i=1, count do
                local item = interstellarList:getItem(i)
                local record = item.args[1]
                interstellar[record.galaxy] = record.address
            end
            future:complete {
                name = getInputOrNil(nameInput);
                key = getInputOrNil(keyInput);
                interstellar = interstellar;
                extragalactic = extragalactic;
            }
        end)
        window:getObject("cancel"):onClick(function()
            future:complete(nil)
        end)
    end)
end

basalt.setVariable("scrollUp", function(button)
    scrollParentList(button, -1)
end)

basalt.setVariable("scrollDown", function(button)
    scrollParentList(button, 1)
end)

basalt.setVariable("up", function()
    scroll(activeList, -1)
end)

basalt.setVariable("down", function()
    scroll(activeList, 1)
end)

local function listItem(record)
    return record.name or record.key or "???", nil, nil, record
end

basalt.setVariable("addRecord", function()
    job.async(function()
        local record
        if activeList == positionList then
            record = positionForm(nil)
        else
            record = modalMutex:with_lock(addressForm, modalMutexPosition, nil, 'systemwide')
        end
        if record then
            activeList:addItem(listItem(record))
        end
    end)
end)

basalt.setVariable("editRecord", function()
    local index = activeList:getItemIndex()
    if not index or index <= 0 then
        return
    end
    job.async(function()
        local record = activeList:getItem(index).args[1]
        if activeList == positionList then
            record = positionForm(record)
        else
            record = modalMutex:with_lock(addressForm, modalMutexPosition, record, 'systemwide')
        end
        if record then
            activeList:editItem(index, listItem(record))
        end
    end)
end)

basalt.setVariable("deleteRecord", function()
    local index = activeList:getItemIndex()
    if not index or index <= 0 then
        return
    end
    job.async(function()
        local isSure = modalMutex:with_lock(modal.alert, "Are you sure?", "Yes", "No")
        if isSure then
            activeList:removeItem(index)
        end
    end)
end)

local function editListItem(list, index, item)
    list:editItem(index, item.text, item.bgCol, item.fgCol, table.unpack(item.args))
end

local function swapListItems(list, a, b)
    local aItem = list:getItem(a)
    local bItem = list:getItem(b)
    editListItem(list, a, bItem)
    editListItem(list, b, aItem)
end

basalt.setVariable("moveUp", function()
    local index = activeList:getItemIndex()
    if not index or index <= 0 then
        return
    end
    if index == 1 then
        return
    end
    swapListItems(activeList, index - 1, index)
    activeList:selectItem(index - 1)
end)

basalt.setVariable("moveDown", function()
    local index = activeList:getItemIndex()
    if not index or index <= 0 then
        return
    end
    if index == activeList:getItemCount() then
        return
    end
    swapListItems(activeList, index, index + 1)
    activeList:selectItem(index + 1)
end)

local function transformList(list)
    local result = {}
    for i, item in ipairs(list:getAll()) do
        result[i] = item.args[1]
    end
    return result
end

basalt.setVariable("saveAll", function()
    job.async(function()
        local ok, err = pcall(function()
            addressbook.set_location(addressbookLocationInput:getValue())
            local addresses = {
                position = transformList(positionList);
                identity = transformList(identityList);
            }
            addressbook.save(addresses)
        end)
        if not ok then
            modalMutex:with_lock(modal.alert, "Saving failed:\n"..err, nil, "OK")
        else
            modalMutex:with_lock(modal.message, "Success", "Addressbook saved!")
        end
    end)
end)

basalt.createFrame()
    :setTheme(theme)
    :addLayoutFromString(resources.load("asn.xml"))

dom { 'root', 'main', 'file', 'version' }:setText(version)

positionList = dom { 'root', 'main', 'edit', 'position' }
identityList = dom { 'root', 'main', 'edit', 'identity' }
activeList = positionList
addressbookLocationInput = dom { 'root', 'main', 'file', 'filepath' }

do
    addressbookLocationInput:setValue(addressbook.get_location())
    local addresses = assert(addressbook.load())
    for _, record in ipairs(addresses.position) do
        positionList:addItem(listItem(record))
    end
    for _, record in ipairs(addresses.identity) do
        identityList:addItem(listItem(record))
    end
end

job.run(function()

job.async(basalt.autoUpdate)

end)
