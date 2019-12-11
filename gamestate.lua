local utils = require "utils"
local gamestate = {}

gamestate.states = {}

local null_func = function() end

local function assign(dest, callbacks)
    dest.load = callbacks.load or null_func
    dest.unload = callbacks.unload or null_func
    dest.update = callbacks.update or null_func
    dest.draw = callbacks.draw or null_func
    dest.keypressed = callbacks.keypressed or null_func
    dest.keyreleased = callbacks.keyreleased or null_func
    dest.mousepressed = callbacks.mousepressed or null_func
    dest.mousereleased = callbacks.mousereleased or null_func
end

function gamestate.register(name, callbacks)
    local new_entry = {}
    assign(new_entry, callbacks)
    gamestate.states[name] = new_entry
end

function gamestate.switch(name, objects)
    print("switch to " .. name)
    if gamestate.current then
        gamestate.current.unload()
    end
    gamestate.current = gamestate.states[name]
    assign(love, gamestate.current)
    gamestate.current.load(objects)
end

return gamestate
