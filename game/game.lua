local gamestate = require "gamestate"
local game = {}

local width = love.graphics.getWidth()
local height = love.graphics.getHeight()

function game.load(player)
    game.player = player
    game.player:stop()
end

function game.draw()
    game.player:draw()

    --fps
    love.graphics.setColor(1,0,0)
    love.graphics.printf(love.timer.getFPS(), 0, height-20, width, "right")
end

function game.update(dt)
    game.player:update(dt)
end

function game.keypressed(key, scancode, isrepeat)
    if key == "escape" then
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
