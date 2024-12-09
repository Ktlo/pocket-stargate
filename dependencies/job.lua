local concurrent = require 'concurrent'
local task = require 'task'

local function endsWith(str, ending)
    return str:sub(-#ending) == ending
end

local library = {}

----------------------------------------

local job_methods = {}

job_methods.selector = {}

function job_methods.selector.immediate(self)
    local future = self.future
    return future.selector.immediate(future)
end

function job_methods.selector.enter(self)
    local future = self.future
    return future.selector.enter(future)
end

function job_methods.selector.condition(self, context, event)
    local future = self.future
    return future.selector.condition(future, context, event)
end

function job_methods.selector.leave(self, context, selected)
    local future = self.future
    return future.selector.leave(future, context, selected)
end

local job_meta = {
    __index = job_methods;
}

local function job_root(job)
    local parent = job.parent
    if parent then
        return job_root(parent)
    else
        return job
    end
end

local job_child_death

local function job_terminate_condition(job)
    if job.task.status ~= 'alive' and not next(job.children) and job.future.status == 'idle' then
        if job.result.status == 'idle' then
            job.result:from(job.task.future)
        end
        job.future:from(job.result)
        local status = job.future.status
        if status == 'success' then
            job.status = 'done'
        else
            if endsWith(job.future.error, "Terminated") then
                job.status = 'canceled'
            else
                job.status = 'bad'
            end
        end
        if job.parent then
            job_child_death(job.parent, job)
        end
    end
end

job_child_death = function(job, child)
    if child.status == 'bad' then
        if job.result.status == 'idle' then
            job.result:from(child.future)
            -- ignore parallel errors for now
            local root = job_root(job)
            local traces = root.traces or {}
            table.insert(traces, child.task.traceback)
            root.traces = traces
        end
        job:cancel()
    end
    job.children[child] = nil
    job_terminate_condition(job)
end

local function job_create(pool, action)
    assert(action)
    local job
    job = {
        status = 'working';
        result = concurrent.future();
        future = concurrent.future();
        children = {};
        task = pool:spawn(function()
            task.context().JOB = job
            return action()
        end);
    }
    setmetatable(job, job_meta)
    pool:spawn_immortal(function()
        job.task:wait()
        if job.task.status == 'failed' then
            job:cancel()
        end
        job_terminate_condition(job)
    end):start()
    return job
end

function job_methods:fork(action)
    local job = job_create(self.task.pool, action)
    job.parent = self
    self.children[job] = true
    return job
end

function job_methods:async(action)
    local job = self:fork(action)
    job.task:start()
    return job
end

function job_methods:cancel_children()
    for child in pairs(self.children) do
        child:cancel()
    end
end

function job_methods:cancel()
    self:cancel_children()
    self.task:stop()
end

function job_methods:await()
    return self.future:get()
end

function job_methods:await_timeout(timeout)
    if concurrent.wait_timeout(self, timeout) then
        return true, self.future:get()
    else
        self:cancel()
        return false
    end
end

function job_methods:finnalize(action)
    local task = self.task.pool:spawn_immortal(function()
        concurrent.wait(self)
        return action()
    end)
    task:start()
    return task
end

function library.run(action)
    local pool = task.pool()
    local root = job_create(pool, action)
    root.task:start()
    pool:run()
    root.future:wait()
    local traces = root.traces or {}
    local traceback = root.task.traceback
    if traceback then
        table.insert(traces, traceback)
    end
    if next(traces) then
        local filename = os.date("crash_%Y-%m-%dT%H:%M:%SZ.txt")
        local file = io.open(filename, 'w')
        if file then
            file:write("ERROR: ")
            file:write(root.future.error)
            file:write('\n')
            for i=#traces, 1, -1 do
                local trace = traces[i]
                file:write(trace)
                file:write('\n')
            end
            file:close()
        end
    end
    return root:await()
end

function library.running()
    return task.context().JOB
end

local function job_require_running()
    return library.running() or error("no job in current context", 3)
end

function library.async(action)
    return job_require_running():async(action)
end

function library.cancel()
    return job_require_running():cancel()
end

function library.any(...)
    local result = { concurrent.select(...) }
    for _, job in ipairs { ... } do
        job:cancel()
    end
    return table.unpack(result)
end

function library.critical(action)
    local job = job_require_running()
    local t = job.task.pool:spawn_immortal(function()
        task.context().JOB = job
        return action()
    end)
    t:start()
    return t:join()
end

function library.retry(times, action, ...)
    local err
    for _=1, times do
        local r = table.pack(pcall(action, ...))
        if r[1] then
            return table.unpack(r, 2)
        else
            err = r[2]
        end
    end
    error(err, 0)
end

library.livedata = {}

function library.livedata.subscribe(property, action)
    return library.async(function()
        property:collect(function(value)
            library.async(function()
                action(value)
            end)
        end)
    end)
end

local function extract_values(properties)
    local values = {}
    for i, property in ipairs(properties) do
        values[i] = property.value
    end
    return table.unpack(values)
end

function library.livedata.combine(action, ...)
    local job = job_require_running()
    local properties = table.pack(...)
    local init = action(extract_values(properties))
    local result = concurrent.property(init)
    job:async(function()
        while true do
            concurrent.select(table.unpack(properties))
            result:set(action(extract_values(properties)))
        end
    end)
    return result
end

function library.livedata.determines(property, action)
    local job
    return library.livedata.subscribe(property, function(value)
        if job then
            job:cancel()
        end
        if value then
            job = library.async(action)
        end
    end)
end

return library
