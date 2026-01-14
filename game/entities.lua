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

function entities.createEnemy(x, y, target)
    return {
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        Collider = { radius = config.enemy.size },
        SeeksTarget = { target = target, speed = config.enemy.speed },
        DamagesPlayer = { amount = config.enemy.damage },
        Render = {
            type = "circle",
            radius = config.enemy.size,
            color = config.enemy.color,
            layer = 5
        }
    }
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

function entities.spawnEnemyAtEdge(arena, target, rng)
    rng = rng or math.random
    local side = rng(1, 4)
    local x, y
    local margin = config.enemy.size

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

    return entities.createEnemy(x, y, target)
end

return entities
