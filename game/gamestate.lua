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
    dest.displayrotated = callbacks.displayrotated or null_func
    dest.errorhandler = callbacks.errorhandler or null_func
    dest.lowmemory = callbacks.lowmemory or null_func
    dest.quit = callbacks.quit or null_func
    dest.run = callbacks.run or null_func
    dest.threaderror = callbacks.threaderror or null_func
    dest.directorydropped = callbacks.directorydropped or null_func
    dest.filedropped = callbacks.filedropped or null_func
    dest.focus = callbacks.focus or null_func
    dest.mousefocus = callbacks.mousefocus or null_func
    dest.resize = callbacks.resize or null_func
    dest.visible = callbacks.visible or null_func
    dest.textedited = callbacks.textedited or null_func
    dest.textinput = callbacks.textinput or null_func
    dest.mousemoved = callbacks.mousemoved or null_func
    dest.mousepressed = callbacks.mousepressed or null_func
    dest.mousereleased = callbacks.mousereleased or null_func
    dest.wheelmoved = callbacks.wheelmoved or null_func
    dest.gamepadaxis = callbacks.gamepadaxis or null_func
    dest.gamepadpressed = callbacks.gamepadpressed or null_func
    dest.gamepadreleased = callbacks.gamepadreleased or null_func
    dest.joystickadded = callbacks.joystickadded or null_func
    dest.joystickaxis = callbacks.joystickaxis or null_func
    dest.joystickhat = callbacks.joystickhat or null_func
    dest.joystickpressed = callbacks.joystickpressed or null_func
    dest.joystickreleased = callbacks.joystickreleased or null_func
    dest.joystickremoved = callbacks.joystickremoved or null_func
    dest.touchmoved = callbacks.touchmoved or null_func
    dest.touchpressed = callbacks.touchpressed or null_func
    dest.touchreleased = callbacks.touchreleased or null_func
end

function gamestate.register(name, callbacks)
    local new_entry = {}
    assign(new_entry, callbacks)
    gamestate.states[name] = new_entry
end

function gamestate.switch(name, object)
    if gamestate.current then
        gamestate.current.unload()
    end
    gamestate.current = gamestate.states[name]
    assign(love, gamestate.current)
    gamestate.current.load(object)
end

return gamestate
