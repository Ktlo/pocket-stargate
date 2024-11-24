local CHANNEL = 75
local COLUMNS = 2

--------------------------------

local concurrent = require 'concurrent'
local rpc = require 'rpc'
local job = require 'job'
local shared = require 'shared'

--------------------------------

local monitor = assert(peripheral.find "monitor", "no monitor found")
local modem = assert(peripheral.find("modem", function(device)
    return not peripheral.hasType(device, "peripheral_hub")
end), "no modem found")
local meBridge = assert(peripheral.find "meBridge")
local spatial = assert(peripheral.find "ae2:spatial_io_port")

--------------------------------

local MY_NAME = assert((...), "portal name not provided")
COLUMNS = tonumber(select(2, ...) or COLUMNS)

--------------------------------

local portals = {}
local availablePortals = {}
local meLockedProperty = concurrent.property(false)

local cells = {}
local availableCells = {}

local function reloadCells()
    local newCells = meBridge.listItems()
    if newCells then
        for _, cell in ipairs(newCells) do
            if cell.name:sub(1, 24) == "ae2:spatial_storage_cell" then
                local fingerprint = cell.fingerprint
                if not cells[fingerprint] then
                    print('new cell', fingerprint)
                    cells[fingerprint] = true
                    availableCells[fingerprint] = true
                end
            end
        end
    end
end

reloadCells()

--------------------------------

local sides = {'top', 'bottom', 'right', 'left', 'front', 'back'}

local currentRedstoneOutput = 0

local function syncRedstone()
    for _, side in ipairs(sides) do
        redstone.setBundledOutput(side, currentRedstoneOutput)
    end
end

local function setSignal(color, value)
    if value then
        currentRedstoneOutput = colors.combine(currentRedstoneOutput, color)
    else
        currentRedstoneOutput = colors.subtract(currentRedstoneOutput, color)
    end
    syncRedstone()
end

syncRedstone()

monitor.setTextScale(0.5)

local function determineColor(flipped, active)
    if active then
        if flipped then
            return colors.green
        else
            return colors.lime
        end
    else
        if flipped then
            return colors.red
        else
            return colors.pink
        end
    end
end

local buttons = {}

local redrawProperty = concurrent.property(false)

local function redraw()
    redrawProperty:set(true)
end

--------------------------------

local function broadcast(message)
    rpc.broadcast_network(modem, CHANNEL, message)
    --print("TELL", textutils.serialise(message, {compact=true}))
end

shared.on_event(function(event)
    broadcast {
        type = 'shared';
        payload = event;
    }
end)

local declareBucket = shared.bucket('declare')
function declareBucket:on_create(portal)
    if portal == MY_NAME then
        return
    end
    portals[portal] = true
    availablePortals[portal] = true
    redraw()
end
function declareBucket:on_destroy(portal)
    if portal == MY_NAME then
        return
    end
    portals[portal] = nil
    availablePortals[portal] = nil
    redraw()
end

local portalBucket = shared.bucket('portal')
function portalBucket:on_create(portal)
    if portal == MY_NAME then
        meLockedProperty:set(true)
        return
    end
    availablePortals[portal] = nil
    redraw()
end
function portalBucket:on_destroy(portal)
    if portal == MY_NAME then
        meLockedProperty:set(false)
    else
        if portals[portal] then
            availablePortals[portal] = true
        end
    end
    redraw()
end

local cellBucket = shared.bucket('cell')
function cellBucket:on_create(cell)
    availableCells[cell] = nil
end
function cellBucket:on_destroy(cell)
    availableCells[cell] = true
end

local server = {}

function server.exchange(cell)
    local exported = assert(meBridge.exportItemToPeripheral({fingerprint=cell}, peripheral.getName(spatial)))
    assert(exported == 1, 'cell not exported')
    setSignal(colors.purple, true)
    while not spatial.list()[2] do sleep() end
    setSignal(colors.purple, false)
    local imported = assert(meBridge.importItemFromPeripheral({}, peripheral.getName(spatial)))
    assert(imported == 1, 'cell not imported')
end

--------------------------------

job.run(function()

rpc.subscribe_network(modem, CHANNEL, function(event)
    local type = event.type
    if type == 'shared' then
        shared.push(event.payload)
    end
end)

shared.initialize()
print('gathered state')

local thisPortal = assert(declareBucket:try_acquire(MY_NAME))

print('declared this portal')

job.async(function()
    while true do
        sleep(2)
        thisPortal:revive()
    end
end):finnalize(function()
    thisPortal:release()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
end)

rpc.server_network(rpc.simple_commands(server), modem, CHANNEL, MY_NAME)

job.livedata.subscribe(meLockedProperty, function(locked)
    setSignal(colors.red, locked)
end)

job.async(function()
    while true do
        sleep(1)
        shared.expire()
    end
end)

local function teleport(destination)
    local source = portalBucket:try_acquire(MY_NAME)
    if not source then
        return
    end
    local target = portalBucket:try_acquire(destination)
    if not target then
        source:release()
        return
    end
    sleep(0.5)
    local cellName, cell
    while true do
        cellName = next(availableCells)
        if not cellName then
            print("no available cell left")
            source:release()
            target:release()
            return
        end
        cell = cellBucket:try_acquire(cellName)
        if cell then
            break
        end
    end
    assert(cell)
    print("teleport to", destination)
    server.exchange(cellName)
    local client = rpc.client_network(modem, CHANNEL, 3, destination)
    local ok, err = pcall(client.exchange, cellName)
    if not ok then
        print("failed to materialize", err)
    end
    target:release()
    server.exchange(cellName)
    source:release()
    cell:release()
end

job.async(function()
    local monitorName = peripheral.getName(monitor)
    while true do
        local _, side, x, y = os.pullEvent('monitor_touch')
        local width, height = monitor.getSize()
        local buttonWidth = math.floor((width - 2) / COLUMNS)
        if side == monitorName and x > 1 and y > 1 and x < buttonWidth*COLUMNS + 1 then
            local index = (y - 2)*COLUMNS + math.floor((x - 1)/buttonWidth) + 1
            local portal = buttons[index]
            if portal and availablePortals[portal] then
                teleport(portal)
            end
        end
    end
end)

job.livedata.subscribe(redrawProperty, function(doRedraw)
    if doRedraw then
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.white)
        monitor.clear()
        local width, height = monitor.getSize()
        local buttonWidth = math.floor((width - 2) / COLUMNS)
        if not meLockedProperty.value then
            monitor.setCursorPos((width - #MY_NAME)/2, 1)
            monitor.write(MY_NAME)
            local flipColor = false
            local columnOffset = 0
            local rowOffset = 0
            buttons = {}
            for portal in pairs(portals) do
                table.insert(buttons, portal)
                monitor.setCursorPos(2 + columnOffset*buttonWidth, 2 + rowOffset)
                local bg = determineColor(flipColor, availablePortals[portal])
                local fg = colors.white
                local space = buttonWidth - #portal
                local name = portal
                if space < 0 then
                    space = 0
                    name = string.sub(portal, 1, buttonWidth)
                end
                local beginSpace = math.floor(space/2)
                local endSpace = beginSpace + space%2
                local text = string.rep(" ", beginSpace)..name..string.rep(" ", endSpace)
                monitor.blit(text, colors.toBlit(fg):rep(buttonWidth), colors.toBlit(bg):rep(buttonWidth))
                columnOffset = columnOffset + 1
                flipColor = not flipColor
                if columnOffset == COLUMNS then
                    columnOffset = 0
                    rowOffset = rowOffset + 1
                end
            end
        end
        redrawProperty:set(false)
    end
end)

job.async(function()
    while true do
        os.sleep(10)
        reloadCells()
    end
end)

print("started")

end)
