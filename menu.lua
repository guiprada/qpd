local utils = require "utils"
local gamestate = require "gamestate"

local menu = {}

function menu.load(objects)
    menu.objects = {}
    if objects ~= nil then
        utils.array_append(menu.objects, objects)
    end
end

function menu.draw()
    love.graphics.print("menu", 300, 300)
    love.graphics.print("'enter' to start game", 300, 310)
    love.graphics.print("'esc' to quit", 300, 320)
    for key, value in pairs(menu.objects) do
        love.graphics.draw(value.img, value.x, value.y)
    end
end

function menu.keypressed(key, scancode, isrepeat)
    print(key)
    if key == "return" then
        gamestate.switch("game")
    elseif key == "escape" then
        love.event.quit(0)
    end
end

return menu
