local utils = require "utils"
local gamestate = require "gamestate"
local player = require "player"
local particle = require "particle"

local N_PARTICLES = 250

local menu = {}

local width = love.graphics.getWidth()
local height = love.graphics.getHeight()

menu.text_font = love.graphics.newFont("fonts/PressStart2P-Regular.ttf", 20)
menu.title_font = love.graphics.newFont("fonts/PressStart2P-Regular.ttf", 50)
menu.title_font_back = love.graphics.newFont("fonts/PressStart2P-Regular.ttf", 51)

menu.title = [[
Intergalatic
Farmer
]]
menu.text = [[
'enter' to start game
'esc' to exit
]]

function menu.load(this_player)
    menu.player = this_player or player.new()

    menu.particles = {}
    for i=1,N_PARTICLES,1 do
        menu.particles[i] = particle.new()
    end
end

function menu.draw()
    --particles
    for i=1,N_PARTICLES,1 do
        menu.particles[i]:draw()
    end

    --title
    love.graphics.setColor(1, 1, 0)
    love.graphics.printf(menu.title, menu.title_font_back, 0, height/4, width, "center" )
    love.graphics.setColor(0, 1, 1)
    love.graphics.printf(menu.title, menu.title_font, 0, 2+ height/4, width, "center" )

    --text
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(menu.text, menu.text_font, 0, 3*height/4, width, "center")

    --fps
    love.graphics.setColor(1, 0, 0)
    love.graphics.printf(love.timer.getFPS(), 0, height-12, width, "right")


end

function menu.update(dt)
    for i=1,N_PARTICLES,1 do
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
