local player = {}

local PLAYER_MAX_SPEED_X = 500
local PLAYER_MIN_SPEED_X = 50
local PLAYER_MAX_SPEED_Y = 120
local PLAYER_ACCEL_X = 200
local PLAYER_ACCEL_Y = 1000

local AIR_RESISTANCE_FACTOR = 50

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

local position_brake = {
	body_x = 0,
	body_y = 0,
	body_rotation = 0,

	u_wing_x =  -10,
	u_wing_y =  -20,
	u_wing_rotation = 0,

	d_wing_x = -10,
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
	o.accel_x = 0
    o.accel_y = 0

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
	local air_resistance = dt * AIR_RESISTANCE_FACTOR

	self.speed_x = self.speed_x + self.accel_x*dt - air_resistance
	if self.speed_x > PLAYER_MAX_SPEED_X then self.speed_x = PLAYER_MAX_SPEED_X
	elseif self.speed_x < PLAYER_MIN_SPEED_X then self.speed_x = PLAYER_MIN_SPEED_X end

	if self.speed_y > 0 then
		self.speed_y = self.speed_y + self.accel_y*dt - air_resistance
		if self.speed_y > PLAYER_MAX_SPEED_Y then
			self.speed_y = PLAYER_MAX_SPEED_Y
		elseif self.speed_y < 0 then --mudou de sinal
			self.speed_y = 0
		end
	elseif self.speed_y < 0 then
		self.speed_y = self.speed_y + self.accel_y*dt + air_resistance
		if -self.speed_y > PLAYER_MAX_SPEED_Y then
			self.speed_y = -PLAYER_MAX_SPEED_Y
		elseif self.speed_y > 0 then --mudou de sinal
			self.speed_y = 0
		end
	else
		self.speed_y = self.speed_y + self.accel_y*dt
	end

	-- if self.speed_y > 0 then
	-- 	self.speed_y = self.speed_y + self.accel_y*dt - air_resistance
	-- 	if self.speed_y > PLAYER_MAX_SPEED_Y then
	-- 		self.speed_y = PLAYER_MAX_SPEED_Y
	-- 	end
	-- else
	-- 	self.speed_y = self.speed_y + self.accel_y*dt + air_resistance
	-- 	if -self.speed_y > PLAYER_MAX_SPEED_Y then
	-- 		self.speed_y = -PLAYER_MAX_SPEED_Y
	-- 	end
	-- end

    self.x = self.x + self.speed_x*dt
    self.y = self.y + self.speed_y*dt

	if self.y > height then
		self.y = height
		self.accel_y = 0
		self.speed_y = 0
	elseif self.y < 0 then
		self.y = 0
		self.accel_y = 0
		self.speed_y = 0
	end

end

function player:moving_left()
	self:assign_position(position_brake)
    self.accel_x = -PLAYER_ACCEL_X
end

function player:moving_right()
	self:assign_position(position_trust)
	self.accel_x = PLAYER_ACCEL_X
end

function player:moving_up()
    self.accel_y = -PLAYER_ACCEL_Y
end

function player:moving_down()
    self.accel_y = PLAYER_ACCEL_Y
end

function player:slow_stop_x()
	self:assign_position(position_idle)
	self.accel_x = 0
end

function player:slow_stop_y()
    self.accel_y = 0
end

function player:stop()
    self.speed_x = PLAYER_MIN_SPEED_X
	self.speed_y = 0
	self.accel_x = 0
	self.accel_y = 0

end

return player
