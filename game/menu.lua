local utils = require "utils"
local gamestate = require "gamestate"
local player = require "player"
local particle = require "particle"

local menu = {}
menu.font = love.graphics.newFont("fonts/PressStart2P-Regular.ttf", 20)
menu.text = [[
'enter' to start game
'esc' to exit
]]

function menu.load(this_player)
    menu.width = love.graphics.getWidth()
    menu.height = love.graphics.getHeight()

    menu.player = this_player or player.new()

    menu.particles = {}
    for i=1,5000,1 do
        menu.particles[i] = particle.new()
    end
end

function menu.draw()
    love.graphics.setColor(1,1,1)
    love.graphics.printf(menu.text, menu.font, 0, 3*menu.height/4, menu.width, "center")
    love.graphics.setColor(1,0,0)
    love.graphics.printf(love.timer.getFPS(), 0, menu.height-12, menu.width, "right")
    for i=1,20,1 do
        menu.particles[i]:draw()
    end
end

function menu.update(dt)
    for i=1,20,1 do
        menu.particles[i]:update(dt)
    end
end

function menu.keypressed(key, scancode, isrepeat)
    if key == "return" then
        gamestate.switch("game", menu.player)
    elseif key == "escape" then
        love.event.quit(0)
    end
end

return menu
