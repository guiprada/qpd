local gamestate = require "gamestate"
local game = {}

function game.load(objects)
    game.objects = {}
    nave = {}
    nave.img = love.graphics.newImage("nave.png")
    nave.x = 100
    nave.y = 100
    table.insert(game.objects, nave)

    if objects ~= nil then
        utils.array_append(game.objects, objects)
    end
end

function game.draw()
    love.graphics.print("in game, have fun", 300, 300)
    love.graphics.print("'esc' to go to menu", 300, 310)
    for key, value in pairs(game.objects) do
        love.graphics.draw(value.img, value.x, value.y)
    end
end

function game.keypressed(key, scancode, isrepeat)
    if key == "escape" then
        print(game.objects)
        gamestate.switch("menu", game.objects)
    end
end

return game
