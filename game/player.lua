local player = {}

local PLAYER_MAX_SPEED_X = 60
local PLAYER_MIN_SPEED_X = 30
local PLAYER_SPEED_Y = 100

local AIR_RESISTANCE_FACTOR = 80

local width = love.graphics.getWidth()
local height = love.graphics.getHeight()

local body_vertices = {
-- pos_x,pos_y, texture_x, texture_y, color_r, color_g, color_b, alpha
	{-20, -20,    0, 0,    0.8, 0.8, 1.0, 1.0},
	{-20,  20,    0, 0,    0.8, 0.8, 1.0, 1.0},
	{ 20,   0,    0, 0,    0.8, 0.8, 1.0, 1.0},
}

local wing_vertices = {
-- pos_x,pos_y, texture_x, texture_y, color_r, color_g, color_b, alpha
	{ -12, -12,    0, 0,    1.0, 0.3, 0.3, 1.0},
	{ -12,  12,    0, 0,    1.0, 0.3, 0.3, 1.0},
	{  12,   0,    0, 0,    1.0, 0.3, 0.3, 1.0},
}

local cockpit_vertices = {
-- pos_x,pos_y, texture_x, texture_y, color_r, color_g, color_b, alpha
	{ -6, -6,    0, 0,    0.3, 0.6, 1.0, 1.0},
	{ -6,  6,    0, 0,    0.3, 0.6, 1.0, 1.0},
	{  6,  6,    0, 0,    0.3, 0.6, 1.0, 1.0},
	{  6, -6,    0, 0,    0.3, 0.6, 1.0, 1.0},
}


local body_mesh = love.graphics.newMesh(body_vertices, "triangles", "static")
local wing_mesh = love.graphics.newMesh(wing_vertices, "triangles", "static")
local cockpit_mesh = love.graphics.newMesh(cockpit_vertices, "fan", "static")

local position_idle = {
	body_x = 0,
	body_y = 0,
	body_rotation = 0,

	u_wing_x =  -15,
	u_wing_y =  -20,
	u_wing_rotation = 0,

	d_wing_x = -15,
	d_wing_y =  20,
	d_wing_rotation = 0,

	cockpit_x = -5,
	cockpit_y = 0,
	cockpit_rotation = 0
}

local position_trust = {
	body_x = 0,
	body_y = 0,
	body_rotation = 0,

	u_wing_x =  -20,
	u_wing_y =  -20,
	u_wing_rotation = 0,

	d_wing_x = -20,
	d_wing_y =  20,
	d_wing_rotation = 0,

	cockpit_x = -5,
	cockpit_y = 0,
	cockpit_rotation = 0
}

function player:assign_position(position)
	self.body_x = position.body_x
	self.body_y = position.body_y
	self.body_rotation = position.body_rotation

	self.u_wing_x = position.u_wing_x
	self.u_wing_y = position.u_wing_y
	self.u_wing_rotation = position.u_wing_rotation

	self.d_wing_x = position.d_wing_x
	self.d_wing_y =  position.d_wing_y
	self.d_wing_rotation = position.d_wing_rotation

	self.cockpit_x = position.cockpit_x
	self.cockpit_y = position.cockpit_y
	self.cockpit_rotation = position.cockpit_rotation
end

function player.new(x, y)
    local o = {}

	o.x = x or (width/2)
	o.y = y or (height/2)
	o.rotation = 0

	o.body = body_mesh
	o.u_wing = wing_mesh
	o.d_wing = wing_mesh
	o.cockpit = cockpit_mesh


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
	o.assign_position = player.assign_position

	o:assign_position(position_idle)
    return o
end

function player:draw()
	-- body
	love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.body, self.x + self.body_x, self.y + self.body_y, self.rotation + self.body_rotation)

	-- u_wing
	love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.u_wing, self.x + self.u_wing_x, self.y + self.u_wing_y, self.rotation + self.u_wing_rotation)

	-- d_wing
	love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.d_wing, self.x + self.d_wing_x, self.y + self.d_wing_y, self.rotation + self.d_wing_rotation)

	-- cockpit
	love.graphics.setColor(1, 1, 1)
    love.graphics.draw(self.cockpit, self.x + self.cockpit_x, self.y + self.cockpit_y, self.rotation + self.cockpit_rotation)
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
        if self.speed_x > PLAYER_MIN_SPEED_X and self.speed_x - air_resistance > PLAYER_MIN_SPEED_X then
            self.speed_x = self.speed_x - air_resistance
        elseif self.speed_x < PLAYER_MIN_SPEED_X and self.speed_x +  air_resistance < -PLAYER_MIN_SPEED_X then
            self.speed_x = self.speed_x + air_resistance
        else
            self.speed_x = PLAYER_MIN_SPEED_X
        end
    end

    self.x = self.x + self.speed_x*dt
    self.y = self.y + self.speed_y*dt
end

function player:moving_left()
    self.is_moving_x = true
    self.speed_x = -PLAYER_MAX_SPEED_X
end

function player:moving_right()
	self:assign_position(position_trust)
    self.is_moving_x = true
    self.speed_x = PLAYER_MAX_SPEED_X
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
	self:assign_position(position_idle)
    self.is_moving_x = false
end

function player:slow_stop_y()
    self.is_moving_y = false
end

function player:stop()
    self.is_moving_x = false
    self.speed_x = PLAYER_MIN_SPEED_X

    self.is_moving_y = false
    self.speed_y = PLAYER_MIN_SPEED_X
end

return player
