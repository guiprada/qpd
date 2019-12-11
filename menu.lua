local gamestate = require "gamestate"

local menu = {}

menu.objects = {}

function menu.draw()
    love.graphics.print("menu", 300, 300)
    love.graphics.print("'enter' to start game", 300, 310)
    love.graphics.print("'esc' to quit", 300, 320)
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
