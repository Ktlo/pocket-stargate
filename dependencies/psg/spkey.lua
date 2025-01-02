local PRIVATE_KEY_FILE = "host_key.txt"

-------------------------------------------

local random = require 'ccryptolib.random'
local ed25519 = require 'ccryptolib.ed25519'
local base64 = require 'ktlo.base64'
local keyring = require 'psg.keyring'

local privateKey, publicKey
do
    local file = io.open(PRIVATE_KEY_FILE, 'r')
    if file then
        privateKey = base64.decode(file:read('a'))
    else
        if not random.isInit() then
            random.initWithTiming()
        end
        privateKey = random.random(32)
        file = io.open(PRIVATE_KEY_FILE, 'w')
        if not file then
            error("cannot open file '"..PRIVATE_KEY_FILE.."' for write mode")
        end
        file:write(base64.encode(privateKey))
    end
    file:close()
    publicKey = ed25519.publicKey(privateKey)
end

local pkey = {}

local sessions = {}

local function cleanupSessions()
    local prevKey = nil
    local key, value = next(sessions)
    while key do
        if os.time() - value > 10 then
            sessions[key] = nil
            key = prevKey
        end
        prevKey = key
        key, value = next(sessions, key)
    end
end

local serializeOpts = { compact = true }

function pkey.public_key()
    return base64.encode(publicKey)
end

function pkey.auth_request(nonce, payload)
    assert(#nonce <= 64)
    cleanupSessions()
    local session = random.random(16)
    sessions[session] = os.time()
    local message = {
        nonce = nonce;
        session = base64.encode(session);
        payload = payload;
        key = base64.encode(publicKey);
    }
    local messageString = textutils.serialise(message, serializeOpts)
    local signature = ed25519.sign(privateKey, publicKey, messageString)
    return {
        message = messageString;
        signature = base64.encode(signature);
    }
end

function pkey.auth_continue(request)
    cleanupSessions()
    local messageString = request.message
    local message = textutils.unserialise(messageString)
    if not message then
        return false, "inconsistent message", message.key
    end
    local session = base64.decode(message.session)
    if not sessions[session] then
        return false, "session is expired", message.key
    end
    local key = base64.decode(message.key)
    if not keyring.keys[key] then
        return false, "access denied", message.key
    end
    if not ed25519.verify(key, messageString, base64.decode(request.signature)) then
        return false, "signature is not valid", message.key
    end
    return true, nil, message.key
end

return pkey
