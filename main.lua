local gamestate = require "gamestate"
local menu = require "menu"
local game = require "game"

function love.load()

    gamestate.register("menu", menu)
    gamestate.register("game", game)

    gamestate.switch("menu")
end
