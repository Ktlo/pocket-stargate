local expect = require "cc.expect"
local expect, field, range = expect.expect, expect.field, expect.range

local os_pullEvent, os_startTimer = os.pullEvent, os.startTimer
local huge = math.huge
local peripheral_getName, peripheral_isPresent, peripheral_hasType = peripheral.getName, peripheral.isPresent, peripheral.hasType
local type, setmetatable = type, setmetatable
local term = term
local term_current, term_native = term.current, term.native()
local debug_getupvalue = debug.getupvalue
local table_insert, table_move, table_remove = table.insert, table.move, table.remove
local string_sub, string_rep, string_gsub, string_find = string.sub, string.rep, string.gsub, string.find
local colors_toBlit, colors_fromBlit = colors.toBlit, colors.fromBlit

------------------------------------------------------------

local function check_peripheral(peripheral, kind)
    if type(peripheral) == 'table' then
        peripheral = peripheral_getName(peripheral)
    end
    if not peripheral_isPresent(peripheral) then
        error("peripheral \""..tostring(peripheral).."\" not present", 2)
    end
    if not peripheral_hasType(kind) then
        error("peripheral \""..tostring(peripheral).."\" has no type \""..kind.."\"", 2)
    end
    return peripheral
end

------------------------------------------------------------

local mouse_events = {
    mouse_click = 'down';
    mouse_drag = 'drag';
    mouse_scroll = 'scroll';
    mouse_up = 'up';
}

local function getupvalue_by_name(f, name)
    for i = 2, huge do
        local key, value = debug_getupvalue(f, i)
        if key == name then
            return value
        end
        if not key then
            return nil
        end
    end
end

local function window_parent(window)
    local internalBlit = getupvalue_by_name(window.write, "internalBlit")
    local redrawLine = getupvalue_by_name(internalBlit, "redrawLine")
    return getupvalue_by_name(redrawLine, "parent")
end

local function get_event_parameters(window)
    local x_offset = 0
    local y_offset = 0
    if window == term then
        window = term_current()
    end
    local width, height = window.getSize()
    while true do
        local getPosition = window.getPosition
        if not getPosition then
            break
        end
        local x, y = getPosition()
        x_offset = x_offset + x - 1
        y_offset = y_offset + y - 1
        window = window_parent(window)
    end
    local device
    if term_native == window then
        device = nil
    else
        device = peripheral_getName(window)
    end
    return device, x_offset, y_offset, width, height
end

local function dynamic_event_source(window)
    expect(1, window, 'table', 'nil')
    window = window or term_current()
    local isVisible = window.isVisible
    local queue = {}
    return function()
        while true do
            local event, special, x, y = os_pullEvent()
            if not isVisible or isVisible() then
                local device, x_offset, y_offset, width, height = get_event_parameters(window)
                if not device then
                    local remapped_event = mouse_events[event]
                    if remapped_event then
                        x = x - x_offset
                        y = y - y_offset
                        if x > 0 and y > 0 and x <= width and y <= height then
                            return remapped_event, x, y, special
                        end
                    end
                else
                    if event == 'monitor_touch' and special == device then
                        x = x - x_offset
                        y = y - y_offset
                        if x > 0 and y > 0 and x <= width and y <= height then
                            local timer = os_startTimer(0.1)
                            queue[timer] = { x, y }
                            return 'down', x, y, 1
                        end
                    elseif event == 'monitor_resize' and special == device then
                        return 'device_resize'
                    elseif event == 'timer' then
                        local context = queue[special]
                        if context then
                            queue[special] = nil
                            return 'up', context[1], context[2], 1
                        end
                    end
                end
            end
        end
    end
end

local event_source = {
    dynamic = dynamic_event_source;
}

------------------------------------------------------------

local canvas_index = {}

function canvas_index:clear()
    if next(self.text) then
        self.text = {}
        self.foreground = {}
        self.background = {}
        self.updated = true
    end
end

function canvas_index:trim()
    local text = self.text
    local foreground = self.foreground
    local background = self.background
    local width = self.width
    local height = self.height
    local y_offset = self.y_offset
    local x_offset = self.x_offset
    local y_limit = height + y_offset
    local updated = self.updated
    if #text > y_limit then
        for i=#text, y_limit + 1, -1 do
            text[i] = nil
            foreground[i] = nil
            background[i] = nil
        end
        updated = true
    end
    if y_offset > 0 then
        local from = y_offset + 1
        table_move(text, from, height, 1)
        table_move(foreground, from, height, 1)
        table_move(background, from, height, 1)
        self.y_offset = 0
        updated = true
    end
    for i=1, height do
        local text_row = text[i]
        local n = #text_row
        if x_offset ~= 0 or n > width then
            local foreground_row = foreground[i]
            local background_row = background[i]
            if width > 0 then
                local from = x_offset + 1
                local to = x_offset + width
                text[i] = string_sub(text_row, from, to)
                foreground[i] = string_sub(foreground_row, from, to)
                background[i] = string_sub(background_row, from, to)
            else
                text[i] = ""
                foreground[i] = ""
                background[i] = ""
            end
            updated = true
        end
    end
    self.x_offset = 0
    self.updated = updated
end

local function canvas_shift(self, x, y)
    local text_list = self.text
    local text_foreground = self.foreground
    local text_background = self.background
    if x <= 0 then
        local new_x_offset = -x + 1
        local old_x_offset = self.x_offset
        if new_x_offset > old_x_offset then
            local x_offset_diff = new_x_offset - old_x_offset
            for i=1, #text_list do
                local text_row = text_list[i]
                if text_row ~= "" then
                    local space = string_rep(" ", x_offset_diff)
                    text_list[i] = space..text_row
                    text_foreground[i] = space..text_foreground[i]
                    text_background[i] = space..text_background[i]
                end
            end
            self.x_offset = new_x_offset
        end
    end
    if y <= 0 then
        local new_y_offset = -y + 1
        local old_y_offset = self.y_offset
        if new_y_offset > old_y_offset then
            local y_offset_diff = new_y_offset - old_y_offset
            for i=1, y_offset_diff do
                table_insert(text_list, i, "")
                table_insert(text_foreground, i, "")
                table_insert(text_background, i, "")
            end
            self.y_offset = new_y_offset
        end
    end
end

local function canvas_prepend(self, y)
    local text = self.text
    local foreground = self.foreground
    local background = self.background
    local size = #text
    local cy = y + self.y_offset
    if cy > size then
        for i=size + 1, cy do
            text[i] = ""
            foreground[i] = ""
            background[i] = ""
        end
    end
end

local function insert_into_row(row, segment, x)
    local row_size = #row
    local segment_size = #segment
    local beginning
    local offset = x - 1
    if offset > row_size then
        beginning = row..string_rep(" ", offset - row_size)
    else
        beginning = string_sub(row, 1, offset)
    end
    local segment_end = segment_size + x
    local ending
    if row_size >= segment_end then
        ending = string_sub(row, segment_end)
    else
        ending = ""
    end
    return string_gsub(beginning..segment..ending, "%s*$", "")
end

local function canvas_blit(self, x, y, text, foreground, background)
    local cx = x + self.x_offset
    local cy = y + self.y_offset
    self.text[cy] = insert_into_row(self.text[cy], text, cx)
    self.foreground[cy] = insert_into_row(self.foreground[cy], foreground, cx)
    self.background[cy] = insert_into_row(self.background[cy], background, cx)
    self.updated = true
end

function canvas_index:blit(x, y, text, foreground, background)
    local size = #text
    if size ~= #foreground and size ~= #background then
        error("Arguments must be the same length", 2)
    end
    if size == 0 then
        return
    end
    canvas_shift(self, x, y)
    canvas_prepend(self, y)
    canvas_blit(self, x, y, text, foreground, background)
end

local function canvas_extract_segment(self, list, x, y, size)
    local pos = self.x_offset + x
    local segment = string_sub(self[list][self.y_offset + y] or "", pos, pos + size - 1)
    local segment_size = #segment
    if segment_size < size then
        segment = segment..string_rep(" ", size - segment_size)
    end
    return segment
end

function canvas_index:write(x, y, text, color)
    local size = #text
    if size == 0 then
        return
    end
    canvas_shift(self, x, y)
    canvas_prepend(self, y)
    local background = canvas_extract_segment(self, "background", x, y, size)
    canvas_blit(self, x, y, text, string_rep(colors_toBlit(color), size), background)
end

function canvas_index:fill(x, y, dx, dy, color)
    if dx == 0 or dy == 0 then
        return
    end
    canvas_shift(self, x, y)
    local cy = y + dy - 1
    canvas_prepend(self, cy)
    local background_segment = string_rep(colors_toBlit(color), dx)
    for i=y, cy do
        local text_segment = canvas_extract_segment(self, "text", x, y, dx)
        local foreground_segment = canvas_extract_segment(self, "foreground", x, y, dx)
        canvas_blit(self, x, i, text_segment, foreground_segment, background_segment)
    end
end

function canvas_index:erase(x, y, dx, dy)
    if dx == 0 or dy == 0 then
        return
    end
    canvas_shift(self, x, y)
    local cy = y + dy - 1
    canvas_prepend(self, cy)
    local space = string_rep(" ", dx)
    for i=y, cy do
        canvas_blit(self, x, i, space, space, space)
    end
end

local function canvas_remove_redundant_rows(self)
    local y_offset = self.y_offset
    local text = self.text
    local foreground = self.foreground
    local background = self.background
    local counter = 1
    local size = #text
    while y_offset > 0 and text[counter] == "" and foreground[counter] == "" and background[counter] == "" do
        y_offset = y_offset - 1
        counter = counter + 1
    end
    self.y_offset = y_offset
    local new_size = size - counter + 1
    table_move(text, counter, new_size, 1)
    table_move(foreground, counter, new_size, 1)
    table_move(background, counter, new_size, 1)
    for i=new_size + 1, size do
        text[i] = nil
        foreground[i] = nil
        background[i] = nil
    end
end

function canvas_index:scroll(dy)
    if dy == 0 then
        return
    end
    if dy > 0 then
        self.y_offset = self.y_offset + dy
    else
        local text = self.text
        local foreground = self.foreground
        local background = self.background
        for i=1, -dy do
            table_insert(text, 1, "")
            table_insert(foreground, 1, "")
            table_insert(background, 1, "")
        end
    end
    canvas_remove_redundant_rows(self)
    self.updated = true
end

local function canvas_get_element(self, name, x, y)
    x = x + self.x_offset
    y = y + self.y_offset
    local list = self[name][y]
    if not list then
        return nil
    end
    local symbol = string_sub(list, x, x)
    if symbol == "" or symbol == " " then
        return nil
    end
    return symbol
end

function canvas_index:get_char(x, y)
    return canvas_get_element(self, "text", x, y)
end

function canvas_index:get_fg(x, y)
    local symbol = canvas_get_element(self, "foreground", x, y)
    if symbol then
        return colors_fromBlit(symbol)
    else
        return nil
    end
end

function canvas_index:get_bg(x, y)
    local symbol = canvas_get_element(self, "background", x, y)
    if symbol then
        return colors_fromBlit(symbol)
    else
        return nil
    end
end

local function string_replace(text, pattern, action)
    local offset = 1
    local indexes = {}
    while true do
        local from, to = string_find(text, pattern, offset)
        if not from then
            break
        end
        table_insert(indexes, from)
        table_insert(indexes, to)
        offset = to + 1
    end
    local i = 1
    return string_gsub(text, pattern, function(segment)
        local from, to = indexes[i], indexes[i + 1]
        i = i + 2
        return action(from, to, segment)
    end)
end

local function canvas_draw(self, x, y, txt, fg_color, bg_color, blit)
    local width = self.width
    for i=1, self.height do
        local text_segment = string_replace(canvas_extract_segment(self, "text", 1, i, width), " ", function(f,_,s) return txt(f, i, s) end)
        local foreground_segment = string_replace(canvas_extract_segment(self, "foreground", 1, i, width), " ", function(f,_,s) return fg_color(f, i, s) end)
        local background_segment = string_replace(canvas_extract_segment(self, "background", 1, i, width), " ", function(f,_,s) return bg_color(f, i, s) end)
        blit(x, y + i - 1, text_segment, foreground_segment, background_segment)
    end
end

function canvas_index:draw(window)
    local fg_color = colors_toBlit(window.getTextColor())
    local bg_color = colors_toBlit(window.getBackgroundColour())
    local x, y = window.getCursorPos()
    canvas_draw(self, x, y,
        function(_, _, s) return s end,
        function() return fg_color end,
        function() return bg_color end,
        function (ax, ay, text, foreground, background)
            window.setCursorPos(ax, ay)
            window.blit(text, foreground, background)
        end
    )
end

function canvas_index:include(x, y, canvas)
    local txt = function(dx, dy)
        return canvas_get_element(self, "text", x + dx - 1, y + dy - 1) or " "
    end
    local fg_color = function(dx, dy)
        return canvas_get_element(self, "foreground", x + dx - 1, y + dy - 1) or " "
    end
    local bg_color = function(dx, dy)
        return canvas_get_element(self, "background", x + dx - 1, y + dy - 1) or " "
    end
    canvas_draw(canvas, x, y, txt, fg_color, bg_color, function (ax, ay, text, foreground, background)
        self:blit(ax, ay, text, foreground, background)
    end)
end

function canvas_index:reset()
    self.updated = false
end

function canvas_index:resize(width, height)
    self.width = width
    self.height = height
end

local canvas_meta = {
    __index = canvas_index;
}

local function canvas_create(width, height)
    local canvas = {
        width = width;
        height = height;
        x_offset = 0;
        y_offset = 0;
        updated = false;
        text = {};
        foreground = {};
        background = {};
    }
    return setmetatable(canvas, canvas_meta)
end

------------------------------------------------------------

local theme_index = {}

function theme_index:add(selector)
    
end

local theme_meta = {
    __index = theme_index;
}

local function create_theme()
    local theme = {
        records = {};
    }
    return setmetatable(theme, theme_meta)
end

------------------------------------------------------------

local frame_index = {}

local frame_meta = {
    __index = frame_index;
}

local function frame_create(window, element, event_source)
    window = window or term_current()
    event_source = event_source or dynamic_event_source(window)
end

------------------------------------------------------------

return {
    event_source = event_source;
    canvas = canvas_create;
    frame = frame_create;
}
