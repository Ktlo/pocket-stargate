local PUBLIC_KEY_FILE = "public_key.txt"
local PRIVATE_KEY_FILE = "private_key.txt"

----------------------------------------------------------

local random = require 'ccryptolib.random'
local ed25519 = require 'ccryptolib.ed25519'
local blake3 = require 'ccryptolib.blake3'
local base64 = require 'ktlo.base64'
local keyring = require 'psg.keyring'

random.initWithTiming()

local isEncryprted

local function save_private_key(keyInfo)
    local file = io.open(PRIVATE_KEY_FILE, 'w')
    if not file then
        error("failed to open private key file: "..PRIVATE_KEY_FILE)
    end
    file:write(textutils.serialise(keyInfo))
    file:close()
end

local function open_private_key()
    local file = assert(io.open(PRIVATE_KEY_FILE, 'r'))
    local contentString = file:read('a')
    file:close()
    return textutils.unserialise(contentString)
end

local function open_public_key()
    local file = io.open(PUBLIC_KEY_FILE, 'r')
    if not file then
        error("failed to open public key file: "..PUBLIC_KEY_FILE)
    end
    return keyring.read_key(file:read('l'))
end

local function save_public_key(key, name)
    local file = io.open(PUBLIC_KEY_FILE, 'w')
    if not file then
        error("failed to open public key file: "..PUBLIC_KEY_FILE)
    end
    file:write(base64.encode(key))
    if name then
        file:write(" ")
        file:write(name)
    end
    file:write("\n")
    file:close()
end

local publicKey, name
if not fs.exists(PRIVATE_KEY_FILE) then
    local privateKey = random.random(32)
    local keyInfo = {
        encrypted = false;
        key = base64.encode(privateKey);
    }
    publicKey = ed25519.publicKey(privateKey)
    save_private_key(keyInfo)
    save_public_key(publicKey)
    isEncryprted = false
else
    local key
    key, name = open_public_key()
    publicKey = base64.decode(key)
    isEncryprted = open_private_key().encrypted
end

local vault = {}

----------------------------------------------------------

function vault.gen_nonce()
    return base64.encode(random.random(16))
end

local serializeOpts = { compact = true }

function vault.public_key()
    return base64.encode(publicKey), name
end

function vault.verify(nonce, response)
    local messageString = response.message
    local message = textutils.unserialise(messageString)
    local key = base64.decode(message.key)
    if message.nonce ~= nonce then
        return false, "invalid nonce"
    end
    if not keyring.keys[key] then
        return false, "unknown host key"
    end
    if not ed25519.verify(key, messageString, base64.decode(response.signature)) then
        return false, "invalid signature"
    end
    return true
end

function vault.is_encrypted()
    return isEncryprted
end

local function simplest_crypt(a, b)
    assert(#a == #b, "#a ~= #b")
    local n = #a
    local result = {}
    for i=1, n do
        result[i] = bit.bxor(a:byte(i), b:byte(i))
    end
    return string.char(table.unpack(result))
end

function vault.encrypt_key(password)
    assert(not isEncryprted, "already encrypted")
    local content = open_private_key()
    local key = base64.decode(content.key)
    local salt = random.random(16)
    local hash = blake3.digest(salt..password)
    local encrypted = simplest_crypt(key, hash)
    local keyInfo = {
        encrypted = true;
        salt = base64.encode(salt);
        key = base64.encode(encrypted);
    }
    save_private_key(keyInfo)
    isEncryprted = true
end

function vault.private_key(password)
    local content = open_private_key()
    local encodedKey = base64.decode(content.key)
    if content.encrypted then
        if not password then
            return nil, "password required"
        end
        local salt = base64.decode(content.salt)
        local hash = blake3.digest(salt..password)
        local decrypted = simplest_crypt(encodedKey, hash)
        local actualPublicKey = ed25519.publicKey(decrypted)
        if publicKey ~= actualPublicKey then
            return nil, "wrong password"
        end
        return decrypted
    else
        return encodedKey
    end
end

function vault.decrypt_key(password)
    assert(isEncryprted, "not encrypted")
    local key, reason = vault.private_key(password)
    if not key then
        return key, reason
    end
    local keyInfo = {
        encrypted = false;
        key = base64.encode(key);
    }
    save_private_key(keyInfo)
    isEncryprted = false
    return true
end

function vault.make_auth_request(privateKey, session)
    local message = {
        session = session;
        key = base64.encode(publicKey);
    }
    local messageString = textutils.serialise(message, serializeOpts)
    local signature = ed25519.sign(privateKey, publicKey, messageString)
    return {
        message = messageString;
        signature = base64.encode(signature);
    }
end

function vault.get_name()
    return name
end

function vault.set_name(new_name)
    name = new_name
    save_public_key(publicKey, name)
end

----------------------------------------------------------

return vault
