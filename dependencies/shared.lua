local TTL = 5

local myId = os.getComputerID()

local shared = {}

local buckets = {}

local broadcast = function(event)end

local function tell(action, bucket, resource)
    broadcast {
        action = action;
        bucket = bucket;
        resource = resource;
        computer = myId;
    }
end

local function exchange(action, bucket, resource)
    tell(action, bucket, resource)
    local id = math.random()
    os.queueEvent("shared_loopback", id)
    while true do
        local _, event_id = os.pullEvent("shared_loopback")
        if event_id == id then
            return
        end
    end
    -- while true do
    --     local _, event_action, event_bucket, event_resource = os.pullEvent("shared_exchange")
    --     if action == event_action and bucket == event_bucket and resource == event_resource then
    --         return
    --     end
    -- end
end

local bucket_index = {}

local resource_index = {}

function resource_index:revive()
    assert(not self.closed, "resource is closed")
    exchange('revive', self.bucket.name, self.name)
    self.ttl = TTL;
end

local function destroy_resource(bucket, name)
    local resources = bucket.resources
    local resource = resources[name]
    if resource.closed then
        return
    end
    resources[name] = nil
    resource.closed = true
    bucket:on_destroy(name)
    os.queueEvent("shared_release", bucket.name, name)
end

function resource_index:release()
    assert(not self.closed, "resource is closed")
    tell('release', self.bucket.name, self.name)
    destroy_resource(self.bucket, self.name)
end

local resource_meta = {
    __index = resource_index;
}

local function get_or_create_resource(self, name)
    local resources = self.resources
    local old_resource = resources[name]
    if old_resource then
        return old_resource
    end
    local resource = {
        bucket = self;
        name = name;
        ttl = TTL;
        closed = false;
    }
    resources[name] = resource
    setmetatable(resource, resource_meta)
    self:on_create(name)
    return resource
end

function bucket_index:try_acquire(name)
    exchange('acquire', self.name, name)
    local resources = self.resources
    if resources[name] then
        return nil, "resource is busy"
    end
    return get_or_create_resource(self, name)
end

function bucket_index:acquire(name)
    local bucket = self.name
    while true do
        local resource = self:try_acquire(name)
        if resource then
            return resource
        end
        while true do
            local _, buc, res = os.pullEvent("shared_release")
            if bucket == buc and name == res then
                break
            end
        end
    end
end

local function event_handler(bucket, resource)end

bucket_index.on_create = event_handler

bucket_index.on_destroy = event_handler

local bucket_meta = {
    __index = bucket_index;
}

local function get_or_create_bucket(name)
    local old_bucket = buckets[name]
    if old_bucket then
        return old_bucket
    end
    local bucket = {
        name = name;
        resources = {};
    }
    buckets[name] = bucket
    return setmetatable(bucket, bucket_meta)
end

shared.bucket = get_or_create_bucket

local function take_snapshot()
    local snapshot = {}
    for bucket_name, bucket in pairs(buckets) do
        for resource_name, resource in pairs(bucket.resources) do
            table.insert(snapshot, { bucket = bucket_name, resource = resource_name, ttl = resource.ttl })
        end
    end
    return snapshot
end

local function init(snapshot)
    for _, record in ipairs(snapshot) do
        local bucket = get_or_create_bucket(record.bucket)
        get_or_create_resource(bucket, record.resource).ttl = record.ttl
    end
end

local loaded = false

function shared.push(event)
    local action = event.action
    local computer = event.computer
    if action == 'load' then
        if computer == myId then
            return
        end
        broadcast { action = 'state', state = take_snapshot(), recipient = computer, computer = myId }
        return
    elseif action == 'state' then
        if event.recipient ~= myId or loaded then
            return
        end
        loaded = true
        init(event.state)
        os.queueEvent('shared_init')
        return
    end
    local bucket = event.bucket
    local resource = event.resource
    if computer == myId then
        os.queueEvent("shared_exchange", action, bucket, resource)
        return
    end
    local bucket_obj = get_or_create_bucket(bucket)
    if action == 'acquire' then
        get_or_create_resource(bucket_obj, resource)
    elseif action == 'revive' then
        get_or_create_resource(bucket_obj, resource).ttl = TTL
    elseif action == 'release' then
        destroy_resource(bucket_obj, resource)
    end
end

function shared.on_event(listener)
    broadcast = listener
end

function shared.expire()
    for _, bucket in pairs(buckets) do
        local resources = bucket.resources
        local to_remove = {}
        for name, resource in pairs(resources) do
            local ttl = resource.ttl - 1
            resource.ttl = ttl
            if ttl <= 0 then
                table.insert(to_remove, name)
            end
        end
        for _, name in ipairs(to_remove) do
            destroy_resource(bucket, name)
        end
    end
end

function shared.initialize()
    broadcast { action = 'load', computer = myId }
    local timer = os.startTimer(1)
    while true do
        local event_name, arg1 = os.pullEvent()
        if event_name == 'shared_init' then
            os.cancelTimer(timer)
            return
        end
        if event_name == 'timer' and arg1 == timer then
            return
        end
    end
end

return shared
