local DEFAULT_BASE_PATH = "network"
local DEFAULT_PORT = 7625
local DEFAULT_HOSTNAME = "fileserver"

local rpc = require 'ktlo.rpc'
local job = require 'ktlo.job'
local blake3 = require 'ccryptolib.blake3'

settings.define("sfs.basePath", {
    description = "Path",
    default = DEFAULT_BASE_PATH,
    type = "string",
})

settings.define("sfs.port", {
    description = "Port",
    default = DEFAULT_PORT,
    type = "number",
})

settings.define("sfs.hostname", {
    description = "Hostname",
    default = DEFAULT_HOSTNAME,
    type = "string",
})

local modems = { peripheral.find("modem") }

local basePath = settings.get("sfs.basePath", DEFAULT_BASE_PATH)
local port = settings.get("sfs.port", DEFAULT_PORT)
local hostname = settings.get("sfs.hostname", DEFAULT_HOSTNAME)

local handlers = {}

function handlers.put(path, content, username, password)
    
end

function handlers.get(path)

end

function handlers.list(path)
    
end

function handlers.info(path)

end

job.run(function()

for _, modem in ipairs(modems) do
    rpc.server_network(handlers, modem, port, hostname)
end

end)
