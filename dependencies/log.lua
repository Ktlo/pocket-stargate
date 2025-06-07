local string = string
local string_format = string.format
local type, error = type, error

local library = {}

----------------------------------------------------

--- @enum (keys) level
local levels = {
    'none', 'fatal', 'error', 'warning', 'info', 'debug', 'trace'
}

for int=1, #levels do
    levels[levels[int]] = int
end

library.levels = levels

----------------------------------------------------

local logger_methods = {}

--- @type fun(level: level, pattern: string, ...: any)
function logger_methods:write(level, pattern, ...)
    if type(level) == 'string' then
        level = levels[level]
    end
    if level <= self.writer.level then
        local message = string_format(pattern, ...)
        self.writer:write(level, message)
    end
end

local function logger_method(level)
    local level_id = levels[level]
    --- @type fun(self: logger, pattern: string, ...: any)
    logger_methods[level] = function(self, pattern, ...)
        if level_id <= self.writer.level then
            local message = string_format(pattern, ...)
            self.writer:write(level_id, message)
        end
    end
end

logger_method 'error'
logger_method 'warning'
logger_method 'info'
logger_method 'debug'
logger_method 'trace'

local fatal_level = levels.fatal

function logger_methods:fatal(pattern, ...)
    local message = string_format(pattern, ...)
    if fatal_level <= self.writer.level then
        self.writer:write(fatal_level, message)
    end
    error(message, 2)
end

local logger_meta = {
    __index = logger_methods;
}

--- @type fun(writer: writer): logger
function library.logger(writer)
    --- @class logger
    --- @field writer writer
    local logger = {
        writer = writer;
    }
    return setmetatable(logger, logger_meta)
end

----------------------------------------------------

return library
