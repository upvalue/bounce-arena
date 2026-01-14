-- Test helpers for Bounce Arena
local helpers = {}

-- Default config for tests (mirrors relevant parts of game config)
local defaultConfig = {
    knockback = {
        speed = 400,
        cooldown = 0.5
    }
}

-- Mock tiny-ecs world for testing
function helpers.createMockWorld(arena, config)
    local world = {
        arena = arena or { x = 0, y = 0, width = 800, height = 600 },
        config = config or defaultConfig,
        entities = {},
        removed = {}
    }

    function world:addEntity(e)
        table.insert(self.entities, e)
        return e
    end

    function world:removeEntity(e)
        table.insert(self.removed, e)
        for i, entity in ipairs(self.entities) do
            if entity == e then
                table.remove(self.entities, i)
                break
            end
        end
    end

    return world
end

-- Create a minimal processing system wrapper for testing
function helpers.processSystem(system, entities, dt, world)
    dt = dt or 1/60
    world = world or helpers.createMockWorld()

    -- Inject world reference if system needs it
    if system.onAddToWorld then
        system:onAddToWorld(world)
    end

    -- Set world reference
    system.world = world

    -- Process each entity
    for _, e in ipairs(entities) do
        if system.process then
            system:process(e, dt)
        end
    end

    return world
end

-- Assert helpers
function helpers.assertNear(actual, expected, tolerance, message)
    tolerance = tolerance or 0.001
    local diff = math.abs(actual - expected)
    if diff > tolerance then
        error(string.format(
            "%s: expected %f, got %f (diff: %f, tolerance: %f)",
            message or "assertNear failed",
            expected, actual, diff, tolerance
        ))
    end
end

-- Entity factory helpers for testing
function helpers.createMovingEntity(x, y, vx, vy)
    return { x = x, y = y, vx = vx, vy = vy }
end

function helpers.createBouncingEntity(x, y, vx, vy)
    return { x = x, y = y, vx = vx, vy = vy, Bounces = {} }
end

function helpers.createSeekingEntity(x, y, target, speed)
    return {
        x = x, y = y,
        vx = 0, vy = 0,
        SeeksTarget = { target = target, speed = speed or 100 }
    }
end

function helpers.createPlayerInputEntity(x, y, speed)
    return {
        x = x, y = y,
        vx = 0, vy = 0,
        PlayerInput = { speed = speed or 200 }
    }
end

return helpers
