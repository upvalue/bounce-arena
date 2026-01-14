local tiny = require("lib.tiny")
local input = require("input")
local events = require("events")

--[[
Components (just table fields - documented here for reference):

Position:      { x, y }
Velocity:      { vx, vy }
Health:        { current, max }
Collider:      { radius }
SeeksTarget:   { target, speed }
Bounces:       { }  (flag component)
Lifetime:      { remaining }
DamagesPlayer: { amount }
DamagesEnemy:  { amount }
PlayerInput:   { speed }  (flag + config)
Render:        { type="circle", color={r,g,b}, radius }
]]

local systems = {}

-- Movement system: applies velocity to position
systems.movement = tiny.processingSystem()
systems.movement.filter = tiny.requireAll("x", "y", "vx", "vy")
function systems.movement:process(e, dt)
    e.x = e.x + e.vx * dt
    e.y = e.y + e.vy * dt
end

-- Player input system: handles keyboard input
systems.playerInput = tiny.processingSystem()
systems.playerInput.filter = tiny.requireAll("x", "y", "PlayerInput")
function systems.playerInput:process(e, dt)
    local dx, dy = 0, 0
    if input.isDown("up") then dy = -1 end
    if input.isDown("down") then dy = 1 end
    if input.isDown("left") then dx = -1 end
    if input.isDown("right") then dx = 1 end

    -- Normalize diagonal
    if dx ~= 0 and dy ~= 0 then
        dx = dx * 0.7071
        dy = dy * 0.7071
    end

    e.vx = dx * e.PlayerInput.speed
    e.vy = dy * e.PlayerInput.speed
end

-- Seeking system: moves toward target
systems.seeking = tiny.processingSystem()
systems.seeking.filter = tiny.requireAll("x", "y", "vx", "vy", "SeeksTarget")
function systems.seeking:process(e, dt)
    local target = e.SeeksTarget.target
    if not target then return end

    local dx = target.x - e.x
    local dy = target.y - e.y
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist > 0 then
        e.vx = (dx / dist) * e.SeeksTarget.speed
        e.vy = (dy / dist) * e.SeeksTarget.speed
    end
end

-- Bounce system: bounces off arena walls
systems.bounce = tiny.processingSystem()
systems.bounce.filter = tiny.requireAll("x", "y", "vx", "vy", "Bounces")
function systems.bounce:onAddToWorld(world)
    self.arena = world.arena
end
function systems.bounce:process(e, dt)
    local arena = self.arena
    if e.x <= arena.x or e.x >= arena.x + arena.width then
        e.vx = -e.vx
        e.x = math.max(arena.x, math.min(arena.x + arena.width, e.x))
    end
    if e.y <= arena.y or e.y >= arena.y + arena.height then
        e.vy = -e.vy
        e.y = math.max(arena.y, math.min(arena.y + arena.height, e.y))
    end
end

-- Arena clamp system: keeps entities inside arena
systems.arenaClamp = tiny.processingSystem()
systems.arenaClamp.filter = tiny.requireAll("x", "y", "ArenaClamp")
function systems.arenaClamp:onAddToWorld(world)
    self.arena = world.arena
end
function systems.arenaClamp:process(e, dt)
    local arena = self.arena
    local margin = e.ArenaClamp.margin or 0
    e.x = math.max(arena.x + margin, math.min(arena.x + arena.width - margin, e.x))
    e.y = math.max(arena.y + margin, math.min(arena.y + arena.height - margin, e.y))
end

-- Lifetime system: removes entities when lifetime expires
systems.lifetime = tiny.processingSystem()
systems.lifetime.filter = tiny.requireAll("Lifetime")
function systems.lifetime:process(e, dt)
    e.Lifetime.remaining = e.Lifetime.remaining - dt
    if e.Lifetime.remaining <= 0 then
        self.world:removeEntity(e)
    end
end

-- Collision system: handles all collision detection and response
systems.collision = tiny.system()
systems.collision.filter = tiny.requireAll("x", "y", "Collider")
function systems.collision:onAddToWorld(world)
    self.player = nil
    self.enemies = {}
    self.projectiles = {}
end
function systems.collision:onAdd(e)
    if e.PlayerInput then
        self.player = e
    elseif e.DamagesPlayer then
        table.insert(self.enemies, e)
    elseif e.DamagesEnemy then
        table.insert(self.projectiles, e)
    end
end
function systems.collision:onRemove(e)
    if e == self.player then
        self.player = nil
    end
    for i = #self.enemies, 1, -1 do
        if self.enemies[i] == e then
            table.remove(self.enemies, i)
            break
        end
    end
    for i = #self.projectiles, 1, -1 do
        if self.projectiles[i] == e then
            table.remove(self.projectiles, i)
            break
        end
    end
end
function systems.collision:update(dt)
    local player = self.player
    if not player then return end

    -- Track entities to remove (avoid modifying lists while iterating)
    local toRemove = {}

    -- Enemy-player collisions
    for i = #self.enemies, 1, -1 do
        local enemy = self.enemies[i]
        local dx = enemy.x - player.x
        local dy = enemy.y - player.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local minDist = enemy.Collider.radius + player.Collider.radius

        if dist < minDist then
            -- Emit event instead of directly handling response
            events.emit("collision", {
                type = "enemy_hit_player",
                enemy = enemy,
                player = player,
                damage = enemy.DamagesPlayer.amount
            })
            toRemove[enemy] = true
        end
    end

    -- Projectile-enemy collisions
    for pi = #self.projectiles, 1, -1 do
        local proj = self.projectiles[pi]
        if proj and not toRemove[proj] then
            for ei = #self.enemies, 1, -1 do
                local enemy = self.enemies[ei]
                if enemy and not toRemove[enemy] then
                    local dx = proj.x - enemy.x
                    local dy = proj.y - enemy.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    local minDist = proj.Collider.radius + enemy.Collider.radius

                    if dist < minDist then
                        -- Emit event instead of directly handling response
                        events.emit("collision", {
                            type = "projectile_hit_enemy",
                            projectile = proj,
                            enemy = enemy,
                            damage = proj.DamagesEnemy.amount
                        })
                        toRemove[enemy] = true
                        toRemove[proj] = true
                        break
                    end
                end
            end
        end
    end

    -- Remove entities after iteration
    for entity, _ in pairs(toRemove) do
        self.world:removeEntity(entity)
    end
end

-- Render system: draws all renderable entities
systems.render = tiny.sortedProcessingSystem()
systems.render.filter = tiny.requireAll("x", "y", "Render")
systems.render.isDrawSystem = true
function systems.render:compare(a, b)
    return (a.Render.layer or 0) < (b.Render.layer or 0)
end
function systems.render:process(e, dt)
    local r = e.Render
    love.graphics.setColor(r.color[1], r.color[2], r.color[3], r.color[4] or 1)

    if r.type == "circle" then
        love.graphics.circle("fill", e.x, e.y, r.radius)
    elseif r.type == "rectangle" then
        love.graphics.rectangle("fill", e.x - r.width/2, e.y - r.height/2, r.width, r.height)
    end
end

-- HUD system: draws player health and other UI
systems.hud = tiny.processingSystem()
systems.hud.filter = tiny.requireAll("Health", "PlayerInput")
systems.hud.isDrawSystem = true
function systems.hud:process(e, dt)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("HP: " .. e.Health.current .. "/" .. e.Health.max, 10, 10)
end

-- Aiming line system: draws line from player to mouse
systems.aimingLine = tiny.processingSystem()
systems.aimingLine.filter = tiny.requireAll("x", "y", "PlayerInput")
systems.aimingLine.isDrawSystem = true
function systems.aimingLine:process(e, dt)
    love.graphics.setColor(0.5, 0.5, 0.5, 0.5)
    local mx, my = input.getMousePosition()
    love.graphics.line(e.x, e.y, mx, my)
end

return systems
