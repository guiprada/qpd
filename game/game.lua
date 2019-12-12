local gamestate = require "gamestate"
local game = {}

function game.load(player)
    game.player = player
    game.player:stop()
end

function game.draw()
    game.player:draw()
end

function game.update(dt)
    game.player:update(dt)
end

function game.keypressed(key, scancode, isrepeat)
    if key == "escape" then
        print(game.objects)
        gamestate.switch("menu", game.player)
    elseif key == "left" then
        game.player:moving_left()
    elseif key == "right" then
        game.player:moving_right()
    elseif key == "up" then
        game.player:moving_up()
    elseif key == "down" then
        game.player:moving_down()
    end
end

function game.keyreleased(key, scancode, isrepeat)
    if key == "left" or key == "right" then
        game.player:slow_stop_x()
    elseif key == "up" or key == "down" then
        game.player:slow_stop_y()
    end
end

return game
