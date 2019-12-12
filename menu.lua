local utils = require "utils"
local gamestate = require "gamestate"
local player = require "player"

local menu = {}

menu.text = [[
    'enter' to start game
    'esc' to exit
]]

function menu.load(this_player)
    menu.width = love.graphics.getWidth()
    menu.height = love.graphics.getHeight()

    print(this_player)
    menu.player = this_player or player.new()
end

function menu.draw()
    love.graphics.printf(menu.text, 0, 3*menu.height/4, menu.width, "center")
end

function menu.keypressed(key, scancode, isrepeat)
    if key == "return" then
        gamestate.switch("game", menu.player)
    elseif key == "escape" then
        love.event.quit(0)
    end
end

return menu
