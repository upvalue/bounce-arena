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
            type = "vector",
            radius = config.player.size,
            color = config.player.color,
            layer = 10
        }
    }
end

function entities.createEnemy(x, y, target, enemyType, options)
    enemyType = enemyType or config.enemies.trooper
    options = options or {}
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
            type = "vector",
            radius = enemyType.size,
            color = enemyType.color,
            layer = 5
        }
    }
    -- Add movement delay if configured (unless explicitly skipped)
    if enemyType.movementDelay and not options.skipMovementDelay then
        enemy.MovementDelay = { remaining = enemyType.movementDelay }
    end
    -- Mark as destroyed on contact with player
    if enemyType.destroyedOnContact then
        enemy.DestroyedOnContact = true
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
            type = "vector",
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
            type = "sparkle",
            radius = config.experience.size,
            color = config.experience.color,
            layer = 3
        }
    }
end

function entities.createTurret(x, y, turretType)
    turretType = turretType or config.enemies.xTurret
    local turret = {
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
    -- Add ball turret flag if this turret type fires bouncing projectiles
    if turretType.isBallTurret then
        turret.IsBallTurret = true
    end
    return turret
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
            type = "vector",
            radius = cfg.size,
            color = cfg.color,
            layer = 7
        }
    }
end

function entities.createBallTurretProjectile(x, y, dirX, dirY)
    local cfg = config.ballTurretProjectile
    return {
        x = x,
        y = y,
        vx = dirX * cfg.speed,
        vy = dirY * cfg.speed,
        Collider = { radius = cfg.size },
        Bounces = {},                    -- bounces off arena walls
        BouncesOffEnemies = {},          -- bounces off enemies harmlessly
        EnemyProjectile = true,          -- marker for enemy projectile
        DamagesPlayer = { amount = cfg.damage },
        Lifetime = { remaining = cfg.lifetime },
        Render = {
            type = "vector",
            radius = cfg.size,
            color = cfg.color,
            layer = 9
        }
    }
end

function entities.createGunnerProjectile(x, y, dirX, dirY)
    local cfg = config.gunnerProjectile
    return {
        x = x,
        y = y,
        vx = dirX * cfg.speed,
        vy = dirY * cfg.speed,
        Collider = { radius = cfg.size },
        Bounces = {},                    -- bounces off arena walls
        EnemyProjectile = true,          -- marker for enemy projectile
        DamagesPlayer = { amount = cfg.damage },
        Lifetime = { remaining = cfg.lifetime },
        Render = {
            type = "vector",
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

function entities.createCarrier(x, y, target)
    local cfg = config.enemies.carrier
    return {
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        Health = { current = cfg.health, max = cfg.health },
        Collider = { radius = cfg.size },
        FleesTarget = {
            target = target,
            speed = cfg.speed,
            wanderSpeed = cfg.wanderSpeed,
            fleeRadius = cfg.fleeRadius
        },
        Bounces = {},  -- bounce off walls while fleeing
        Spawner = { timer = cfg.spawnInterval, interval = cfg.spawnInterval, target = target },
        DamagesPlayer = { amount = cfg.damage },
        expValue = cfg.expValue,
        Render = {
            type = "oval",
            width = cfg.size * 2.5,
            height = cfg.size * 1.5,
            color = cfg.color,
            layer = 5
        }
    }
end

function entities.spawnCarrierAtEdge(arena, target, rng)
    rng = rng or math.random
    local cfg = config.enemies.carrier
    local margin = cfg.size
    local safeRadius = config.spawn.safeRadius

    for attempt = 1, 10 do
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

        if target then
            local dx = x - target.x
            local dy = y - target.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist >= safeRadius then
                return entities.createCarrier(x, y, target)
            end
        else
            return entities.createCarrier(x, y, target)
        end
    end

    -- Fallback
    local x = arena.x + arena.width / 2
    local y = arena.y + margin
    return entities.createCarrier(x, y, target)
end

function entities.createMine(x, y, player)
    local cfg = config.enemies.mine
    return {
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        Health = { current = cfg.health, max = cfg.health },
        Collider = { radius = cfg.size },
        MineDetonator = {
            player = player,
            detonationRange = cfg.detonationRange,
            aoeDamage = cfg.aoeDamage,
            aoeRadius = cfg.aoeRadius,
            fuseTime = cfg.fuseTime,
            triggered = false,
            fuseTimer = 0,
            flashTimer = 0
        },
        DamagesPlayer = { amount = 0 },  -- for collision tracking
        expValue = cfg.expValue,
        Render = {
            type = "mine",
            radius = cfg.size,
            blastRadius = cfg.aoeRadius,
            color = cfg.color,
            layer = 5
        }
    }
end

function entities.spawnMineAtEdge(arena, player, rng)
    rng = rng or math.random
    local cfg = config.enemies.mine
    -- Spawn mines away from edges (like turrets)
    local margin = 50 + cfg.size

    local side = rng(1, 4)
    local x, y

    if side == 1 then
        x = arena.x + margin + rng() * (arena.width - margin * 2)
        y = arena.y + margin
    elseif side == 2 then
        x = arena.x + margin + rng() * (arena.width - margin * 2)
        y = arena.y + arena.height - margin
    elseif side == 3 then
        x = arena.x + margin
        y = arena.y + margin + rng() * (arena.height - margin * 2)
    else
        x = arena.x + arena.width - margin
        y = arena.y + margin + rng() * (arena.height - margin * 2)
    end

    return entities.createMine(x, y, player)
end

function entities.createFlapper(x, y, axis)
    local cfg = config.enemies.flapper
    return {
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        Health = { current = cfg.health, max = cfg.health },
        Collider = { radius = cfg.size },
        Oscillator = {
            axis = axis or "horizontal",
            direction = 1,
            speed = cfg.speed,
            distance = cfg.travelDistance,
            traveled = 0
        },
        ArenaClamp = { margin = cfg.size },
        DamagesPlayer = { amount = cfg.damage },
        expValue = cfg.expValue,
        Render = {
            type = "vector",
            radius = cfg.size,
            color = cfg.color,
            layer = 5
        }
    }
end

function entities.spawnFlapperAtEdge(arena, rng)
    rng = rng or math.random
    local cfg = config.enemies.flapper
    local margin = cfg.size
    local axis = rng(1, 2) == 1 and "horizontal" or "vertical"

    local x, y
    if axis == "horizontal" then
        -- Spawn on left or right edge
        local side = rng(1, 2)
        if side == 1 then
            x = arena.x + margin
        else
            x = arena.x + arena.width - margin
        end
        y = arena.y + margin + rng() * (arena.height - margin * 2)
    else
        -- Spawn on top or bottom edge
        local side = rng(1, 2)
        x = arena.x + margin + rng() * (arena.width - margin * 2)
        if side == 1 then
            y = arena.y + margin
        else
            y = arena.y + arena.height - margin
        end
    end

    return entities.createFlapper(x, y, axis)
end

function entities.createGunner(x, y, target)
    local cfg = config.enemies.gunner
    return {
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        Health = { current = cfg.health, max = cfg.health },
        Collider = { radius = cfg.size },
        SeeksTarget = { target = target, speed = cfg.speed },
        GunnerShooter = {
            fireRate = cfg.fireRate,
            fireTimer = cfg.fireRate,
            target = target
        },
        DamagesPlayer = { amount = cfg.damage },
        expValue = cfg.expValue,
        Render = {
            type = "vector",
            radius = cfg.size,
            color = cfg.color,
            layer = 5
        }
    }
end

function entities.spawnGunnerAtEdge(arena, target, rng)
    rng = rng or math.random
    local cfg = config.enemies.gunner
    local margin = cfg.size
    local safeRadius = config.spawn.safeRadius

    for attempt = 1, 10 do
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

        if target then
            local dx = x - target.x
            local dy = y - target.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist >= safeRadius then
                return entities.createGunner(x, y, target)
            end
        else
            return entities.createGunner(x, y, target)
        end
    end

    local x = arena.x + arena.width / 2
    local y = arena.y + margin
    return entities.createGunner(x, y, target)
end

function entities.createAoeEffect(x, y, radius)
    local cfg = config.effects.aoeExplosion
    return {
        x = x,
        y = y,
        Lifetime = { remaining = cfg.duration, total = cfg.duration },
        FadesOut = true,
        Render = {
            type = "circle",
            radius = radius,
            color = {cfg.color[1], cfg.color[2], cfg.color[3], cfg.color[4]},
            layer = 2  -- below enemies
        }
    }
end

-- Secondary weapon: Bomb (dropped at player position, timed explosion)
function entities.createBomb(x, y)
    local cfg = config.secondaryWeapons.bomb
    return {
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        BombTimer = {
            fuseTime = cfg.fuseTime,
            fuseRemaining = cfg.fuseTime,
            flashTimer = 0
        },
        AoeExplosion = {
            radius = cfg.aoeRadius,
            damage = cfg.aoeDamage
        },
        Render = {
            type = "vector",
            radius = cfg.size,
            color = {cfg.color[1], cfg.color[2], cfg.color[3]},
            layer = 6
        }
    }
end

-- Secondary weapon: Missile (flies straight, explodes on enemy contact with AOE)
function entities.createMissile(x, y, dirX, dirY)
    local cfg = config.secondaryWeapons.missile
    local len = math.sqrt(dirX * dirX + dirY * dirY)
    local vx, vy = 0, 0
    if len > 0 then
        vx = (dirX / len) * cfg.speed
        vy = (dirY / len) * cfg.speed
    end

    return {
        x = x,
        y = y,
        vx = vx,
        vy = vy,
        Collider = { radius = cfg.size },
        Bounces = {},
        Lifetime = { remaining = 5 },
        ExplodesOnContact = {
            aoeRadius = cfg.aoeRadius,
            aoeDamage = cfg.aoeDamage
        },
        DamagesEnemy = { amount = cfg.aoeDamage },
        Render = {
            type = "vector",
            radius = cfg.size,
            color = {cfg.color[1], cfg.color[2], cfg.color[3]},
            layer = 8
        }
    }
end

-- Secondary weapon: Sniper (fast, one-hit kill, pierces enemies, ignores arena bounds)
function entities.createSniperShot(x, y, dirX, dirY)
    local cfg = config.secondaryWeapons.sniper
    local len = math.sqrt(dirX * dirX + dirY * dirY)
    local vx, vy = 0, 0
    local angle = 0
    if len > 0 then
        vx = (dirX / len) * cfg.speed
        vy = (dirY / len) * cfg.speed
        angle = math.atan2(dirY, dirX)
    end

    return {
        x = x,
        y = y,
        vx = vx,
        vy = vy,
        Collider = { radius = cfg.size },
        IgnoresArenaBounds = {},
        Lifetime = { remaining = 3 },
        OneHitKill = {},
        Piercing = { hitEnemies = {} },  -- passes through enemies
        DamagesEnemy = { amount = 9999 },
        Render = {
            type = "sniper",
            width = 20,
            height = 4,
            angle = angle,
            color = {0.7, 0.7, 0.7},  -- gray
            layer = 9
        }
    }
end

-- Visual effect for secondary weapon explosions (orange)
function entities.createSecondaryAoeEffect(x, y, radius)
    local cfg = config.effects.aoeExplosion
    return {
        x = x,
        y = y,
        Lifetime = { remaining = cfg.duration, total = cfg.duration },
        FadesOut = true,
        Render = {
            type = "circle",
            radius = radius,
            color = {1, 0.6, 0.2, 0.6},  -- orange for secondary weapons
            layer = 2
        }
    }
end

return entities
