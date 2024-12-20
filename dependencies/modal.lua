local basalt = require 'basalt'
local concurrent = require 'concurrent'
local resources = require 'resources'
local job = require 'job'

local library = {}

local mutex = concurrent.mutex()

--- @param setup fun(frame, future: future)
--- @return any
local function open_modal_window(setup)
    return mutex:with_lock(function()
        local root = basalt.getActiveFrame()
        local mainFrame = root:getObject("root") or root:getObject("main")
        local future = concurrent.future()
        mainFrame:disable()
        local frame = root:addFrame()
        frame:setMovable(true)
        setup(frame, future)
        local ok, result = pcall(future.get, future)
        frame:remove()
        mainFrame:enable()
        if ok then
            return result
        else
            error(result, 0)
        end
    end)
end

library.open = open_modal_window

local function setup_frame_width(frame, width, height, layout)
    frame:setSize(width, height)
    frame:setPosition("(parent.w - self.w)/2 + 1", "(parent.h - self.h)/2")
    frame:addLayoutFromString(resources.load(layout))
    return frame:getObject("window")
end

local function setup_frame(frame, height, layout)
    local width = math.min(30, frame:getParent():getSize() - 2)
    return setup_frame_width(frame, width, height, layout)
end

--- @async
function library.alert(text, accept, cancel)
    if type(text) == 'table' then
        text = table.concat(text, '\n')
    end
    return open_modal_window(function(frame, future)
        local window = setup_frame(frame, 13, "alert.xml")
        local acceptButton = window:getObject("accept")
        acceptButton:onClick(function()
            future:complete(true)
        end)
        local cancelButton = window:getObject("cancel")
        cancelButton:onClick(function()
            future:complete(false)
        end)
        local content = window:getObject("content")
        content:setText(text)
        if accept then
            acceptButton:show()
            acceptButton:setText(accept)
        else
            acceptButton:hide()
        end
        cancelButton:setText(cancel)
    end)
end

--- @async
function library.message(title, message)
    open_modal_window(function(frame, future)
        local window = setup_frame(frame, 11, "message.xml")
        window:getObject("title"):setText(title)
        window:getObject("content"):setText(message)
        window:getObject("close"):onClick(function()
            future:complete(nil)
        end)
    end)
end

local function setup_passwd(frame, future)
    local window = setup_frame(frame, 8, "passwd.xml")
    local input = window:getObject("password")
    local done = window:getObject("done")
    local cancel = window:getObject("cancel")
    done:onClick(function()
        future:complete(input:getValue())
    end)
    cancel:onClick(function()
        future:complete(nil)
    end)
    input:setFocus()
end

--- @async
function library.passwd()
    return open_modal_window(setup_passwd)
end

local function setup_chpass(frame, future)
    local window = setup_frame(frame, 12, "chpass.xml")
    local message = window:getObject("message")
    local input = window:getObject("password")
    local confirmElement = window:getObject("confirm")
    local done = window:getObject("done")
    local cancel = window:getObject("cancel")
    done:onClick(function()
        local password = input:getValue()
        local confirm = confirmElement:getValue()
        if password ~= confirm then
            message:setText("Passwords not equal!")
            return
        end
        future:complete(password)
    end)
    cancel:onClick(function()
        future:complete(nil)
    end)
    input:onClick(function()
        message:setText("")
    end)
    confirmElement:onClick(function()
        message:setText("")
    end)
    input:setFocus()
end

--- @async
function library.chpass()
    return open_modal_window(setup_chpass)
end

--- @param init integer
--- @return integer
--- @async
function library.number(init)
    return open_modal_window(function(frame, future)
        local window = setup_frame_width(frame, 23, 16, "number.xml")
        local input = window:getObject("input")
        input:setValue(tostring(init))
        local digits = window:getObject("digits")
        for i=0, 9 do
            local digit = digits:getObject("d"..i)
            digit:onClick(function()
                input:setValue(tostring(tonumber(input:getValue()..i)))
                input:setFocus()
            end)
        end
        local control = window:getObject("control")
        control:getObject("erase"):onClick(function()
            local value = tostring(input:getValue())
            if #value ~= 0 then
                input:setValue(value:sub(1, -2))
            end
            input:setFocus()
        end)
        control:getObject("done"):onClick(function()
            local value = input:getValue()
            future:complete(tonumber(value) or 0)
        end)
        control:getObject("back"):onClick(function()
            future:complete(nil)
        end)
        input:setFocus()
    end)
end

local function setup_address(frame, future)
    local window = setup_frame_width(frame, 27, 20, "address.xml")
    local symbols = window:getObject("symbols")
    local input = window:getObject("input")
    local control = window:getObject("control")
    local done = control:getObject("done")
    done:disable()
    local address = {}
    local function update_address(newAddress)
        address = newAddress
        for i=1, 8 do
            local symbol = address[i]
            local display = symbols:getObject("s"..i)
            if symbol then
                display:setText(string.format("%02d", symbol))
            else
                display:setText("")
            end
        end
        if #address >= 6 then
            done:setBackground(colors.green)
            done:enable()
        else
            done:setBackground(colors.gray)
            done:disable()
        end
    end
    local function input_symbol(button)
        local symbol = tonumber(button:getValue())
        local length = #address
        if length < 8 then
            for i=1, length do
                if address[i] == symbol then
                    return
                end
            end
            local newAddress = { table.unpack(address) }
            newAddress[length + 1] = symbol
            update_address(newAddress)
        end
    end
    for i=1, 47 do
        input:getObject("v"..i):onClick(input_symbol)
    end
    input:getObject("erase"):onClick(function()
        local length = #address
        if length > 0 then
            local newAddress = { table.unpack(address, 1, length - 1) }
            update_address(newAddress)
        end
    end)
    done:onClick(function()
        future:complete(address)
    end)
    control:getObject("back"):onClick(function()
        future:complete(nil)
    end)
    job.async(function()
        local event = concurrent.event('paste')
        while true do
            local subject, data = concurrent.select(future, event)
            if subject == future then
                break
            end
            local newAddress = { table.unpack(address) }
            local symbols = {}
            for _, symbol in ipairs(newAddress) do
                symbols[symbol] = true
            end
            for value in data[2]:gmatch("%d+") do
                local symbol = assert(tonumber(value))
                if symbol > 0 and symbol < 48 and not symbols[symbol] then
                    symbols[symbol] = true
                    table.insert(newAddress, symbol)
                    if #newAddress >= 8 then
                        break
                    end
                end
            end
            update_address(newAddress)
        end
    end)
end

--- @return integer[]
--- @async
function library.address()
    return open_modal_window(setup_address)
end

return library
