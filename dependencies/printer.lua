local printer = peripheral.find 'printer'

local library = {}

function library.exists()
    return printer and true or false
end

local print_index = {}

function print_index:write_line(from, to)
    local y = self.y
    assert(y <= self.height)
    printer.setCursorPos(1, y)
    local text = self.text
    printer.write(text:sub(from, to))
    self.y = y + 1
    local pos = to + 1
    if pos > #text then
        self.done = true
    end
    self.pos = pos
end

function print_index:continue()
    while true do
        local state = self.state
        if state == 'empty' then
            if self.done then
                return true
            end
            if not printer.newPage() then
                return false, 'not enough ink or paper'
            end
            printer.setPageTitle(self.title)
            self.y = 1
            self.state = 'page'
            local width, height = printer.getPageSize()
            self.width = width
            self.height = height
        elseif state == 'page' then
            local y = self.y
            local height = self.height
            if y > height or self.done then
                if not printer.endPage() then
                    return false, 'not enough space for printed page'
                end
                self.state = 'empty'
            else
                local text = self.text
                local pos = self.pos
                local width = self.width
                local size = #text
                local subtext = text:sub(1, pos+width)
                local newLine = string.find(subtext, '\n', pos, true)
                if size < pos+width and not newLine then
                    self:write_line(pos, size)
                else
                    if newLine then
                        self:write_line(pos, newLine)
                    else
                        local _, whitespace = string.find(subtext, '.*(%s)', pos)
                        if whitespace then
                            self:write_line(pos, whitespace)
                        else
                            self:write_line(pos, pos+width-1)
                        end
                    end
                end
            end
        elseif state == 'cancel' then
            error('Operation cancelled', 2)
        end
    end
end

function print_index:cancel()
    if self.state == 'page' then
        printer.endPage()
    end
    self.state = 'cancel'
end

local print_meta = {
    __index = print_index;
}

function library.print(title, text)
    local state = {
        title = title;
        state = 'empty';
        text = text;
        pos = 1;
        y = 1;
        done = false;
    }
    return setmetatable(state, print_meta)
end

return library
