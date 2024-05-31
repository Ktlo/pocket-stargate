local concurrent = {}

local notify_methods = {}

local notifyConsumerIdCounter = 1

function notify_methods:wait()
    local consumerId = notifyConsumerIdCounter
    notifyConsumerIdCounter = notifyConsumerIdCounter + 1
    table.insert(self.consumers, consumerId)
    local notifyId, receivedConsumerId
    repeat
        _, notifyId, receivedConsumerId = os.pullEvent("notify_wake")
    until notifyId == self.id and receivedConsumerId == consumerId
end

function notify_methods:wake()
    if #self.consumers > 0 then
        local consumer = table.remove(self.consumers, 1)
        os.queueEvent("notify_wake", self.id, consumer)
        return true
    else
        return false
    end
end

local notify_meta = {
    __index = notify_methods;
}

local notifyIdCounter = 1

function concurrent.notify()
    local notifyId = notifyIdCounter
    notifyIdCounter = notifyIdCounter + 1
    local notify = {
        id = notifyId;
        consumers = {};
    }
    return setmetatable(notify, notify_meta)
end

--------------------------------------------

local mutex_methods = {}

function mutex_methods:try_lock()
    if self.locked then
        return false
    else
        self.locked = true
        return true
    end
end

function mutex_methods:unlock()
    if not self.locked then
        error("mutex not locked", 1)
    end
    if not self.notify:wake() then
        self.locked = false
    end
end

function mutex_methods:lock()
    if self:try_lock() then
        return
    end
    self.notify:wait()
end

function mutex_methods:with_lock(action)
    self:lock()
    local result = { pcall(action) }
    self:unlock()
    if result[1] then
        return table.unpack(result, 2)
    else
        error(result[2])
    end
end

function mutex_methods:wrap(action)
    return function(...)
        local args = {...}
        return self:with_lock(function()
            return action(table.unpack(args))
        end)
    end
end

local mutex_meta = {
    __index = mutex_methods;
}

function concurrent.mutex()
    local mutex = {
        locked = false;
        notify = concurrent.notify();
    }
    return setmetatable(mutex, mutex_meta)
end;

----------------------------------------------------

local channel_methods = {}

function channel_methods:send(obj)
    table.insert(self.queue, obj)
    self.notify:wake()
end

function channel_methods:try_recv()
    if #self.queue > 0 then
        return true, table.remove(self.queue, 1)
    else
        return false
    end
end

function channel_methods:recv()
    local removed, item = self:try_recv()
    if removed then
        return item
    else
        self.notify:wait()
        return table.remove(self.queue, 1)
    end
end

local channel_meta = {
    __index = channel_methods;
}

function concurrent.channel()
    local channel = {
        queue = {};
        notify = concurrent.notify();
    }
    return setmetatable(channel, channel_meta)
end

return concurrent
