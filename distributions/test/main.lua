local concurrent = require 'concurrent'
local job = require 'job'
local gui = require 'gui'
local container = require 'container'
local task      = require 'task'

--[[
term.clear()
term.setCursorPos(1, 1)

local canvas = gui.canvas(7, 6)

-- canvas:fill(1, 1, 4, 1, colors.red)
-- canvas:blit(1, 1, "aaaa", "    ", "aaaa")
-- canvas:draw(term)
-- print()
-- canvas:blit(1, 1, "aaa", "   ", "444")
-- canvas:fill(1, 1, 3, 1, colors.blue)
--print()

--canvas:blit(2, 2, "!", "", "a")

canvas:fill(1, 1, 6, 6, colors.red)
canvas:fill(1, 1, 5, 1, colors.blue)

canvas:scroll(1)
canvas:scroll(-1)
--canvas:erase(2, 3, 2, 2)

local canvas2 = gui.canvas(4, 4)
canvas2:write(2, 2, "example", colors.green)

canvas:include(2, 3, canvas2)
canvas:draw(term)

-- print(textutils.serialise(canvas.background))
]]

-- local a = container.datum { 1, 2, nil, "string\t", n = 4, ["k e y"] = 3 }
-- local b = container.datum(textutils.unserialise(tostring(a)))
-- print(a == b, b)
-- print(container.datum({ result = container.result.success("yeah") }, true))

-- local pool = task.pool()
-- local t = pool:spawn(function()
--     error("err")
-- end)
-- t:start()
-- t:join()
-- pool:run()


job.run(function()
    -- local semaphore = concurrent.semaphore(3)

    -- for i=1, 10 do
    --     job.async(function()
    --         semaphore:with_lock(function()
    --             print("semaphore", i)
    --             sleep(1)
    --         end)
    --     end)
    -- end

    -- local write, read = concurrent.rw_mutex()

    -- job.async(function()
    --     write:with_lock(function()
    --         sleep(1)
    --         print("writer")
    --         sleep(1)
    --         print("writer2")
    --     end)
    -- end)

    -- job.async(function()
    --     read:with_lock(function()
    --         sleep(2)
    --         print("here")
    --     end)
    -- end)

    -- job.async(function()
    --     read:with_lock(function()
    --         sleep(1)
    --         print("there")
    --     end)
    -- end)

    -- job.async(function()
    --     read:with_lock(function()
    --         print("hmmm")
    --     end)
    -- end)

    -- job.async(function()
    --     local event = concurrent.event("testificate")
    --     local selected, args = concurrent.select(event, concurrent.timeout(2))
    --     if event == selected then
    --         print("event selected:", table.unpack(args))
    --     else
    --         print("timeout")
    --     end
    -- end)

    -- job.async(function()
    --     sleep(3)
    --     os.queueEvent("testificate", 42)
    --     print("done")
    -- end)

    print('before')
    local timeout = concurrent.timeout(3)
    concurrent.wait(34)
    print('after')
end)
