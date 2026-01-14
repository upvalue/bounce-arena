local tiny = require("lib.tiny")
local systems = require("systems")
local entities = require("entities")
local config = require("config")
local input = require("input")
local events = require("events")

-- ECS world
local world
local player

function love.load()
    love.window.setTitle("Bounce Arena")

    local arena = config.arena

    -- Create ECS world with arena and config references
    world = tiny.world()
    world.arena = arena
    world.config = config

    -- Add systems in order (update systems first, then render systems)
    world:addSystem(systems.playerInput)
    world:addSystem(systems.seeking)
    world:addSystem(systems.movement)
    world:addSystem(systems.bounce)
    world:addSystem(systems.arenaClamp)
    world:addSystem(systems.lifetime)
    world:addSystem(systems.collision)
    world:addSystem(systems.render)
    world:addSystem(systems.aimingLine)
    world:addSystem(systems.hud)

    -- Create player at center
    player = entities.createPlayer(
        arena.x + arena.width / 2,
        arena.y + arena.height / 2
    )
    world:addEntity(player)

    -- Spawn initial enemies
    for i = 1, config.spawn.initialEnemies do
        local enemy = entities.spawnEnemyAtEdge(arena, player)
        world:addEntity(enemy)
    end

    -- Set up collision event handlers
    events.on("collision", function(data)
        if data.type == "enemy_hit_player" then
            -- Apply damage to player
            data.player.Health.current = data.player.Health.current - data.damage
        end
        -- Future: add sound effects, particles, screen shake, etc.
    end)
end

function love.update(dt)
    -- Update input state from Love2D
    input.update()

    world:update(dt, function(_, system)
        return not system.isDrawSystem
    end)
end

function love.draw()
    -- Draw arena border
    local arena = config.arena
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", arena.x, arena.y, arena.width, arena.height)

    -- Draw instructions
    love.graphics.print("WASD to move, Click to shoot", 10, 30)

    -- Run draw systems
    world:update(0, function(_, system)
        return system.isDrawSystem
    end)
end

function love.mousepressed(x, y, button)
    if button == 1 and player then
        local dirX = x - player.x
        local dirY = y - player.y
        local projectile = entities.createProjectile(player.x, player.y, dirX, dirY)
        world:addEntity(projectile)
    end
end
