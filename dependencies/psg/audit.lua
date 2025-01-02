AUDIT_DIRECTORY="audit"
EVENT_TABLE="event"

-------------------------------------------

if fs.exists(AUDIT_DIRECTORY) then
    fs.makeDir(AUDIT_DIRECTORY)
end

local audit = {}

local function timestamp()
    return os.date("%Y-%m-%dT%H:%M:%SZ")
end

local COMA = (','):byte(1)

local function parse_csv(str)
    local i,j, n = 1, 1, #str
    local result = {}
    while j <= n do
        local c = str:byte(j)
        if c == COMA then
            local text
            if i == j - 1 then
                text = ""
            else
                text = str:sub(i, j - 1)
            end
            table.insert(result, text)
            j = j + 1
            i = j
        else
            j = j + 1
        end
    end
    local text
    if i == j then
        text = ""
    else
        text = str:sub(i, j)
    end
    table.insert(result, text)
    return result
end

local function table_to_csv(tab)
    return table.concat(tab, ",")
end

local function makeFilename(event)
    return AUDIT_DIRECTORY.."/"..event..".csv"
end

local function append_to_file(filename, data)
    local file = assert(io.open(filename, 'a'))
    file:write(table_to_csv(data))
    file:write('\n')
    file:close()
end

local function define_schemaless(event, headers)
    local filename = makeFilename(event)
    if not fs.exists(filename) then
        append_to_file(filename, headers)
    end
end

local eventHeaders = {'timestamp', 'type'}

define_schemaless(EVENT_TABLE, eventHeaders)

local function read_back_line(file, location)
    for pos=location-1, 0, -1 do
        file:seek("set", pos)
        local c = file:read(1)
        if c == '\n' then
            local line = file:read('l')
            file:seek("set", pos)
            return line, pos
        end
    end
    return nil, 0
end

local function setup_head(event)
    local file = assert(io.open(makeFilename(event)))
    assert(file:read('l'))
    return file
end

local function setup_tail(event)
    local file = assert(io.open(makeFilename(event)))
    local location = file:seek("end")
    return file, location - 1
end

local schema = {}

-------------------------------------------

audit.parse_csv = parse_csv

function audit.define(event, headers)
    define_schemaless(event, headers)
    schema[event] = headers
end

function audit.save(event, record)
    local headers = assert(schema[event])
    local t = timestamp()
    append_to_file(makeFilename(EVENT_TABLE), {t, event})
    local data = {}
    for i, header in ipairs(headers) do
        data[i] = tostring(record[header])
    end
    append_to_file(makeFilename(event), data)
    return t
end

local function audit_read(setup_file, read_line, skip, size)
    local mainFile, mainLocation = setup_file(EVENT_TABLE)
    local files = {}
    for event, headers in pairs(schema) do
        local file, location = setup_file(event)
        local context = {
            file = file;
            location = location;
            headers = headers;
        }
        files[event] = context
    end
    local result, line = {}, nil
    for i=1, skip+size do
        line, mainLocation = read_line(mainFile, mainLocation)
        if not line then
            break
        end
        local data = parse_csv(line)
        local type = data[2]
        local context = files[type]
        if i <= skip then
            _, context.location = assert(read_line(context.file, context.location))
        else
            local record = {
                timestamp=data[1];
                event=type;
            }
            line, context.location = assert(read_line(context.file, context.location))
            data = parse_csv(line)
            for j, header in ipairs(context.headers) do
                record[header] = data[j]
            end
            table.insert(result, record)
        end
    end
    for _, context in pairs(files) do
        context.file:close()
    end
    return result
end

local function read_line_head(file)
    return file:read('l')
end

function audit.head(skip, size)
    return audit_read(setup_head, read_line_head, skip, size)
end

function audit.tail(skip, size)
    return audit_read(setup_tail, read_back_line, skip, size)
end

local function copy_content(event, file, headers)
    local filename = makeFilename(event)
    local tmpfile = filename..".tmp"
    local out = assert(io.open(tmpfile, 'w'))
    out:write(table_to_csv(headers))
    out:write('\n')
    for chunk in file:lines(4096) do
        out:write(chunk)
    end
    file:close()
    out:close()
    fs.delete(filename)
    fs.move(tmpfile, filename)
end

function audit.erase(count)
    local mainFile = setup_head(EVENT_TABLE)
    local files = {}
    for event, headers in pairs(schema) do
        local file = setup_head(event)
        local context = {
            file = file;
            headers = headers;
        }
        files[event] = context
    end
    local line
    for i=1, count do
        line = mainFile:read('l')
        if not line then
            break
        end
        local data = parse_csv(line)
        local type = data[2]
        local context = files[type]
        assert(context.file:read('l'))
    end
    copy_content(EVENT_TABLE, mainFile, eventHeaders)
    for event, context in pairs(files) do
        copy_content(event, context.file, context.headers)
    end
end

-------------------------------------------

return audit
