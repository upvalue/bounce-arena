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

-- Movement delay system: decrements delay timer before enemy can move
systems.movementDelay = tiny.processingSystem()
systems.movementDelay.filter = tiny.requireAll("MovementDelay")
function systems.movementDelay:process(e, dt)
    if not e.MovementDelay then return end
    e.MovementDelay.remaining = e.MovementDelay.remaining - dt
    if e.MovementDelay.remaining <= 0 then
        e.MovementDelay = nil
        self.world:addEntity(e)  -- refresh to remove from system
    end
end

-- Seeking system: moves toward target
systems.seeking = tiny.processingSystem()
systems.seeking.filter = tiny.requireAll("x", "y", "vx", "vy", "SeeksTarget")
function systems.seeking:process(e, dt)
    -- Skip if movement is delayed or frozen
    if e.MovementDelay then return end
    if e.Frozen then return end

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

-- Fleeing system: moves away from target (for Carrier)
-- Wanders randomly when player is far, flees when player is close
systems.fleeing = tiny.processingSystem()
systems.fleeing.filter = tiny.requireAll("x", "y", "vx", "vy", "FleesTarget")
function systems.fleeing:process(e, dt)
    -- Skip if frozen
    if e.Frozen then return end

    local flee = e.FleesTarget
    local target = flee.target
    if not target then return end

    local dx = target.x - e.x
    local dy = target.y - e.y
    local dist = math.sqrt(dx * dx + dy * dy)

    local fleeRadius = flee.fleeRadius or 150
    local wanderSpeed = flee.wanderSpeed or 15

    if dist < fleeRadius and dist > 0 then
        -- Player is close - flee!
        e.vx = -(dx / dist) * flee.speed
        e.vy = -(dy / dist) * flee.speed
    else
        -- Player is far - wander randomly
        flee.wanderTimer = (flee.wanderTimer or 0) - dt
        if flee.wanderTimer <= 0 then
            -- Pick new random direction every 1-3 seconds
            local angle = math.random() * math.pi * 2
            flee.wanderDirX = math.cos(angle)
            flee.wanderDirY = math.sin(angle)
            flee.wanderTimer = 1 + math.random() * 2
        end
        e.vx = (flee.wanderDirX or 0) * wanderSpeed
        e.vy = (flee.wanderDirY or 0) * wanderSpeed
    end
end

-- Oscillation system: moves back and forth (for Flapper)
systems.oscillation = tiny.processingSystem()
systems.oscillation.filter = tiny.requireAll("x", "y", "vx", "vy", "Oscillator")
function systems.oscillation:process(e, dt)
    -- Skip if frozen
    if e.Frozen then return end

    local osc = e.Oscillator
    osc.traveled = osc.traveled + math.abs(osc.speed) * dt

    if osc.traveled >= osc.distance then
        osc.direction = -osc.direction
        osc.traveled = 0
    end

    if osc.axis == "horizontal" then
        e.vx = osc.direction * osc.speed
        e.vy = 0
    else
        e.vx = 0
        e.vy = osc.direction * osc.speed
    end
end

-- Freeze system: handles frozen state countdown for enemies
systems.freeze = tiny.processingSystem()
systems.freeze.filter = tiny.requireAll("Frozen")
function systems.freeze:process(e, dt)
    e.Frozen.remaining = e.Frozen.remaining - dt
    if e.Frozen.remaining <= 0 then
        e.Frozen = nil
        self.world:addEntity(e)  -- refresh to remove from system
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
    -- Skip entities that ignore arena bounds (e.g., sniper shots)
    if e.IgnoresArenaBounds then return end

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

-- Fade system: updates render alpha based on lifetime for fading entities
systems.fade = tiny.processingSystem()
systems.fade.filter = tiny.requireAll("Lifetime", "FadesOut", "Render")
function systems.fade:process(e, dt)
    local total = e.Lifetime.total or 1
    local remaining = e.Lifetime.remaining
    local alpha = math.max(0, remaining / total)
    local color = e.Render.color
    color[4] = alpha * (e.Render.baseAlpha or 0.6)
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

-- Shooting system: handles turrets firing projectiles
local entities = require("entities")
local config = require("config")
systems.shooting = tiny.processingSystem()
systems.shooting.filter = tiny.requireAll("x", "y", "Shooter")
function systems.shooting:process(e, dt)
    local shooter = e.Shooter
    shooter.fireTimer = shooter.fireTimer - dt

    if shooter.fireTimer <= 0 then
        -- Fire in all configured directions
        for _, dir in ipairs(shooter.directions) do
            local proj
            if e.IsBallTurret then
                proj = entities.createBallTurretProjectile(e.x, e.y, dir[1], dir[2])
            else
                proj = entities.createEnemyProjectile(e.x, e.y, dir[1], dir[2])
            end
            self.world:addEntity(proj)
        end
        shooter.fireTimer = shooter.fireRate
    end
end

-- Spawner system: spawns child enemies (for Carrier)
systems.spawner = tiny.processingSystem()
systems.spawner.filter = tiny.requireAll("x", "y", "Spawner")
function systems.spawner:process(e, dt)
    local spawner = e.Spawner
    spawner.timer = spawner.timer - dt

    if spawner.timer <= 0 then
        -- Skip movement delay for carrier-spawned children
        local child = entities.createEnemy(e.x, e.y, spawner.target, config.enemies.fastTrooper, { skipMovementDelay = true })
        self.world:addEntity(child)
        spawner.timer = spawner.interval
        events.emit("enemy_spawned", { enemy = child })
    end
end

-- Mine detector system: handles mine proximity detection and detonation
systems.mineDetector = tiny.processingSystem()
systems.mineDetector.filter = tiny.requireAll("x", "y", "MineDetonator")
function systems.mineDetector:process(e, dt)
    local det = e.MineDetonator
    local player = det.player
    if not player then return end

    local dx = player.x - e.x
    local dy = player.y - e.y
    local dist = math.sqrt(dx * dx + dy * dy)

    if det.triggered then
        -- Countdown to explosion with flashing
        det.fuseTimer = det.fuseTimer - dt
        det.flashTimer = det.flashTimer - dt
        if det.flashTimer <= 0 then
            e.Flash = { remaining = 0.1, color = {1, 0, 0} }
            det.flashTimer = 0.15  -- fast flashing
            self.world:addEntity(e)
        end
        if det.fuseTimer <= 0 then
            -- Explode - deal AOE damage to player if in range
            if dist < det.aoeRadius and not player.Invulnerable then
                events.emit("collision", {
                    type = "mine_exploded",
                    mine = e,
                    player = player,
                    damage = det.aoeDamage
                })
            end
            -- Deal AOE damage to enemies in range
            local enemiesToRemove = {}
            for _, entity in ipairs(self.world.entities) do
                if entity.Health and entity.DamagesPlayer and entity ~= e then
                    local edx = entity.x - e.x
                    local edy = entity.y - e.y
                    local edist = math.sqrt(edx * edx + edy * edy)
                    if edist < det.aoeRadius then
                        entity.Health.current = entity.Health.current - det.aoeDamage
                        if entity.Health.current <= 0 then
                            table.insert(enemiesToRemove, entity)
                        end
                    end
                end
            end
            -- Remove killed enemies and emit events
            for _, enemy in ipairs(enemiesToRemove) do
                events.emit("collision", {
                    type = "mine_killed_enemy",
                    mine = e,
                    enemy = enemy
                })
                self.world:removeEntity(enemy)
            end
            events.emit("mine_removed", { mine = e })
            self.world:removeEntity(e)
        end
    elseif dist < det.detonationRange then
        det.triggered = true
        det.fuseTimer = det.fuseTime
        det.flashTimer = 0
    end
end

-- Bomb timer system: handles secondary weapon bomb fuse countdown and explosion
systems.bombTimer = tiny.processingSystem()
systems.bombTimer.filter = tiny.requireAll("x", "y", "BombTimer", "AoeExplosion")
function systems.bombTimer:process(e, dt)
    local bomb = e.BombTimer

    -- Countdown
    bomb.fuseRemaining = bomb.fuseRemaining - dt

    -- Flash as fuse burns (accelerating)
    bomb.flashTimer = bomb.flashTimer - dt
    local flashInterval = 0.1 + (bomb.fuseRemaining / bomb.fuseTime) * 0.3
    if bomb.flashTimer <= 0 then
        e.Flash = { remaining = 0.1, color = {1, 0.5, 0} }
        bomb.flashTimer = flashInterval
        self.world:addEntity(e)
    end

    -- Explode when fuse runs out
    if bomb.fuseRemaining <= 0 then
        events.emit("secondary_explosion", {
            type = "bomb",
            x = e.x,
            y = e.y,
            radius = e.AoeExplosion.radius,
            damage = e.AoeExplosion.damage
        })
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
    self.enemyProjectiles = {}
    self.ballTurretProjectiles = {}  -- bounce off enemies
    self.experience = {}
end
function systems.collision:onAdd(e)
    if e.PlayerInput then
        self.player = e
    elseif e.EnemyProjectile then
        -- Enemy projectiles tracked separately (pass through enemies)
        table.insert(self.enemyProjectiles, e)
        -- Ball turret projectiles also tracked for enemy bouncing
        if e.BouncesOffEnemies then
            table.insert(self.ballTurretProjectiles, e)
        end
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
    for i = #self.enemyProjectiles, 1, -1 do
        if self.enemyProjectiles[i] == e then
            table.remove(self.enemyProjectiles, i)
            break
        end
    end
    for i = #self.ballTurretProjectiles, 1, -1 do
        if self.ballTurretProjectiles[i] == e then
            table.remove(self.ballTurretProjectiles, i)
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

            -- Destroy enemy if flagged (e.g., troopers die on contact)
            if enemy.DestroyedOnContact then
                toRemove[enemy] = true
                events.emit("collision", {
                    type = "enemy_killed_on_contact",
                    enemy = enemy,
                    player = player
                })
            else
                -- Apply knockback: push enemy away from player (skip for stationary enemies like mines)
                if not enemy.MineDetonator then
                    local dx = enemy.x - player.x
                    local dy = enemy.y - player.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist > 0 then
                        enemy.vx = (dx / dist) * knockbackConfig.speed
                        enemy.vy = (dy / dist) * knockbackConfig.speed
                    end
                end

                -- Add cooldown so enemy can't immediately damage again
                enemy.DamageCooldown = { remaining = knockbackConfig.cooldown }
                self.world:addEntity(enemy)  -- refresh for cooldown system
            end
        end
    end

    -- Ball turret projectiles bounce off enemies (harmlessly)
    for _, proj in ipairs(self.ballTurretProjectiles) do
        if proj and not toRemove[proj] then
            for _, enemy in ipairs(self.enemies) do
                if enemy and not toRemove[enemy] and collides(proj, enemy) then
                    -- Calculate bounce direction (reflect off enemy surface)
                    local dx = proj.x - enemy.x
                    local dy = proj.y - enemy.y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist > 0 then
                        -- Normalize and reflect velocity
                        local nx, ny = dx / dist, dy / dist
                        local dot = proj.vx * nx + proj.vy * ny
                        proj.vx = proj.vx - 2 * dot * nx
                        proj.vy = proj.vy - 2 * dot * ny
                        -- Push projectile out of enemy
                        local overlap = (proj.Collider.radius + enemy.Collider.radius) - dist
                        if overlap > 0 then
                            proj.x = proj.x + nx * (overlap + 1)
                            proj.y = proj.y + ny * (overlap + 1)
                        end
                    end
                    break  -- Only bounce off one enemy per frame
                end
            end
        end
    end

    -- Projectile-enemy collisions
    for pi = #self.projectiles, 1, -1 do
        local proj = self.projectiles[pi]
        if proj and not toRemove[proj] then
            for ei = #self.enemies, 1, -1 do
                local enemy = self.enemies[ei]
                -- Skip if already hit by this piercing projectile
                local alreadyHit = proj.Piercing and proj.Piercing.hitEnemies[enemy]
                if enemy and not toRemove[enemy] and not alreadyHit and collides(proj, enemy) then
                    -- Check for missile with ExplodesOnContact - triggers AOE explosion
                    if proj.ExplodesOnContact then
                        events.emit("secondary_explosion", {
                            type = "missile",
                            x = proj.x,
                            y = proj.y,
                            radius = proj.ExplodesOnContact.aoeRadius,
                            damage = proj.ExplodesOnContact.aoeDamage
                        })
                        toRemove[proj] = true
                        break  -- missile is consumed by explosion
                    end

                    -- Apply damage to enemy (OneHitKill guarantees kill)
                    local damage = proj.DamagesEnemy.amount
                    if proj.OneHitKill and enemy.Health then
                        damage = enemy.Health.max + 1
                    end
                    if enemy.Health then
                        enemy.Health.current = enemy.Health.current - damage
                    end

                    -- Only remove enemy if dead
                    local killed = not enemy.Health or enemy.Health.current <= 0
                    if killed then
                        toRemove[enemy] = true
                        -- If mine is killed, emit mine_removed so it doesn't explode
                        if enemy.MineDetonator then
                            events.emit("mine_removed", { mine = enemy })
                        end
                    else
                        -- Trigger mine when damaged but not killed
                        if enemy.MineDetonator and not enemy.MineDetonator.triggered then
                            enemy.MineDetonator.triggered = true
                            enemy.MineDetonator.fuseTimer = enemy.MineDetonator.fuseTime
                            enemy.MineDetonator.flashTimer = 0
                        end
                    end

                    -- Handle piercing projectiles (pass through enemies)
                    local projectileDestroyed = true
                    if proj.Piercing then
                        proj.Piercing.hitEnemies[enemy] = true
                        projectileDestroyed = false
                        -- Don't break - continue checking other enemies
                    elseif proj.EnemyBounces and proj.EnemyBounces.count < proj.EnemyBounces.max then
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

                    -- Only break if not piercing
                    if not proj.Piercing then
                        break
                    end
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

    -- Enemy projectile-player collisions (turret shots, skip if invulnerable)
    for i = #self.enemyProjectiles, 1, -1 do
        local proj = self.enemyProjectiles[i]
        if proj and not toRemove[proj] and not player.Invulnerable and collides(proj, player) then
            events.emit("collision", {
                type = "enemy_projectile_hit_player",
                projectile = proj,
                player = player,
                damage = proj.DamagesPlayer.amount
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
    elseif r.type == "turret" then
        -- Draw center circle
        love.graphics.circle("fill", e.x, e.y, r.radius)
        -- Draw direction lines
        love.graphics.setLineWidth(2)
        for _, dir in ipairs(r.directions) do
            local endX = e.x + dir[1] * r.lineLength
            local endY = e.y + dir[2] * r.lineLength
            love.graphics.line(e.x, e.y, endX, endY)
        end
        love.graphics.setLineWidth(1)
    elseif r.type == "oval" then
        love.graphics.ellipse("fill", e.x, e.y, r.width / 2, r.height / 2)
    elseif r.type == "mine" then
        -- Draw blast radius indicator only when triggered
        if e.MineDetonator and e.MineDetonator.triggered then
            love.graphics.setColor(color[1], color[2], color[3], 0.15)
            love.graphics.circle("fill", e.x, e.y, r.blastRadius)
            love.graphics.setColor(color[1], color[2], color[3], 0.3)
            love.graphics.setLineWidth(1)
            love.graphics.circle("line", e.x, e.y, r.blastRadius)
        end
        -- Draw mine body
        love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
        love.graphics.circle("fill", e.x, e.y, r.radius)
    elseif r.type == "sniper" then
        -- Draw rotated rectangle for sniper shot
        love.graphics.push()
        love.graphics.translate(e.x, e.y)
        love.graphics.rotate(r.angle or 0)
        love.graphics.rectangle("fill", -r.width/2, -r.height/2, r.width, r.height)
        love.graphics.pop()
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
