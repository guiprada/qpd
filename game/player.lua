local player = {}

local PLAYER_SPEED_X = 60
local PLAYER_SPEED_Y = 100

local AIR_RESISTANCE_FACTOR = 80

local vertices = {
-- pos_x,pos_y, texture_x, texture_y, color_r, color_g, color_b, alpha
	{0, 0,  0,0, 0,0.2,0.2,1.0},
	{20,0,  0,0, 0,1.0,0.2,1.0},
	{20,20, 0,0, 0,0.2,1.0,1.0},

    {0, 0,  0,0, 0,0.2,0.2,1.0},
	{0,20,  0,0, 0,1.0,0.2,1.0},
	{20,20, 0,0, 0,0.2,1.0,1.0},
}

local mesh = love.graphics.newMesh(vertices, "triangles", "static")

function player.new()
    local o = {}
    o.mesh = mesh
    o.x = 300
    o.y = 300
    o.speed_x = 0
    o.speed_y = 0
    o.is_moving_x = false
    o.is_moving_y = false

    -- callbacks
    o.draw = player.draw
    o.update = player.update
    o.moving_left = player.moving_left
    o.moving_right = player.moving_right
    o.moving_up = player.moving_up
    o.moving_down = player.moving_down
    o.slow_stop_x = player.slow_stop_x
    o.slow_stop_y = player.slow_stop_y
    o.stop = player.stop
    return o
end

function player:draw()
    --love.graphics.printf("player", 0, 300, 300, "center")
    love.graphics.draw(self.mesh, self.x, self.y)
end

function player:update(dt)
    if not self.is_moving_y then
        local distance = dt * self.speed_y
        local air_resistance = dt * AIR_RESISTANCE_FACTOR
        if self.speed_y > 0 and self.speed_y > air_resistance then
            self.speed_y = self.speed_y - air_resistance
        elseif self.speed_y < 0 and self.speed_y < air_resistance then
            self.speed_y = self.speed_y + air_resistance
        else
            self.speed_y = 0
        end
    end
    if not self.is_moving_x then
        local distance = dt * self.speed_x
        local air_resistance = dt * AIR_RESISTANCE_FACTOR
        if self.speed_x > 0 and self.speed_x > air_resistance then
            self.speed_x = self.speed_x - air_resistance
        elseif self.speed_x < 0 and self.speed_x < air_resistance then
            self.speed_x = self.speed_x + air_resistance
        else
            self.speed_x = 0
        end
    end

    self.x = self.x + self.speed_x*dt
    self.y = self.y + self.speed_y*dt
end

function player:moving_left()
    self.is_moving_x = true
    self.speed_x = -PLAYER_SPEED_X
end

function player:moving_right()
    self.is_moving_x = true
    self.speed_x = PLAYER_SPEED_X
end

function player:moving_up()
    self.is_moving_y = true
    self.speed_y = -PLAYER_SPEED_Y
end

function player:moving_down()
    self.is_moving_y = true
    self.speed_y = PLAYER_SPEED_Y
end

function player:slow_stop_x()
    self.is_moving_x = false
end

function player:slow_stop_y()
    self.is_moving_y = false
end

function player:stop()
    self.is_moving_x = false
    self.speed_x = 0

    self.is_moving_y = false
    self.speed_y = 0
end

return player
