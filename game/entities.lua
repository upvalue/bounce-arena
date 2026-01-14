local config = require("config")

local entities = {}

-- Expose config for external access (e.g., tests)
entities.config = config

function entities.createPlayer(x, y)
    return {
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        Health = { current = config.player.maxHp, max = config.player.maxHp },
        Collider = { radius = config.player.size },
        PlayerInput = { speed = config.player.speed },
        ArenaClamp = { margin = config.player.size },
        Render = {
            type = "circle",
            radius = config.player.size,
            color = config.player.color,
            layer = 10
        }
    }
end

function entities.createEnemy(x, y, target, enemyType)
    enemyType = enemyType or config.enemies.trooper
    local enemy = {
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        Health = { current = enemyType.health, max = enemyType.health },
        Collider = { radius = enemyType.size },
        SeeksTarget = { target = target, speed = enemyType.speed },
        DamagesPlayer = { amount = enemyType.damage },
        expValue = enemyType.expValue or 1,
        Render = {
            type = "circle",
            radius = enemyType.size,
            color = enemyType.color,
            layer = 5
        }
    }
    -- Add movement delay if configured
    if enemyType.movementDelay then
        enemy.MovementDelay = { remaining = enemyType.movementDelay }
    end
    return enemy
end

function entities.createProjectile(x, y, dirX, dirY)
    local len = math.sqrt(dirX * dirX + dirY * dirY)
    local vx, vy = 0, 0
    if len > 0 then
        vx = (dirX / len) * config.projectile.speed
        vy = (dirY / len) * config.projectile.speed
    end

    return {
        x = x,
        y = y,
        vx = vx,
        vy = vy,
        Collider = { radius = config.projectile.size },
        Bounces = {},
        EnemyBounces = { count = 0, max = config.projectile.maxEnemyBounces },
        Lifetime = { remaining = config.projectile.lifetime },
        DamagesEnemy = { amount = config.projectile.damage },
        Render = {
            type = "circle",
            radius = config.projectile.size,
            color = config.projectile.color,
            layer = 8
        }
    }
end

function entities.spawnEnemyAtEdge(arena, target, rng, enemyType)
    rng = rng or math.random
    enemyType = enemyType or config.enemies.trooper
    local margin = enemyType.size
    local safeRadius = config.spawn.safeRadius

    -- Try up to 10 times to find a safe spawn point
    for attempt = 1, 10 do
        local side = rng(1, 4)
        local x, y

        if side == 1 then -- top
            x = arena.x + rng() * arena.width
            y = arena.y + margin
        elseif side == 2 then -- bottom
            x = arena.x + rng() * arena.width
            y = arena.y + arena.height - margin
        elseif side == 3 then -- left
            x = arena.x + margin
            y = arena.y + rng() * arena.height
        else -- right
            x = arena.x + arena.width - margin
            y = arena.y + rng() * arena.height
        end

        -- Check distance from target (player)
        if target then
            local dx = x - target.x
            local dy = y - target.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist >= safeRadius then
                return entities.createEnemy(x, y, target, enemyType)
            end
        else
            return entities.createEnemy(x, y, target, enemyType)
        end
    end

    -- Fallback: spawn anyway on last attempt position
    local side = rng(1, 4)
    local x, y
    if side == 1 then
        x = arena.x + rng() * arena.width
        y = arena.y + margin
    elseif side == 2 then
        x = arena.x + rng() * arena.width
        y = arena.y + arena.height - margin
    elseif side == 3 then
        x = arena.x + margin
        y = arena.y + rng() * arena.height
    else
        x = arena.x + arena.width - margin
        y = arena.y + rng() * arena.height
    end
    return entities.createEnemy(x, y, target, enemyType)
end

function entities.createExperience(x, y, target, value)
    return {
        x = x,
        y = y,
        Collider = { radius = config.experience.size },
        Experience = { value = value or config.experience.value },
        AttractedTo = {
            target = target,
            radius = config.experience.attractRadius,
            speed = config.experience.attractSpeed
        },
        Render = {
            type = "circle",
            radius = config.experience.size,
            color = config.experience.color,
            layer = 3
        }
    }
end

function entities.createTurret(x, y, turretType)
    turretType = turretType or config.enemies.xTurret
    return {
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        Health = { current = turretType.health, max = turretType.health },
        Collider = { radius = turretType.size },
        DamagesPlayer = { amount = turretType.damage or 0 },  -- needed for collision tracking
        expValue = turretType.expValue or 1,
        Shooter = {
            fireRate = turretType.fireRate,
            fireTimer = turretType.fireRate,  -- start ready to fire
            directions = turretType.directions
        },
        Render = {
            type = "turret",
            radius = turretType.size * 0.4,  -- small center circle
            lineLength = turretType.size,    -- length of direction lines
            directions = turretType.directions,
            color = turretType.color,
            layer = 5
        }
    }
end

function entities.createEnemyProjectile(x, y, dirX, dirY)
    local cfg = config.turretProjectile
    return {
        x = x,
        y = y,
        vx = dirX * cfg.speed,
        vy = dirY * cfg.speed,
        Collider = { radius = cfg.size },
        Lifetime = { remaining = cfg.lifetime },
        DamagesPlayer = { amount = cfg.damage },
        EnemyProjectile = true,  -- flag to skip enemy collisions
        Render = {
            type = "circle",
            radius = cfg.size,
            color = cfg.color,
            layer = 7
        }
    }
end

function entities.spawnTurretAtEdge(arena, rng, turretType)
    rng = rng or math.random
    turretType = turretType or config.enemies.xTurret
    -- Spawn turrets further from wall (50 pixels + size)
    local margin = 50 + turretType.size

    local side = rng(1, 4)
    local x, y

    if side == 1 then -- top
        x = arena.x + margin + rng() * (arena.width - margin * 2)
        y = arena.y + margin
    elseif side == 2 then -- bottom
        x = arena.x + margin + rng() * (arena.width - margin * 2)
        y = arena.y + arena.height - margin
    elseif side == 3 then -- left
        x = arena.x + margin
        y = arena.y + margin + rng() * (arena.height - margin * 2)
    else -- right
        x = arena.x + arena.width - margin
        y = arena.y + margin + rng() * (arena.height - margin * 2)
    end

    return entities.createTurret(x, y, turretType)
end

return entities
