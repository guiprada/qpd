local gamestate = require "gamestate"
local camera = require "camera"
local particle = require "particle"

local N_PARTICLES = 500

local game = {}

local width = love.graphics.getWidth()
local height = love.graphics.getHeight()

function game.load(player)
    game.player = player
    game.player.x = 100
    game.player.y = height/2
    game.player:stop()

    game.camera = camera.new()
    game.camera.x = 0
    game.camera.speed_x = -30

    game.particles = {}
    for i=1,N_PARTICLES,1 do
        game.particles[i] = particle.new(game.camera)
    end
end

function game.draw()
    --fps
    love.graphics.setColor(1,0,0)
    love.graphics.printf(love.timer.getFPS(), 0, height-12, width, "right")

    game.camera:set()

    --particles
    for i=1,N_PARTICLES,1 do
        game.particles[i]:draw()
    end

    game.player:draw()


end

function game.update(dt)
    game.camera:update(dt)

    for i=1,N_PARTICLES,1 do
        game.particles[i]:update(dt)
    end

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
