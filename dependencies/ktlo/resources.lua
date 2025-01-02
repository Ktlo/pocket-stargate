local library = {}

--------------------------------

function library.load(filename)
    local file = io.open(filename, 'r')
    if file then
        local content = file:read('a')
        file:close()
        return content
    end
    return assert(RESOURCES and RESOURCES[filename], "resource \""..filename.."\" not found")
end

--------------------------------

return library
