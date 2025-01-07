local os, table, math = os, table, math
local os_pullEventRaw, os_startTimer, os_cancelTimer, os_epoch = os.pullEventRaw, os.startTimer, os.cancelTimer, os.epoch
local table_unpack, table_pack, table_remove, table_insert = table.unpack, table.pack, table.remove, table.insert
local math_floor = math.floor
local setmetatable, select, error, type, pairs = setmetatable, select, error, type, pairs
local check = require 'ktlo.check'
local expect = check.expect

local function table_index(obj, value)
    for i=1, #obj do
        if value == obj[i] then
            return i
        end
    end
    return nil
end

----------------------------------------------------

--- @class (exact) selector
--- @field immediate fun(self: waitable): boolean, ...
--- @field enter fun(self: waitable): any
--- @field condition fun(self: waitable, context: any, event: any[]): boolean
--- @field leave fun(self: waitable, context: any, selected: boolean): ...

--- @class (exact) waitable
--- @field selector selector

local waitable_classes = { waitable = true };

local concurrent = {}

--- @param object waitable
--- @return any ...
--- @async
local function wait_pattern(object)
    expect(1, object, 'waitable')
    local selector = object.selector
    local immediate = { selector.immediate(object) }
    if immediate[1] then
        return table_unpack(immediate, 2)
    end
    local context = selector.enter(object)
    repeat
        local event = { os_pullEventRaw() }
        local event_name = event[1]
        if event_name == 'terminate' then
            selector.leave(object, context, false)
            error("Terminated", 0)
        end
    until selector.condition(object, context, event)
    return selector.leave(object, context, true)
end

concurrent.wait = wait_pattern

--- @param ... waitable
--- @return waitable
--- @return any ...
--- @async
function concurrent.select(...)
    for i=1, select('#', ...) do
        expect(i, select(i, ...), 'waitable')
    end
    local objects = { ... }
    local selectors = {}
    local contexts = {}
    local n = #objects
    for i=1, n do
        local object = objects[i]
        local immediate = { object.selector.immediate(object) }
        if immediate[1] then
            return object, table_unpack(immediate, 2)
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

--- @class notify: waitable
--- @field private id integer
--- @field private consumers table<integer, boolean>
local notify_methods = {}

local notifyConsumerIdCounter = 1

notify_methods.selector = {
    immediate = return_false;
    --- @param self notify
    enter = function(self)
        local consumerId = notifyConsumerIdCounter
        notifyConsumerIdCounter = notifyConsumerIdCounter + 1
        table_insert(self.consumers, consumerId)
        return consumerId
    end;
    --- @param self notify
    condition = function(self, consumerId, event)
        local eventName, notifyId, receivedConsumerId = table.unpack(event)
        return eventName == 'notify_wake' and notifyId == self.id and (receivedConsumerId == consumerId or not receivedConsumerId)
    end;
    --- @param self notify
    leave = function(self, consumerId, selected)
        if not selected then
            local consumers = self.consumers
            local not_woke = table_index(consumers, consumerId)
            if not_woke then
                table_remove(consumers, not_woke)
                return false
            else
                return true
            end
        end
        return false
    end;
}

--- @param self notify
--- @return boolean
--- @async
function notify_methods:wait()
    expect(1, self, 'notify')
    return wait_pattern(self)
end

--- @param self notify
--- @return boolean
function notify_methods:wake()
    expect(1, self, 'notify')
    local consumers = self.consumers
    local consumer = table_remove(consumers, 1)
    if consumer then
        os.queueEvent("notify_wake", self.id, consumer)
        return true
    else
        return false
    end
end

--- @param self notify
--- @return integer
function notify_methods:wake_all()
    expect(1, self, 'notify')
    local count = #self.consumers
    if count > 0 then
        self.consumers = {}
        os.queueEvent("notify_wake", self.id)
        return count
    else
        return 0
    end
end

local notify_meta = {
    __index = notify_methods;
    __classes = waitable_classes;
    __name = 'notify';
}

local notifyIdCounter = 1

--- @return notify
--- @nodiscard
local function notify_create()
    local notifyId = notifyIdCounter
    notifyIdCounter = notifyIdCounter + 1
    local notify = {
        id = notifyId;
        count = 0;
        consumers = {};
    }
    return setmetatable(notify, notify_meta)
end

concurrent.notify = notify_create

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

--- @return selector
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

--- @class lockable: waitable
--- @field locked boolean
local lockable_methods = {}

--- @param self lockable
--- @return boolean
function lockable_methods:try_lock()
    expect(1, self, 'lockable')
    return self.selector.immediate(self)
end

--- @param self lockable
--- @async
function lockable_methods:lock()
    expect(1, self, 'lockable')
    wait_pattern(self)
end

--- @param self lockable
function lockable_methods:unlock()
    expect(1, self, 'lockable')
    error("not implemented")
end

--- @param self lockable
--- @param action function
--- @param ... any
--- @return any ...
--- @async
function lockable_methods:with_lock(action, ...)
    expect(1, self, 'lockable')
    expect(2, action, 'function')
    wait_pattern(self)
    local result = { pcall(action, ...) }
    self:unlock()
    if result[1] then
        return table_unpack(result, 2)
    else
        error(result[2], 0)
    end
end

--- @param self lockable
--- @param action function
--- @param ... any
--- @return boolean
--- @return any ...
function lockable_methods:with_try_lock(action, ...)
    expect(1, self, 'lockable')
    expect(2, action, 'function')
    local locked = self.selector.immediate(self)
    if locked then
        local result = { pcall(action, ...) }
        self:unlock()
        if result[1] then
            return true, table_unpack(result, 2)
        else
            error(result[2], 0)
        end
    else
        return false
    end
end

--- @generic T: function
--- @param self lockable
--- @param action T
--- @return T
--- @nodiscard
function lockable_methods:wrap(action)
    expect(1, self, 'lockable')
    expect(2, action, 'function')
    return function(...)
        return self:with_lock(function(...)
            return action(...)
        end, ...)
    end
end

local function lockable_methods_leave(self, woke, selected)
    if woke then
        self:unlock()
    end
end

local function create_lockable_selector(immediate)
    return with_notify_create_selector(immediate, lockable_methods_leave)
end

local lockable_classes = { lockable = true, waitable = true };

--------------------------------------------

--- @class mutex: lockable
--- @field locked boolean
--- @field private notify notify
local mutex_methods = {}

setmetatable(mutex_methods, { __index = lockable_methods })

local function mutex_methods_try_lock(self)
    if self.locked then
        return false
    else
        self.locked = true
        return true
    end
end

mutex_methods.selector = create_lockable_selector(mutex_methods_try_lock)

--- @param self mutex
function mutex_methods:unlock()
    expect(1, self, 'mutex')
    if not self.locked then
        error("mutex not locked", 2)
    end
    if not self.notify:wake() then
        self.locked = false
    end
end

local mutex_meta = {
    __index = mutex_methods;
    __classes = lockable_classes;
    __name = 'mutex';
}

--- @return mutex
--- @nodiscard
function concurrent.mutex()
    local mutex = {
        locked = false;
        notify = notify_create();
    }
    return setmetatable(mutex, mutex_meta)
end;

----------------------------------------------------

--- @generic T
--- @class channel<T> : waitable
--- @field private queue table
--- @field private notify notify
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

--- @param self channel
--- @param obj any
function channel_methods:send(obj)
    expect(1, self, 'channel')
    table_insert(self.queue, obj)
    self.notify:wake()
end


--- @generic T
--- @param self channel<T>
--- @return boolean
--- @return T | nil
function channel_methods:try_recv()
    expect(1, self, 'channel')
    return channel_methods_try_recv(self)
end

--- @generic T
--- @param self channel<T>
--- @return T
--- @async
function channel_methods:recv()
    expect(1, self, 'channel')
    return wait_pattern(self)
end

local channel_meta = {
    __index = channel_methods;
    __classes = waitable_classes;
    __name = 'channel';
}

--- @generic T
--- @return channel<T>
--- @nodiscard
function concurrent.channel()
    local channel = {
        queue = {};
        notify = notify_create();
    }
    return setmetatable(channel, channel_meta)
end

----------------------------------------------------

--- @class property<T>: waitable
--- @field value `T`
--- @field private notify notify
local property_methods = {}

local function property_methods_leave(self, woke, selected)
    if selected then
        return self.value
    end
end

property_methods.selector = with_notify_create_selector(return_false, property_methods_leave)

--- @generic T
--- @param self property<T>
--- @param value T
function property_methods:set(value)
    expect(1, self, 'property')
    if self.value ~= value then
        self.value = value
        self.notify:wake_all()
    end
end

--- @generic T
--- @param self property<T>
--- @param collector fun(value: T)
--- @async
function property_methods:collect(collector)
    expect(1, self, 'property')
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

--- @generic T
--- @param self property<T>
--- @param condition fun(value: T): boolean
--- @return T
--- @async
function property_methods:wait_until(condition)
    expect(1, self, 'property')
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
    __classes = waitable_classes;
    __name = 'property';
}

--- @generic T
--- @param init T
--- @return property<T>
--- @nodiscard
function concurrent.property(init)
    local property = {
        value = init;
        notify = notify_create();
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

--- @class read_mutex : lockable
--- @field private count integer
--- @field private notify notify
--- @field private write write_mutex
local read_mutex_methods = {}

read_mutex_methods.selector = create_lockable_selector(read_mutex_methods_try_lock)

--- @param self read_mutex
function read_mutex_methods:unlock()
    expect(1, self, 'read_mutex')
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

setmetatable(read_mutex_methods, { __index = lockable_methods })

local read_mutex_meta = {
    __index = read_mutex_methods;
    __classes = lockable_classes;
    __name = 'read_mutex';
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

--- @class write_mutex : lockable
--- @field private notify notify
--- @field private read read_mutex
local write_mutex_methods = {}

write_mutex_methods.selector = create_lockable_selector(write_mutex_methods_try_lock)

--- @param self write_mutex
function write_mutex_methods:unlock()
    expect(1, self, 'write_mutex')
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
    if waiters > 0 then
        read.count = waiters
        return
    end
    self.locked = false
end

local write_mutex_meta = {
    __index = write_mutex_methods;
    __classes = lockable_classes;
    __name = 'write_mutex';
}

--- @return write_mutex
--- @return read_mutex
--- @nodiscard
function concurrent.rw_mutex()
    local read = {
        count = 0;
        locked = false;
        notify = notify_create();
        write = true;
    }
    local write = {
        locked = false;
        notify = notify_create();
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
    return os_epoch('utc') / 1000
end

--- @class timer : waitable
--- @field milestone number
--- @field period number
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

--- @param self timer
--- @async
function timer_methods:sleep()
    expect(1, self, 'timer')
    return wait_pattern(self)
end

--- @param self timer
--- @return integer
function timer_methods:skip_missed()
    expect(1, self, 'timer')
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
    __classes = waitable_classes;
    __name = 'timer';
}

--- @param period number
--- @param start? number
--- @return timer
--- @nodiscard
function concurrent.timer(period, start)
    expect(1, period, 'number')
    expect(2, start, 'number', 'nil')
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

--- @class timeout : waitable
--- @field delay number
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
    __classes = waitable_classes;
    __name = 'timeout';
}

--- @param delay number
--- @return timeout
--- @nodiscard
function concurrent.timeout(delay)
    expect(1, delay, 'number')
    local timeout = {
        delay = delay;
    }
    return setmetatable(timeout, timeout_meta)
end

----------------------------------------------------

--- @class event : waitable
--- @field private filter fun(event: table): boolean
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

--- @param self event
--- @return string
--- @return any ...
--- @async
function event_methods:listen()
    expect(1, self, 'event')
    return table_unpack(wait_pattern(self))
end

local event_meta = {
    __index = event_methods;
    __classes = waitable_classes;
    __name = 'event';
}

--- @param filter fun(event: table): boolean
--- @return event
--- @overload fun(filter: string): event
--- @overload fun(filter: table): event
function concurrent.event(filter)
    expect(1, filter, 'function', 'string', 'table')
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

--- @class semaphore: lockable
--- @field count integer
--- @field private aquired integer
--- @field private notify notify
local semaphore_methods = {}

local function semaphore_methods_try_aquire(self)
    local aquired = self.aquired
    local count = self.count
    if aquired < count then
        aquired = aquired + 1
        self.aquired = aquired
        if aquired == count then
            self.locked = true
        end
        return true
    else
        return false
    end
end

semaphore_methods.selector = create_lockable_selector(semaphore_methods_try_aquire)

--- @param self semaphore
function semaphore_methods:unlock()
    expect(1, self, 'semaphore')
    local aquired = self.aquired
    if aquired == 0 then
        error("semaphore is not locked", 2)
    end
    if not self.notify:wake() then
        self.aquired = aquired - 1
        self.locked = false
    end
end

setmetatable(semaphore_methods, { __index = lockable_methods })

local semaphore_meta = {
    __index = semaphore_methods;
    __classes = lockable_classes;
    __name = 'semaphore';
}

--- @param count integer
--- @return semaphore
--- @nodiscard
function concurrent.semaphore(count)
    expect(1, count, 'number')
    local semaphore = {
        count = math_floor(count);
        aquired = 0;
        locked = false;
        notify = notify_create();
    }
    return setmetatable(semaphore, semaphore_meta)
end

----------------------------------------------------

--- @class future<T> : waitable
--- @field completed boolean
--- @field value `T`
--- @field private notify notify
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

--- @generic T
--- @param self future<T>
--- @return T
--- @async
function future_methods:get()
    expect(1, self, 'future')
    return wait_pattern(self)
end

--- @generic T
--- @param self future<T>
--- @param value T
function future_methods:complete(value)
    expect(1, self, 'future')
    if self.completed then
        error("future is already completed", 2)
    end
    self.completed = true
    self.value = value
    self.notify:wake_all()
end

local future_meta = {
    __index = future_methods;
    __classes = waitable_classes;
    __name = 'future';
}

--- @generic T
--- @return future<T>
--- @nodiscard
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
