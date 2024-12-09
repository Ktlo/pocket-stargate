local os_pullEventRaw, os_startTimer, os_cancelTimer = os.pullEventRaw, os.startTimer, os.cancelTimer
local table_unpack, table_pack, table_remove, table_insert = table.unpack, table.pack, table.remove, table.insert
local next, setmetatable, select, error = next, setmetatable, select, error

----------------------------------------------------

local concurrent = {}

local function wait_pattern_timeout(object, timeout)
    local selector = object.selector
    local immediate = { selector.immediate(object) }
    if immediate[1] then
        return true, table_unpack(immediate, 2)
    end
    local context = selector.enter(object)
    local timer
    if timeout then
        timer = os_startTimer(timeout)
    else
        timer = nil
    end
    repeat
        local event = { os_pullEventRaw() }
        local event_name = event[1]
        if event_name == 'terminate' then
            selector.leave(object, context, false)
            if timer then
                os_cancelTimer(timer)
            end
            error("Terminated", 0)
        elseif event_name == 'timer' and timer == event[2] then
            selector.leave(object, context, false)
            return false
        end
    until selector.condition(object, context, event)
    if timer then
        os_cancelTimer(timer)
    end
    return true, selector.leave(object, context, true)
end

local function wait_pattern(object)
    return select(2, wait_pattern_timeout(object, nil))
end

concurrent.wait = wait_pattern

concurrent.wait_timeout = wait_pattern_timeout

local function select_timeout(timeout, ...)
    local objects = { ... }
    local selectors = {}
    local contexts = {}
    local n = #objects
    for i=1, n do
        local object = objects[i]
        local immediate = { object.selector.immediate(object) }
        if immediate[1] then
            return table_unpack(immediate, 2)
        end
    end
    for i=1, n do
        local object = objects[i]
        local selector = object.selector
        selectors[i] = selector
        contexts[i] = assert(selector.enter(object), "no context")
    end
    local timer
    if timeout then
        timer = os_startTimer(timeout)
    else
        timer = nil
    end
    local selected = nil
    repeat
        local event = table_pack(os_pullEventRaw())
        local event_name = event[1]
        if event_name == 'terminate' then
            for i=1, n do
                local object = objects[i]
                local selector = selectors[i]
                local context = contexts[i]
                selector.leave(object, context, false)
            end
            if timer then
                os_cancelTimer(timer)
            end
            error("Terminated", 0)
        elseif event_name == 'timer' and timer == event[2] then
            for i=1, n do
                local object = objects[i]
                local selector = selectors[i]
                local context = contexts[i]
                selector.leave(object, context, false)
            end
            return nil
        end
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
    local result
    for i=1, n do
        local object = objects[i]
        local selector = selectors[i]
        local context = contexts[i]
        if i == selected then
            result = table_pack(selector.leave(object, context, true))
        else
            selector.leave(object, context, false)
        end
    end
    if timer then
        os_cancelTimer(timer)
    end
    return objects[selected], table_unpack(result)
end

concurrent.select_timeout = select_timeout

function concurrent.select(...)
    return select_timeout(nil, ...)
end

--------------------------------------------

local notify_methods = {}

local notifyConsumerIdCounter = 1

notify_methods.selector = {}

function notify_methods.immediate(self)
    return false
end

function notify_methods.selector.enter(self)
    local consumerId = notifyConsumerIdCounter
    notifyConsumerIdCounter = notifyConsumerIdCounter + 1
    self.consumers[consumerId] = true
    return consumerId
end

function notify_methods.selector.condition(self, consumerId, event)
    local eventName, notifyId, receivedConsumerId = table.unpack(event)
    return eventName == 'notify_wake' and notifyId == self.id and (receivedConsumerId == consumerId or not receivedConsumerId)
end

function notify_methods.selector.leave(self, consumerId, selected)
    if not selected then
        self.consumers[consumerId] = nil
    end
end

notify_methods.wait = wait_pattern

function notify_methods:wake()
    local consumer = next(self.consumers)
    self.consumers[consumer] = nil
    if consumer then
        os.queueEvent("notify_wake", self.id, consumer)
        return true
    else
        return false
    end
end

function notify_methods:wake_all()
    if next(self.consumers) then
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

local function with_notify_selector_enter(self)
    local notify = self.notify
    return notify.selector.enter(notify)
end

local function with_notify_selector_condition(self, notify_context, event)
    local notify = self.notify
    return notify.selector.condition(notify, notify_context, event)
end

local function with_notify_selector_leave(self, notify_context, selected)
    local notify = self.notify
    notify.selector.leave(notify, notify_context, selected)
end

--------------------------------------------

local mutex_methods = {}

local function mutex_methods_try_lock(self)
    if self.locked then
        return false
    else
        self.locked = true
        return true
    end
end

mutex_methods.selector = {}
mutex_methods.selector.immediate = mutex_methods_try_lock
mutex_methods.selector.enter = with_notify_selector_enter
mutex_methods.selector.condition = with_notify_selector_condition
function mutex_methods.selector.leave(self, context, selected)
    if not selected and not self.notify[context] then
        -- not selected by this select and was chosen by previous unlock call
        -- should unlock is for someone else ortherwise will be locked forever
        self:unlock()
    end
    with_notify_selector_leave(self, context, selected)
end

mutex_methods.try_lock = mutex_methods_try_lock

function mutex_methods:unlock()
    if not self.locked then
        error("mutex not locked", 2)
    end
    if not self.notify:wake() then
        self.locked = false
    end
end

mutex_methods.lock = wait_pattern

function mutex_methods:with_lock(action)
    self:lock()
    local result = { pcall(action) }
    self:unlock()
    if result[1] then
        return table_unpack(result, 2)
    else
        error(result[2], 0)
    end
end

function mutex_methods:wrap(action)
    return function(...)
        local args = {...}
        return self:with_lock(function()
            return action(table_unpack(args))
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

local function channel_methods_try_recv(self)
    if #self.queue > 0 then
        return true, table_remove(self.queue, 1)
    else
        return false
    end
end

channel_methods.selector = {}

channel_methods.selector.immediate = channel_methods_try_recv
channel_methods.selector.enter = with_notify_selector_enter
channel_methods.selector.condition = with_notify_selector_condition

function channel_methods.selector.leave(self, notify_context, selected)
    if not selected and not self.notify[notify_context] then
        self.notify:wake()
    end
    with_notify_selector_leave(self, notify_context, selected)
    if selected then
        return table_remove(self.queue, 1)
    end
end

function channel_methods:send(obj)
    table_insert(self.queue, obj)
    self.notify:wake()
end

channel_methods.try_recv = channel_methods_try_recv

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
    if self.status == 'fail' then
        return false, self.error
    else
        return true, table_unpack(self.value)
    end
end

local function future_methods_try_wait(self)
    if self.status ~= 'idle' then
        return true, future_extract_result(self)
    else
        return false
    end
end

future_methods.selector = {}

future_methods.selector.immediate = future_methods_try_wait
future_methods.selector.enter = with_notify_selector_enter
future_methods.selector.condition = with_notify_selector_condition

function future_methods.selector.leave(self, notify_context, selected)
    with_notify_selector_leave(self, notify_context, selected)
    if selected then
        return future_extract_result(self)
    end
end

future_methods.wait = wait_pattern

function future_methods:get()
    local result = { self:wait() }
    if result[1] then
        return table_unpack(result, 2)
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
    self.value = table_pack(...)
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

property_methods.selector = {}

function property_methods.selector.immediate(self)
    return false
end

function property_methods.selector.enter(self)
    return { self.value, with_notify_selector_enter(self) }
end

function property_methods.selector.condition(self, context, event)
    local old_value, notify_context = context[1], context[2]
    local notify = self.notify
    return notify.selector.condition(notify, notify_context, event) and old_value ~= self.value
end

function property_methods.selector.leave(self, context, selected)
    local notify_context = context[2]
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
        local value = wait_pattern(self)
        collector(value)
        while self.value ~= value do
            -- cases when collector changes itself
            value = self.value
            collector(value)
        end
    end
end

function property_methods:wait_until(condition)
    local value = self.value
    if condition(value) then
        return value
    end
    while true do
        value = wait_pattern(self)
        if condition(value) then
            return value
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
