local job = require 'job'

local rpc = {}

------------------------------------------------------

local function prepareAnswer(server, id, result)
    return {
        magic = "rpc";
        server = server;
        kind = 'response';
        id = id;
        result = result;
    }
end

local function prepareSuccess(server, id, ...)
    return prepareAnswer(server, id, { status = 'success', value = table.pack(...) })
end

local function prepareError(server, id, error)
    return prepareAnswer(server, id, { status = 'failure', error = error })
end

local function processRequest(commands, message, hostname)
    if type(message) == 'table' and message.magic == "rpc" and message.kind == 'request' and (not hostname or message.server == hostname) then
        local mtype = message.type
        if mtype == 'help' then
            local help = {}
            for command in pairs(commands) do
                help[command] = {
                    help = command.help;
                }
            end
            return prepareSuccess(hostname, message.id, help)
        elseif mtype == 'call' then
            local command = commands[message.command]
            if command == nil then
                return prepareError(hostname, message.id, "unknown remote procedure '"..message.command.."'")
            end
            local result = { pcall(command.procedure, table.unpack(message.arguments)) }
            if result[1] then
                return prepareSuccess(hostname, message.id, table.unpack(result, 2))
            else
                return prepareError(hostname, message.id, result[2])
            end
        else
            return prepareError(hostname, message.id, "unsupported rpc request type '"..mtype.."'")
        end
    end
end

function rpc.server(commands, handler, hostname)
    return job.async(function()
        while true do
            handler(function(request)
                return processRequest(commands, request, hostname)
            end)
        end
    end)
end

local dcall = peripheral.call

local function modemServerHandlerTemplate(modem, channel, f)
    local side, rchannel, replyChannel, request
    repeat
        side, rchannel, replyChannel, request = select(2, os.pullEvent("modem_message"))
    until side == modem and rchannel == channel
    local response = f(request)
    if response then
        dcall(modem, 'transmit', replyChannel, channel, response)
    end
end

local function withListeningChannel(modem, channel, action)
    -- if dcall(modem, 'isOpen', channel) then
    --     error("channel #"..channel.."is already open", 2)
    -- end
    dcall(modem, 'open', channel)
    return job.async(function()
        job.running():finnalize(function()
            dcall(modem, 'close', channel)
        end)
        return action()
    end)
end

function rpc.server_network(commands, modem, channel, hostname)
    if type(modem) == 'table' then
        modem = peripheral.getName(modem)
    end
    return withListeningChannel(modem, channel, function()
        local process = function(f) modemServerHandlerTemplate(modem, channel, f) end
        rpc.server(commands, process, hostname)
    end)
end

------------------------------------------------------

function rpc.is_response(request, response)
    return type(response) == 'table' and response.magic == "rpc" and response.id == request.id and response.kind == 'response' and response.result and response.server == request.server
end

local function executeRemote(client, mtype, fill, ...)
    local id = math.random(100000000000)
    local request = {
        magic = "rpc";
        server = client.server;
        id = id;
        kind = 'request';
        type = mtype;
    }
    fill(request, ...)
    local response = job.async(function()
        return client.exchange(request).result
    end)
    local ok, result = response:await_timeout(client.timeout)
    if not ok then
        error("timeout", 3)
    end
    if result.status == 'success' then
        return table.unpack(result.value)
    else
        error("rpc: "..result.error, 3)
    end
end

local function fillCall(request, procedure, ...)
    request.command = procedure
    request.arguments = table.pack(...)
end

local function executeRemoteProcedure(client, procedure, ...)
    return executeRemote(client, 'call', fillCall, procedure, ...)
end

local function fillHelp()end

local function executeRemoteHelp(client)
    return executeRemote(client, 'help', fillHelp)
end

local client_meta = {}

function client_meta:__index(key)
    return function(...)
        return executeRemoteProcedure(rawget(self, '_state'), key, ...)
    end
end

function client_meta:__pairs()
    return next, executeRemoteHelp(rawget(self, '_state')), nil
end

function rpc.client(exchange, timeout, hostname)
    local client = {
        _state = {
            exchange = exchange;
            timeout = timeout;
            server = hostname;
        };
    }
    return setmetatable(client, client_meta)
end

local function randomChannel(modem)
    while true do
        local channel = math.random(65535)
        if not dcall(modem, 'isOpen', channel) then
            return channel
        end
    end
end

local function exchangeNetworkTemplate(modem, serverChannel, request)
    local replyChannel = randomChannel(modem)
    dcall(modem, 'open', replyChannel)
    dcall(modem, 'transmit', serverChannel, replyChannel, request)
    job.running():finnalize(function()
        dcall(modem, 'close', replyChannel)
    end)
    local side, channel, response
    repeat
        _, side, channel, _, response = os.pullEvent("modem_message")
    until side == modem and channel == replyChannel and rpc.is_response(request, response)
    return response
end

function rpc.client_network(modem, channel, timeout, hostname)
    if type(modem) == 'table' then
        modem = peripheral.getName(modem)
    end
    return rpc.client(function (request)
        return exchangeNetworkTemplate(modem, channel, request)
    end, timeout, hostname)
end

------------------------------------------------------

function rpc.broadcast(push, event)
    local message = {
        magic = "rpc";
        kind = 'event';
        id = math.random();
        data = event;
    }
    push(message)
end

local function networkBroadcastPushTemplate(modem, channel, message)
    dcall(modem, 'transmit', channel, 0, message)
end

function rpc.broadcast_network(modem, channel, event)
    if type(modem) == 'table' then
        modem = peripheral.getName(modem)
    end
    rpc.broadcast(function(message)
        return networkBroadcastPushTemplate(modem, channel, message)
    end, event)
end

function rpc.subscribe(pull, action)
    return job.async(function()
        while true do
            local message = pull()
            if type(message) == 'table' and message.magic == 'rpc' and message.kind == 'event' then
                job.async(function() action(message.data) end)
            end
        end
    end)
end

local function networkSubscribePullTemplate(modem, channel)
    local side, rchannel, message
    repeat
        _, side, rchannel, _, message = os.pullEvent("modem_message")
    until side == modem and rchannel == channel
    return message
end

function rpc.subscribe_network(modem, channel, action)
    if type(modem) == 'table' then
        modem = peripheral.getName(modem)
    end
    return withListeningChannel(modem, channel, function()
        rpc.subscribe(function()
            return networkSubscribePullTemplate(modem, channel)
        end, action)
    end)
end

------------------------------------------------------

function rpc.simple_commands(commands)
    local result = {}
    for k, v in pairs(commands) do
        result[k] = { procedure = v }
    end
    return result
end

------------------------------------------------------

return rpc
