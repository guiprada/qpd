local gamestate = require "gamestate"
local game = {}

game.objects = {}

function game.draw()
    love.graphics.print("in game, have fun", 300, 300)
    love.graphics.print("'esc' to go to menu", 300, 310)
end

function game.keypressed(key, scancode, isrepeat)
    if key == "escape" then
        gamestate.switch("menu")
    end
end

return game
