local os, table, math = os, table, math
local os_pullEventRaw, os_startTimer, os_cancelTimer, os_epoch = os.pullEventRaw, os.startTimer, os.cancelTimer, os.epoch
local table_unpack, table_pack, table_remove, table_insert = table.unpack, table.pack, table.remove, table.insert
local math_floor = math.floor
local next, setmetatable, select, error, type, pairs = next, setmetatable, select, error, type, pairs

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

function concurrent.select(...)
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
        contexts[i] = selector.enter(object)
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
            error("Terminated", 0)
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
    return objects[selected], table_unpack(result)
end

local function return_false()
    return false
end

--------------------------------------------

local notify_methods = {}

local notifyConsumerIdCounter = 1

notify_methods.selector = {}

notify_methods.immediate = return_false

function notify_methods.selector.enter(self)
    local consumerId = notifyConsumerIdCounter
    notifyConsumerIdCounter = notifyConsumerIdCounter + 1
    self.consumers[consumerId] = true
    self.count = self.count + 1
    return consumerId
end

function notify_methods.selector.condition(self, consumerId, event)
    local eventName, notifyId, receivedConsumerId = table.unpack(event)
    return eventName == 'notify_wake' and notifyId == self.id and (receivedConsumerId == consumerId or not receivedConsumerId)
end

function notify_methods.selector.leave(self, consumerId, selected)
    if not selected then
        local consumers = self.consumers
        local not_woke = consumers[consumerId]
        if not_woke then
            consumers[consumerId] = nil
            self.count = self.count - 1
            return false
        else
            return true
        end
    end
    return false
end

notify_methods.wait = wait_pattern

function notify_methods:wake()
    local consumer = next(self.consumers)
    if consumer then
        self.consumers[consumer] = nil
        self.count = self.count - 1
        os.queueEvent("notify_wake", self.id, consumer)
        return true
    else
        return false
    end
end

function notify_methods:wake_all()
    if next(self.consumers) then
        self.consumers = {}
        local count = self.count
        self.count = 0
        os.queueEvent("notify_wake", self.id)
        return count
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
        count = 0;
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
    return notify.selector.leave(notify, notify_context, selected)
end

local function with_notify_create_selector(immediate, leave)
    return {
        immediate = immediate;
        enter = with_notify_selector_enter;
        condition = with_notify_selector_condition;
        leave = function(self, context, selected)
            local woke = with_notify_selector_leave(self, context, selected)
            return leave(self, woke, selected)
        end;
    }
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

local function mutex_methods_leave(self, woke, selected)
    if woke then
        self:unlock()
    end
end

mutex_methods.selector = with_notify_create_selector(mutex_methods_try_lock, mutex_methods_leave)

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

local function mutex_methods_with_lock(self, action)
    self:lock()
    local result = { pcall(action) }
    self:unlock()
    if result[1] then
        return table_unpack(result, 2)
    else
        error(result[2], 0)
    end
end

mutex_methods.with_lock = mutex_methods_with_lock

local function mutex_methods_wrap(self, action)
    return function(...)
        local args = {...}
        return self:with_lock(function()
            return action(table_unpack(args))
        end)
    end
end

mutex_methods.wrap = mutex_methods_wrap

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

local function channel_methods_leave(self, woke, selected)
    if woke then
        self.notify:wake()
    end
    if selected then
        return table_remove(self.queue, 1)
    end
end

channel_methods.selector = with_notify_create_selector(channel_methods_try_recv, channel_methods_leave)

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

-- local future_methods = {}

-- local function future_extract_result(self)
--     if self.status == 'fail' then
--         return false, self.error
--     else
--         return true, table_unpack(self.value)
--     end
-- end

-- local function future_methods_try_wait(self)
--     if self.status ~= 'idle' then
--         return true, future_extract_result(self)
--     else
--         return false
--     end
-- end

-- local function future_methods_leave(self, woke, selected)
--     if selected then
--         return future_extract_result(self)
--     end
-- end

-- future_methods.selector = with_notify_create_selector(future_methods_try_wait, future_methods_leave)

-- future_methods.wait = wait_pattern

-- function future_methods:get()
--     local result = { self:wait() }
--     if result[1] then
--         return table_unpack(result, 2)
--     else
--         error(result[2], 2)
--     end
-- end

-- local function checkFutureIdle(self)
--     if self.status ~= 'idle' then
--         error("the value for future is already submitted", 3)
--     end
-- end

-- function future_methods:submit(...)
--     checkFutureIdle(self)
--     self.status = 'success'
--     self.value = table_pack(...)
--     self.notify:wake_all()
-- end

-- function future_methods:failure(err)
--     checkFutureIdle(self)
--     self.status = 'fail'
--     self.error = err
--     self.notify:wake_all()
-- end

-- function future_methods:from(future)
--     checkFutureIdle(self)
--     self.status = future.status
--     self.error = future.error
--     self.value = future.value
--     self.notify:wake_all()
-- end

-- local future_meta = {
--     __index = future_methods;
-- }

-- function concurrent.future()
--     local future = {
--         status = 'idle';
--         notify = concurrent.notify();
--     }
--     return setmetatable(future, future_meta)
-- end

----------------------------------------------------

local property_methods = {}

local function property_methods_leave(self, woke, selected)
    if selected then
        return self.value
    end
end

property_methods.selector = with_notify_create_selector(return_false, property_methods_leave)

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

local function read_mutex_methods_try_lock(self)
    if self.locked then
        return false
    else
        local count = self.count
        if count == 0 then
            self.write.locked = true
        end
        self.count = count + 1
        return true
    end
end

local function read_mutex_methods_leave(self, woke, selected)
    if woke then
        self:unlock()
    end
end

local read_mutex_methods = {}

read_mutex_methods.selector = with_notify_create_selector(read_mutex_methods_try_lock, read_mutex_methods_leave)

read_mutex_methods.try_lock = read_mutex_methods_try_lock

read_mutex_methods.lock = wait_pattern

function read_mutex_methods:unlock()
    local count = self.count
    if count == 0 then
        error("mutex is not locked", 2)
    end
    self.count = count - 1
    if count == 1 then
        local write = self.write
        if write.notify:wake() then
            self.locked = true
        end
    end
end

read_mutex_methods.with_lock = mutex_methods_with_lock

read_mutex_methods.wrap = mutex_methods_wrap

local read_mutex_meta = {
    __index = read_mutex_methods;
}

local function write_mutex_methods_try_lock(self)
    if self.locked then
        return false
    else
        local read = self.read
        read.locked = true
        self.locked = true
        return true
    end
end

local function write_mutex_methods_leave(self, woke, selected)
    if woke then
        self:unlock()
    end
end

local write_mutex_methods = {}

write_mutex_methods.selector = with_notify_create_selector(write_mutex_methods_try_lock, write_mutex_methods_leave)

write_mutex_methods.try_lock = write_mutex_methods_try_lock

write_mutex_methods.lock = wait_pattern

function write_mutex_methods:unlock()
    local read = self.read
    local count = read.count
    if not self.locked or count > 0 then
        error("mutex is not locked", 2)
    end
    if self.notify:wake() then
        return
    end
    read.locked = false
    local waiters = read.notify:wake_all()
    if waiters then
        read.count = waiters
        return
    end
    self.locked = false
end

write_mutex_methods.with_lock = mutex_methods_with_lock

write_mutex_methods.wrap = mutex_methods_wrap

local write_mutex_meta = {
    __index = write_mutex_methods;
}

function concurrent.rw_mutex()
    local read = {
        count = 0;
        locked = false;
        notify = concurrent.notify();
        write = true;
    }
    local write = {
        locked = false;
        notify = concurrent.notify();
        read = true;
    }
    read.write = write
    write.read = read
    setmetatable(read, read_mutex_meta)
    setmetatable(write, write_mutex_meta)
    return write, read
end

----------------------------------------------------

local function ctime()
    return os_epoch() / 1000
end

local timer_methods = {}

timer_methods.selector = {}

function timer_methods.selector.immediate(self)
    local time = ctime()
    local milestone = self.milestone
    if time >= milestone then
        self.milestone = milestone + self.period
        return true
    else
        return false
    end
end

function timer_methods.selector.enter(self)
    local towait = self.milestone - ctime()
    if towait < 0 then
        towait = 0
    end
    return os_startTimer(towait)
end

function timer_methods.selector.condition(self, timer, event)
    return event[1] == 'timer' and event[2] == timer
end

function timer_methods.selector.leave(self, timer, selected)
    if not selected then
        os_cancelTimer(timer)
    else
        self.milestone = self.milestone + self.period
    end
end

timer_methods.sleep = wait_pattern

function timer_methods:skip_missed()
    local time = ctime()
    local milestone = self.milestone
    if time < milestone then
        return 0
    end
    local period = self.period
    local missed = math_floor((time - milestone) / period) + 1
    self.milestone = milestone + missed * period
    return missed
end

local timer_meta = {
    __index = timer_methods;
}

function concurrent.timer(period, start)
    if not start then
        start = ctime() + period
    end
    local timer = {
        milestone = start;
        period = period;
    }
    return setmetatable(timer, timer_meta)
end

----------------------------------------------------

local timeout_methods = {}

timeout_methods.selector = {}

timeout_methods.selector.immediate = return_false

function timeout_methods.selector.enter(self)
    return os_startTimer(self.delay)
end

function timeout_methods.selector.condition(self, timer, event)
    return event[1] == 'timer' and event[2] == timer
end

function timeout_methods.selector.leave(self, timer, selected)
    if not selected then
        os_cancelTimer(timer)
    end
end

local timeout_meta = {
    __index = timeout_methods;
}

function concurrent.timeout(delay)
    local timeout = {
        delay = delay;
    }
    return setmetatable(timeout, timeout_meta)
end

----------------------------------------------------

local event_methods = {}

event_methods.selector = {}
event_methods.selector.immediate = return_false
function event_methods.selector.enter()
    return {}
end
function event_methods.selector.condition(self, context, event)
    local matches = self.filter(event)
    if matches then
        for i=1, #event do
            context[i] = event[i]
        end
    end
    return matches
end
function event_methods.selector.leave(self, context, selected)
    if selected then
        return context
    end
end

local event_meta = {
    __index = event_methods;
}

function concurrent.event(filter)
    if type(filter == 'string') then
        local name = filter
        filter = function(event)
            return event[1] == name
        end
    elseif type(filter) == 'table' then
        local values = filter
        filter = function(event)
            for index, value in pairs(values) do
                if event[index] ~= value then
                    return false
                end
            end
            return true
        end
    end
    local event = {
        filter = filter;
    }
    return setmetatable(event, event_meta)
end

----------------------------------------------------

local semaphore_methods = {}

local function semaphore_methods_try_aquire(self)
    local aquired = self.aquired
    if aquired < self.count then
        self.aquired = aquired + 1
        return true
    else
        return false
    end
end

local function semaphore_methods_leave(self, woke, selected)
    if woke then
        self:release()
    end
end

semaphore_methods.selector = with_notify_create_selector(semaphore_methods_try_aquire, semaphore_methods_leave)

semaphore_methods.try_acquire = semaphore_methods_try_aquire

semaphore_methods.aquire = wait_pattern

function semaphore_methods:release()
    local aquired = self.aquired
    if aquired == 0 then
        error("semaphore is not locked", 2)
    end
    if not self.notify:wake() then
        self.aquired = aquired - 1
    end
end

function semaphore_methods:with_lock(action)
    self:aquire()
    local result = { pcall(action) }
    self:release()
    if result[1] then
        return table_unpack(result, 2)
    else
        error(result[2], 0)
    end
end

function semaphore_methods:wrap(action)
    return function(...)
        local args = {...}
        return self:with_lock(function()
            return action(table_unpack(args))
        end)
    end
end

local semaphore_meta = {
    __index = semaphore_methods;
}

function concurrent.semaphore(count)
    local semaphore = {
        count = count;
        aquired = 0;
        notify = concurrent.notify();
    }
    return setmetatable(semaphore, semaphore_meta)
end

----------------------------------------------------

local future_methods = {}

local function future_methods_try_get(self)
    if self.completed then
        return true, self.value
    else
        return false
    end
end

local function future_methods_leave(self, woke, selected)
    if selected then
        return self.value
    end
end

future_methods.selector = with_notify_create_selector(future_methods_try_get, future_methods_leave)

future_methods.get = wait_pattern

function future_methods:complete(value)
    if self.completed then
        error("future is already completed", 2)
    end
    self.completed = true
    self.value = value
    self.notify:wake_all()
end

local future_meta = {
    __index = future_methods;
}

function concurrent.future()
    local future = {
        completed = false;
        value = false;
        notify = concurrent.notify();
    }
    return setmetatable(future, future_meta)
end

----------------------------------------------------

return concurrent
