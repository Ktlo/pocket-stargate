local function removeFromList(list, element)
    for i=1, #list do
        if element == list[i] then
            table.remove(list, i)
            return true
        end
    end
    return false
end

local concurrent = {}

local immediately = { 'immediate' }

local function wait_pattern(object)
    local selector = object._selector
    local context = selector.enter(object)
    if not selector.condition(object, context, immediately) then
        repeat
            local event = table.pack(os.pullEvent())
        until selector.condition(object, context, event)
    end
    return selector.leave(object, context, true)
end

concurrent.wait = wait_pattern

function concurrent.select(...)
    local objects = { ... }
    local selectors = {}
    local contexts = {}
    for i, object in ipairs(objects) do
        local selector = object._selector
        selectors[i] = selector
        contexts[i] = selector.enter(object)
    end
    local n = #objects
    local selected = nil
    for i=1, n do
        local object = objects[i]
        local selector = selectors[i]
        local context = contexts[i]
        if selector.condition(object, context, immediately) then
            selected = i
            break
        end
    end
    if not selected then
        repeat
            local event = table.pack(os.pullEvent())
            for i=1, n do
                local object = objects[i]
                local selector = selectors[i]
                local context = contexts[i]
                if selector.condition(object, context, event) then
                    selected = i
                    break
                end
            end
        until selected
    end
    local result
    for i=1, n do
        local object = objects[i]
        local selector = selectors[i]
        local context = contexts[i]
        if i == selected then
            result = table.pack(selector.leave(object, context, true))
        else
            selector.leave(object, context, false)
        end
    end
    return objects[selected], table.unpack(result)
end

--------------------------------------------

local notify_methods = {}

local notifyConsumerIdCounter = 1

notify_methods._selector = {}

function notify_methods._selector.enter(self)
    local consumerId = notifyConsumerIdCounter
    notifyConsumerIdCounter = notifyConsumerIdCounter + 1
    table.insert(self.consumers, consumerId)
    return consumerId
end

function notify_methods._selector.condition(self, consumerId, event)
    local eventName, notifyId, receivedConsumerId = table.unpack(event)
    return eventName == 'notify_wake' and notifyId == self.id and (receivedConsumerId == consumerId or not receivedConsumerId)
end

function notify_methods._selector.leave(self, consumerId, selected)
    if not selected then
        removeFromList(self.consumers, consumerId)
        -- assert deleted
    end
end

notify_methods.wait = wait_pattern

function notify_methods:wake()
    if #self.consumers > 0 then
        local consumer = table.remove(self.consumers, 1)
        os.queueEvent("notify_wake", self.id, consumer)
        return true
    else
        return false
    end
end

function notify_methods:wake_all()
    if #self.consumers > 0 then
        self.consumers = {}
        os.queueEvent("notify_wake", self.id)
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

local function with_notify_selector_enter(condition, self)
    if condition then
        return { true }
    else
        local notify = self.notify
        return { false, notify._selector.enter(notify) }
    end
end

local function with_notify_selector_condition(self, context, event)
    local immediate, notify_context = table.unpack(context)
    if immediate then
        return true
    end
    local notify = self.notify
    return notify._selector.condition(notify, notify_context, event)
end

local function with_notify_selector_leave(self, notify_context, selected)
    local notify = self.notify
    notify._selector.leave(notify, notify_context, selected)
end

--------------------------------------------

local mutex_methods = {}

mutex_methods._selector = {}

function mutex_methods._selector.enter(self)
    return with_notify_selector_enter(self:try_lock(), self)
end

mutex_methods._selector.condition = with_notify_selector_condition

function mutex_methods._selector.leave(self, context, selected)
    local immediate, notify_context = table.unpack(context)
    if immediate and selected then
        return
    end
    if immediate then
        self:unlock()
        return
    end
    with_notify_selector_leave(self, notify_context, selected)
end

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

mutex_methods.lock = wait_pattern

function mutex_methods:with_lock(action)
    self:lock()
    local result = table.pack(pcall(action))
    self:unlock()
    if result[1] then
        return table.unpack(result, 2)
    else
        error(result[2], 0)
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

channel_methods._selector = {}

function channel_methods._selector.enter(self)
    return with_notify_selector_enter(#self.queue > 0, self)
end

channel_methods._selector.condition = with_notify_selector_condition

function channel_methods._selector.leave(self, context, selected)
    local immediate, notify_context = table.unpack(context)
    if immediate and selected then
        return table.remove(self.queue, 1)
    end
    if immediate then
        return
    end
    with_notify_selector_leave(self, notify_context, selected)
    if selected then
        return table.remove(self.queue, 1)
    end
end

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

channel_methods.recv = wait_pattern

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

----------------------------------------------------

local future_methods = {}

local function future_extract_result(self)
    if self.error then
        return false, self.error
    else
        return true, table.unpack(self.value)
    end
end

future_methods._selector = {}

function future_methods._selector.enter(self)
    return with_notify_selector_enter(self.status ~= 'idle', self)
end

future_methods._selector.condition = with_notify_selector_condition

function future_methods._selector.leave(self, context, selected)
    local immediate, notify_context = table.unpack(context)
    if immediate and selected then
        return future_extract_result(self)
    end
    if immediate then
        return
    end
    with_notify_selector_leave(self, notify_context, selected)
    if selected then
        return future_extract_result(self)
    end
end

future_methods.wait = wait_pattern

function future_methods:get()
    local result = table.pack(self:wait())
    if result[1] then
        return table.unpack(result, 2)
    else
        error(result[2], 2)
    end
end

local function checkFutureIdle(self)
    if self.status ~= 'idle' then
        error("the value for future is already submitted", 3)
    end
end

function future_methods:submit(...)
    checkFutureIdle(self)
    self.status = 'success'
    self.value = table.pack(...)
    self.notify:wake_all()
end

function future_methods:failure(err)
    checkFutureIdle(self)
    self.status = 'fail'
    self.error = err
    self.notify:wake_all()
end

function future_methods:from(future)
    checkFutureIdle(self)
    self.status = future.status
    self.error = future.error
    self.value = future.value
    self.notify:wake_all()
end

local future_meta = {
    __index = future_methods;
}

function concurrent.future()
    local future = {
        status = 'idle';
        notify = concurrent.notify();
    }
    return setmetatable(future, future_meta)
end

----------------------------------------------------

local property_methods = {}

property_methods._selector = {}

function property_methods._selector.enter(self)
    local notify = self.notify
    return { self.value, notify._selector.enter(notify) }
end

function property_methods._selector.condition(self, context, event)
    local old_value, notify_context = table.unpack(context)
    local notify = self.notify
    return notify._selector.condition(notify, notify_context, event)
end

function property_methods._selector.leave(self, context, selected)
    local _, notify_context = table.unpack(context)
    with_notify_selector_leave(self, notify_context, selected)
    if selected then
        return self.value
    end
end

function property_methods:set(value)
    if self.value ~= value then
        self.value = value
        self.notify:wake_all()
    end
end

function property_methods:collect(collector)
    collector(self.value)
    while true do
        -- self.notify:wait()
        -- collector(self.value)
        collector(wait_pattern(self))
    end
end

function property_methods:wait_until(condition)
    if condition(self.value) then
        return
    end
    while true do
        if condition(wait_pattern(self)) then
            return
        end
    end
end

local property_meta = {
    __index = property_methods;
}

function concurrent.property(init)
    local property = {
        value = init;
        notify = concurrent.notify();
    }
    return setmetatable(property, property_meta)
end

----------------------------------------------------

return concurrent
