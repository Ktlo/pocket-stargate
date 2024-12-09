local concurrent = require 'concurrent'

local function endsWith(str, ending)
    return str:sub(-#ending) == ending
end

local queueEventRaw = os.queueEventRaw or os.queueEvent
os.queueEventRaw = queueEventRaw

local library = {}

-----------------------------------------------

local task_methods = {}

task_methods.selector = {}

function task_methods.selector.immediate(self)
    local future = self.future
    return future.selector.immediate(future)
end

function task_methods.selector.enter(self)
    local future = self.future
    return future.selector.enter(future)
end

function task_methods.selector.condition(self, context, event)
    local future = self.future
    return future.selector.condition(future, context, event)
end

function task_methods.selector.leave(self, context, selected)
    local future = self.future
    return future.selector.leave(future, context, selected)
end

task_methods.wait = concurrent.wait

function task_methods:join()
    return self.future:get()
end

local function task_continue(self, event)
    if self.status ~= 'alive' then
        return
    end
    if event[1] == 'terminate' and self.immortal then
        return
    end
    local thread = self.thread
    local prev_task = _TASK
    _G._TASK = self
    local result = { coroutine.resume(thread, table.unpack(event)) }
    _G._TASK = prev_task
    if not result[1] then
        local msg = result[2]
        self.future:failure(msg)
        if endsWith(msg, "Terminated") then
            self.status = 'stoped'
        else
            self.status = 'failed'
            self.traceback = debug.traceback(thread, msg)
        end
    elseif coroutine.status(thread) == 'dead' then
        self.future:submit(table.unpack(result, 2))
        self.status = 'dead'
    else
        local next_event = result[2]
        self.event = next_event
        if next_event == 'wake' then
            table.insert(self.pool.orders, {task=self, order='wake'})
        end
    end
end

function task_methods:resume(event)
    self:start()
    local eventName = event[1]
    if eventName == 'task_stop' then
        if event[2] == self.id then
            task_continue(self, { 'terminate' })
        end
        return
    end
    if eventName == 'terminate' or (not self.event) or self.event == eventName then
        task_continue(self, event)
    end
end

function task_methods:stop()
    if self.status == 'alive' then
        table.insert(self.pool.orders, { task=self, order='stop' })
    end
end

function task_methods:start()
    if not self.started then
        self.started = true
        task_continue(self, {})
    end
end

local task_meta = {
    __index = task_methods;
}

-----------------------------------------------

local pool_methods = {}

local taskIdCounter = 1

function pool_methods:spawn(action, immortal)
    local task = {
        id = taskIdCounter;
        immortal = immortal or false;
        pool = self;
        future = concurrent.future();
        thread = coroutine.create(action);
        event = nil;
        status = 'alive';
        context = {};
        started = false;
    }
    taskIdCounter = taskIdCounter + 1
    setmetatable(task, task_meta)
    table.insert(self.tasks, task)
    return task
end

function pool_methods:spawn_immortal(action)
    return self:spawn(action, true)
end

function pool_methods:resume(event)
    local filtered = {}
    local process = self.tasks
    self.tasks = filtered
    for _, task in ipairs(process) do
        task:resume(event)
        if task.status == 'alive' then
            table.insert(filtered, task)
        end
    end
end

function pool_methods:process_orders_queue()
    while next(self.orders) do
        local queue = self.orders
        self.orders = {}
        for _, record in ipairs(queue) do
            local task = record.task
            local order = record.order
            if order == 'stop' then
                task_continue(task, { 'terminate' })
            elseif order == 'wake' then
                task_continue(task, { 'wake' })
            end
        end
    end
end

function pool_methods:process_internal_events()
    local events = self.events
    if next(events) then
        self.events = {}
        for _, event in ipairs(events) do
            self:resume(event)
        end
    end
end

function pool_methods:step()
    self:process_orders_queue()
    self:process_internal_events()
    if next(self.tasks) then
        if next(self.events) then
            queueEventRaw('event_batch')
        end
        local event = { os.pullEventRaw() }
        if event[1] ~= 'event_batch' then
            self:resume(event)
        end
    end
end

function pool_methods:run()
    while next(self.tasks) do
        self:step()
    end
end

function pool_methods:queue_event(eventName, ...)
    table.insert(self.events, {eventName, ...})
end

local pool_meta = {
    __index = pool_methods;
}

-----------------------------------------------

function library.pool()
    local pool = {
        tasks = {};
        events = {};
        orders = {};
    }
    return setmetatable(pool, pool_meta)
end

function library.running()
    return _TASK
end

function library.context()
    local task = library.running() or error("context() called outside any task", 2)
    return task.context
end

function library.any(...)
    local result = { concurrent.select(...) }
    for _, task in ipairs { ... } do
        task:stop()
    end
    return table.unpack(result)
end

function library.yield()
    coroutine.yield('wake')
end

-----------------------------------------------

os.queueEvent = function(...)
    local task = library.running()
    if task then
        task.pool:queue_event(...)
    else
        queueEventRaw(...)
    end
end

return library
