local concurrent = {}

local immediately = { 'immediate' }

local function wait_pattern(object)
    local selector = object._selector
    local context = selector.enter(object)
    if not selector.condition(object, context, immediately) then
        repeat
            local event = { os.pullEvent() }
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
            local event = { os.pullEvent() }
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
            result = { selector.leave(object, context, true) }
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
        for i, id in ipairs(self.consumers) do
            if consumerId == id then
                table.remove(self.consumers, i)
                return
            end
        end
        error("unreachable")
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
    return with_notify_selector_enter(self.collapsed, self)
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
    local result = { self:wait() }
    if result[1] then
        return table.unpack(result, 2)
    else
        error("error from future: "..tostring(result[2]), 2)
    end
end

function future_methods:submit(...)
    if self.collapsed then
        error("the value for future is already submitted", 2)
    end
    self.collapsed = true
    self.value = { ... }
    self.notify:wake_all()
end

function future_methods:failure(err)
    if self.collapsed then
        error("the value for future is already submitted", 2)
    end
    self.collapsed = true
    self.error = err
    self.notify:wake_all()
end

local future_meta = {
    __index = future_methods;
}

function concurrent.future()
    local future = {
        collapsed = false;
        notify = concurrent.notify();
    }
    return setmetatable(future, future_meta)
end

----------------------------------------------------

local task_methods = {}

task_methods._selector = {}

function task_methods._selector.enter(self)
    local result = self.result
    return result._selector.enter(result)
end

function task_methods._selector.condition(self, context, event)
    local result = self.result
    return result._selector.condition(result, context, event)
end

function task_methods._selector.leave(self, context, selected)
    local result = self.result
    return result._selector.leave(result, context, selected)
end

task_methods.wait = wait_pattern

function task_methods:get()
    return self.result:get()
end

function task_methods:isStarted()
    return self.started
end

function task_methods:isAlive()
    return not self.result.collapsed
end

function task_methods:isFailed()
    return not not self.result.error
end

function task_methods:isFinished()
    return self.result.collapsed and not self.result.error
end

local function task_handle(self, ...)
    if not self:isAlive() then
        return
    end
    local routine = self.coroutine
    local prev_task = _TASK
    _G._TASK = self
    local result = { coroutine.resume(routine, ...) }
    _G._TASK = prev_task
    if not result[1] then
        self.result:failure(result[2])
    elseif coroutine.status(routine) == 'dead' then
        self.result:submit(table.unpack(result, 2))
    else
        self.event = result[2]
    end
end

local function task_resume(self, ...)
    if not self:isStarted() then
        task_handle(self)
        self.started = true
    end
    local event = ...
    if self:isAlive() and (event == 'terminate' or (not self.event) or self.event == event) then
        task_handle(self, ...)
    end
end

local task_resume_children
local task_resume_subtree

task_resume_children = function(self, ...)
    local filtered = {}
    for _, child in ipairs(self.children) do
        task_resume_subtree(child, ...)
        if child:isAlive() then
            table.insert(filtered, child)
        end
    end
    self.children = filtered
end

task_resume_subtree = function(self, ...)
    task_resume_children(self, ...)
    task_resume(self, ...)
end

function task_methods:cancel_children()
    task_resume_children(self, 'terminate')
    error("Terminated", 0)
end

function task_methods:cancel()
    if coroutine.status(self.coroutine) == "running" then
        task_resume_children(self, 'terminate')
        error("Terminated", 0)
    else
        task_resume_subtree(self, 'terminate')
    end
end

function task_methods:async(action)
    local child = self:fork(action)
    task_resume_subtree(child)
    return child
end

local function while_condition(task)
    local children = task.children
    if #children == 0 then
        return false
    end
    for _, child in ipairs(children) do
        if child:isAlive() then
            return true
        end
    end
    return false
end

local function task_scope_run(task)
    local event
    repeat
        event = { os.pullEventRaw() }
        task_resume_subtree(task, table.unpack(event))
    until not task:isAlive()
    while while_condition(task) do
        event = { os.pullEventRaw() }
        task_resume_children(task, table.unpack(event))
    end
    return task:get()
end

function task_methods:scope(action)
    local child = self:fork(action)
    return task_scope_run(child)
end

local task_meta = {
    __index = task_methods;
}

local function task_create(action)
    local task = {
        result = concurrent.future();
        parent = nil;
        started = false;
        children = {};
        coroutine = coroutine.create(action);
        event = nil;
    }
    return setmetatable(task, task_meta)
end

function task_methods:fork(action)
    local task = task_create(action)
    task.parent = self
    table.insert(self.children, task)
    return task
end

concurrent.task = {}

function concurrent.task.cancel()
    local task = _TASK
    if task then
        task:cancel()
    else
        error("Terminated", 0)
    end
end

function concurrent.task.async(action)
    local task = _TASK
    if not task then
        error("no task in current context", 2)
    end
    return task:async(action)
end

function concurrent.task.run(action)
    local task = _TASK
    if task then
        return task:scope(action)
    else
        local root = task_create(action)
        return task_scope_run(root)
    end
end

function concurrent.task.any(...)
    local result = { concurrent.select(...) }
    for _, task in ipairs({...}) do
        task:cancel()
    end
    return table.unpack(result)
end

----------------------------------------------------

return concurrent
