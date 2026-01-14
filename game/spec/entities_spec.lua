-- Entity factory tests
package.path = package.path .. ";game/?.lua;game/?/init.lua"

local lu = require("spec.luaunit")
local entities = require("entities")

TestEntities = {}

-- Player tests
function TestEntities:testCreatePlayerPosition()
    local player = entities.createPlayer(100, 200)

    lu.assertEquals(player.x, 100)
    lu.assertEquals(player.y, 200)
end

function TestEntities:testCreatePlayerHasRequiredComponents()
    local player = entities.createPlayer(0, 0)

    lu.assertNotNil(player.Health)
    lu.assertNotNil(player.Collider)
    lu.assertNotNil(player.PlayerInput)
    lu.assertNotNil(player.ArenaClamp)
    lu.assertNotNil(player.Render)
    lu.assertEquals(player.vx, 0)
    lu.assertEquals(player.vy, 0)
end

function TestEntities:testCreatePlayerHealth()
    local player = entities.createPlayer(0, 0)

    lu.assertEquals(player.Health.current, player.Health.max)
    lu.assertTrue(player.Health.max > 0)
end

-- Enemy tests
function TestEntities:testCreateEnemyPosition()
    local target = { x = 0, y = 0 }
    local enemy = entities.createEnemy(50, 75, target)

    lu.assertEquals(enemy.x, 50)
    lu.assertEquals(enemy.y, 75)
end

function TestEntities:testCreateEnemyHasRequiredComponents()
    local target = { x = 0, y = 0 }
    local enemy = entities.createEnemy(0, 0, target)

    lu.assertNotNil(enemy.Collider)
    lu.assertNotNil(enemy.SeeksTarget)
    lu.assertNotNil(enemy.DamagesPlayer)
    lu.assertNotNil(enemy.Render)
    lu.assertEquals(enemy.SeeksTarget.target, target)
end

function TestEntities:testCreateEnemyDamagesPlayer()
    local target = { x = 0, y = 0 }
    local enemy = entities.createEnemy(0, 0, target)

    lu.assertTrue(enemy.DamagesPlayer.amount > 0)
end

-- Projectile tests
function TestEntities:testCreateProjectilePosition()
    local proj = entities.createProjectile(100, 200, 1, 0)

    lu.assertEquals(proj.x, 100)
    lu.assertEquals(proj.y, 200)
end

function TestEntities:testCreateProjectileVelocityNormalized()
    local proj = entities.createProjectile(0, 0, 3, 4)

    -- Direction (3,4) has length 5, should normalize to speed
    local speed = entities.config.projectile.speed
    local expectedVx = (3/5) * speed
    local expectedVy = (4/5) * speed

    lu.assertAlmostEquals(proj.vx, expectedVx, 0.01)
    lu.assertAlmostEquals(proj.vy, expectedVy, 0.01)
end

function TestEntities:testCreateProjectileHasRequiredComponents()
    local proj = entities.createProjectile(0, 0, 1, 0)

    lu.assertNotNil(proj.Collider)
    lu.assertNotNil(proj.Bounces)
    lu.assertNotNil(proj.Lifetime)
    lu.assertNotNil(proj.DamagesEnemy)
    lu.assertNotNil(proj.Render)
end

function TestEntities:testCreateProjectileLifetime()
    local proj = entities.createProjectile(0, 0, 1, 0)

    lu.assertTrue(proj.Lifetime.remaining > 0)
end

function TestEntities:testCreateProjectileZeroDirection()
    local proj = entities.createProjectile(0, 0, 0, 0)

    lu.assertEquals(proj.vx, 0)
    lu.assertEquals(proj.vy, 0)
end

-- Spawn at edge tests
function TestEntities:testSpawnEnemyAtEdgeInArena()
    local arena = { x = 50, y = 50, width = 700, height = 500 }
    local target = { x = 400, y = 300 }

    -- Use deterministic RNG for testing
    local callCount = 0
    local function mockRng(min, max)
        callCount = callCount + 1
        if min and max then
            return min  -- Always return first side (top)
        else
            return 0.5  -- Return middle position
        end
    end

    local enemy = entities.spawnEnemyAtEdge(arena, target, mockRng)

    -- Should be within arena bounds
    lu.assertTrue(enemy.x >= arena.x)
    lu.assertTrue(enemy.x <= arena.x + arena.width)
    lu.assertTrue(enemy.y >= arena.y)
    lu.assertTrue(enemy.y <= arena.y + arena.height)
end

function TestEntities:testSpawnEnemyAtEdgeSeeksTarget()
    local arena = { x = 0, y = 0, width = 100, height = 100 }
    local target = { x = 50, y = 50 }

    local enemy = entities.spawnEnemyAtEdge(arena, target)

    lu.assertEquals(enemy.SeeksTarget.target, target)
end

-- Config exposure tests
function TestEntities:testConfigIsExposed()
    lu.assertNotNil(entities.config)
    lu.assertNotNil(entities.config.player)
    lu.assertNotNil(entities.config.enemy)
    lu.assertNotNil(entities.config.projectile)
end

os.exit(lu.LuaUnit.run())
