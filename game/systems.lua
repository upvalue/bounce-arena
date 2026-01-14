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

-- Attraction system: moves toward target when within radius
systems.attraction = tiny.processingSystem()
systems.attraction.filter = tiny.requireAll("x", "y", "AttractedTo")
function systems.attraction:process(e, dt)
    local target = e.AttractedTo.target
    if not target then return end

    local dx = target.x - e.x
    local dy = target.y - e.y
    local dist = math.sqrt(dx * dx + dy * dy)

    if dist < e.AttractedTo.radius and dist > 0 then
        local speed = e.AttractedTo.speed
        e.x = e.x + (dx / dist) * speed * dt
        e.y = e.y + (dy / dist) * speed * dt
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
        events.emit("entity_expired", e)
        self.world:removeEntity(e)
    end
end

-- Damage cooldown system: decrements cooldown timer
systems.damageCooldown = tiny.processingSystem()
systems.damageCooldown.filter = tiny.requireAll("DamageCooldown")
function systems.damageCooldown:process(e, dt)
    if not e.DamageCooldown then return end
    e.DamageCooldown.remaining = e.DamageCooldown.remaining - dt
    if e.DamageCooldown.remaining <= 0 then
        e.DamageCooldown = nil
        self.world:addEntity(e)  -- refresh to remove from system
    end
end

-- Invulnerability system: handles player invuln timer and periodic flashing
systems.invulnerability = tiny.processingSystem()
systems.invulnerability.filter = tiny.requireAll("Invulnerable")
function systems.invulnerability:onAddToWorld(world)
    self.config = world.config
end
function systems.invulnerability:process(e, dt)
    if not e.Invulnerable then return end
    local invuln = e.Invulnerable

    -- Decrement timer
    invuln.remaining = invuln.remaining - dt
    invuln.flashTimer = invuln.flashTimer - dt

    -- Trigger flash periodically
    if invuln.flashTimer <= 0 then
        e.Flash = {
            remaining = self.config.effects.flashDuration,
            color = {1, 1, 1}  -- white flash for invuln
        }
        invuln.flashTimer = self.config.invuln.flashInterval
        self.world:addEntity(e)  -- refresh for flash system
    end

    -- Remove invulnerability when expired
    if invuln.remaining <= 0 then
        e.Invulnerable = nil
        self.world:addEntity(e)  -- refresh to remove from system
    end
end

-- Collision system: handles all collision detection and response
systems.collision = tiny.system()
systems.collision.filter = tiny.requireAll("x", "y", "Collider")
function systems.collision:onAddToWorld(world)
    self.player = nil
    self.enemies = {}
    self.projectiles = {}
    self.experience = {}
end
function systems.collision:onAdd(e)
    if e.PlayerInput then
        self.player = e
    elseif e.DamagesPlayer then
        table.insert(self.enemies, e)
    elseif e.DamagesEnemy then
        table.insert(self.projectiles, e)
    elseif e.Experience then
        table.insert(self.experience, e)
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
    for i = #self.experience, 1, -1 do
        if self.experience[i] == e then
            table.remove(self.experience, i)
            break
        end
    end
end
-- Helper: check if two entities with Colliders overlap
local function collides(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist < (a.Collider.radius + b.Collider.radius)
end

function systems.collision:update(dt)
    local player = self.player
    if not player then return end

    local toRemove = {}
    local knockbackConfig = self.world.config.knockback

    -- Enemy-player collisions (skip if player invulnerable)
    for i = #self.enemies, 1, -1 do
        local enemy = self.enemies[i]
        -- Skip enemies on cooldown or if player is invulnerable
        if not enemy.DamageCooldown and not player.Invulnerable and collides(enemy, player) then
            events.emit("collision", {
                type = "enemy_hit_player",
                enemy = enemy,
                player = player,
                damage = enemy.DamagesPlayer.amount
            })

            -- Apply knockback: push enemy away from player
            local dx = enemy.x - player.x
            local dy = enemy.y - player.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 0 then
                enemy.vx = (dx / dist) * knockbackConfig.speed
                enemy.vy = (dy / dist) * knockbackConfig.speed
            end

            -- Add cooldown so enemy can't immediately damage again
            enemy.DamageCooldown = { remaining = knockbackConfig.cooldown }
            self.world:addEntity(enemy)  -- refresh for cooldown system
        end
    end

    -- Projectile-enemy collisions
    for pi = #self.projectiles, 1, -1 do
        local proj = self.projectiles[pi]
        if proj and not toRemove[proj] then
            for ei = #self.enemies, 1, -1 do
                local enemy = self.enemies[ei]
                if enemy and not toRemove[enemy] and collides(proj, enemy) then
                    -- Apply damage to enemy
                    local damage = proj.DamagesEnemy.amount
                    if enemy.Health then
                        enemy.Health.current = enemy.Health.current - damage
                    end

                    -- Only remove enemy if dead
                    local killed = not enemy.Health or enemy.Health.current <= 0
                    if killed then
                        toRemove[enemy] = true
                    end

                    -- Bounce or destroy projectile
                    local projectileDestroyed = true
                    if proj.EnemyBounces and proj.EnemyBounces.count < proj.EnemyBounces.max then
                        -- Bounce: reflect velocity away from enemy
                        local dx = proj.x - enemy.x
                        local dy = proj.y - enemy.y
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if dist > 0 then
                            -- Reflect velocity
                            local nx, ny = dx / dist, dy / dist
                            local dot = proj.vx * nx + proj.vy * ny
                            proj.vx = proj.vx - 2 * dot * nx
                            proj.vy = proj.vy - 2 * dot * ny
                            -- Push projectile out of enemy
                            local overlap = proj.Collider.radius + enemy.Collider.radius - dist
                            proj.x = proj.x + nx * (overlap + 1)
                            proj.y = proj.y + ny * (overlap + 1)
                        end
                        proj.EnemyBounces.count = proj.EnemyBounces.count + 1
                        projectileDestroyed = false
                    else
                        toRemove[proj] = true
                    end

                    -- Emit event after bounce logic
                    events.emit("collision", {
                        type = "projectile_hit_enemy",
                        projectile = proj,
                        enemy = enemy,
                        damage = damage,
                        killed = killed,
                        projectileDestroyed = projectileDestroyed
                    })
                    break
                end
            end
        end
    end

    -- Projectile-player collisions (self-damage, skip if invulnerable)
    for pi = #self.projectiles, 1, -1 do
        local proj = self.projectiles[pi]
        if proj and not toRemove[proj] and not player.Invulnerable and collides(proj, player) then
            events.emit("collision", {
                type = "projectile_hit_player",
                projectile = proj,
                player = player,
                damage = proj.DamagesEnemy.amount
            })
            toRemove[proj] = true
        end
    end

    -- Experience-player collisions (pickup)
    for i = #self.experience, 1, -1 do
        local exp = self.experience[i]
        if exp and not toRemove[exp] and collides(exp, player) then
            events.emit("collision", {
                type = "experience_collected",
                experience = exp,
                player = player,
                value = exp.Experience.value
            })
            toRemove[exp] = true
        end
    end

    -- Remove entities after iteration
    for entity, _ in pairs(toRemove) do
        self.world:removeEntity(entity)
    end
end

-- Flash system: decrements flash timers
systems.flash = tiny.processingSystem()
systems.flash.filter = tiny.requireAll("Flash")
function systems.flash:process(e, dt)
    if not e.Flash then return end
    e.Flash.remaining = e.Flash.remaining - dt
    if e.Flash.remaining <= 0 then
        e.Flash = nil
        self.world:addEntity(e)  -- refresh to remove from flash system
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
    local color = r.color

    -- Override color if flashing
    if e.Flash then
        color = e.Flash.color
    end

    love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)

    if r.type == "circle" then
        love.graphics.circle("fill", e.x, e.y, r.radius)
    elseif r.type == "rectangle" then
        love.graphics.rectangle("fill", e.x - r.width/2, e.y - r.height/2, r.width, r.height)
    end
end

-- HUD system: placeholder (HUD now drawn in main.lua)
systems.hud = tiny.processingSystem()
systems.hud.filter = tiny.requireAll("Health", "PlayerInput")
systems.hud.isDrawSystem = true
function systems.hud:process(e, dt)
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
