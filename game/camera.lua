local camera = {}

function camera.new()
    local o = {}
    o.x = 0
    o.speed_x = 0

    o.set = camera.set
    o.update = camera.update

    return o
end

function camera:set()
    love.graphics.translate(self.x, 0)
end

function camera:update(dt)
    self.x = self.x + self.speed_x*dt
end

return camera
