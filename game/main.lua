local tiny = require("lib.tiny")
local systems = require("systems")
local entities = require("entities")

-- Game configuration
local ARENA = {
    x = 50,
    y = 50,
    width = 700,
    height = 500
}
local ENEMY_SPAWN_COUNT = 5

-- ECS world
local world
local player

function love.load()
    love.window.setTitle("Bounce Arena")

    -- Create ECS world with arena reference
    world = tiny.world()
    world.arena = ARENA

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
        ARENA.x + ARENA.width / 2,
        ARENA.y + ARENA.height / 2
    )
    world:addEntity(player)

    -- Spawn initial enemies
    for i = 1, ENEMY_SPAWN_COUNT do
        local enemy = entities.spawnEnemyAtEdge(ARENA, player)
        world:addEntity(enemy)
    end
end

function love.update(dt)
    world:update(dt, function(_, system)
        return not system.isDrawSystem
    end)
end

function love.draw()
    -- Draw arena border
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", ARENA.x, ARENA.y, ARENA.width, ARENA.height)

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
