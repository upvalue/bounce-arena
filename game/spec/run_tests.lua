#!/usr/bin/env lua
-- Test runner for all specs
-- Usage: lua game/spec/run_tests.lua

package.path = package.path .. ";game/?.lua;game/?/init.lua"

local lu = require("spec.luaunit")
local helpers = require("spec.helpers")

-- Mock love framework before loading systems
_G.love = {
    keyboard = { isDown = function() return false end },
    mouse = { getPosition = function() return 0, 0 end },
    graphics = {
        setColor = function() end,
        circle = function() end,
        rectangle = function() end,
        line = function() end,
        print = function() end
    }
}

-- Load modules
local input = require("input")
local events = require("events")
local systems = require("systems")
local entities = require("entities")

-- ============================================
-- Movement System Tests
-- ============================================
TestMovement = {}

function TestMovement:testAppliesVelocityToPosition()
    local e = helpers.createMovingEntity(0, 0, 100, 50)
    helpers.processSystem(systems.movement, {e}, 1.0)
    lu.assertEquals(e.x, 100)
    lu.assertEquals(e.y, 50)
end

function TestMovement:testAppliesVelocityWithDeltaTime()
    local e = helpers.createMovingEntity(0, 0, 100, 100)
    helpers.processSystem(systems.movement, {e}, 0.5)
    lu.assertEquals(e.x, 50)
    lu.assertEquals(e.y, 50)
end

function TestMovement:testNegativeVelocity()
    local e = helpers.createMovingEntity(100, 100, -50, -25)
    helpers.processSystem(systems.movement, {e}, 1.0)
    lu.assertEquals(e.x, 50)
    lu.assertEquals(e.y, 75)
end

function TestMovement:testZeroVelocity()
    local e = helpers.createMovingEntity(50, 50, 0, 0)
    helpers.processSystem(systems.movement, {e}, 1.0)
    lu.assertEquals(e.x, 50)
    lu.assertEquals(e.y, 50)
end

-- ============================================
-- Seeking System Tests
-- ============================================
TestSeeking = {}

function TestSeeking:testSeeksTowardTarget()
    local target = { x = 100, y = 0 }
    local e = helpers.createSeekingEntity(0, 0, target, 100)
    helpers.processSystem(systems.seeking, {e}, 1.0)
    lu.assertEquals(e.vx, 100)
    lu.assertEquals(e.vy, 0)
end

function TestSeeking:testSeeksDiagonally()
    local target = { x = 100, y = 100 }
    local e = helpers.createSeekingEntity(0, 0, target, 100)
    helpers.processSystem(systems.seeking, {e}, 1.0)
    local expected = 100 / math.sqrt(2)
    helpers.assertNear(e.vx, expected, 0.01, "vx")
    helpers.assertNear(e.vy, expected, 0.01, "vy")
end

function TestSeeking:testNoMovementWhenOnTarget()
    local target = { x = 50, y = 50 }
    local e = helpers.createSeekingEntity(50, 50, target, 100)
    helpers.processSystem(systems.seeking, {e}, 1.0)
    lu.assertEquals(e.vx, 0)
    lu.assertEquals(e.vy, 0)
end

function TestSeeking:testNoMovementWhenNoTarget()
    local e = {
        x = 0, y = 0, vx = 50, vy = 50,
        SeeksTarget = { target = nil, speed = 100 }
    }
    helpers.processSystem(systems.seeking, {e}, 1.0)
    lu.assertEquals(e.vx, 50)
    lu.assertEquals(e.vy, 50)
end

-- ============================================
-- Entity Factory Tests
-- ============================================
TestEntities = {}

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
end

function TestEntities:testCreateEnemySeeksTarget()
    local target = { x = 0, y = 0 }
    local enemy = entities.createEnemy(50, 75, target)
    lu.assertEquals(enemy.SeeksTarget.target, target)
end

function TestEntities:testCreateProjectileVelocityNormalized()
    local proj = entities.createProjectile(0, 0, 3, 4)
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
end

function TestEntities:testSpawnEnemyAtEdgeInArena()
    local arena = { x = 50, y = 50, width = 700, height = 500 }
    local target = { x = 400, y = 300 }
    local function mockRng(min, max)
        if min and max then return min end
        return 0.5
    end
    local enemy = entities.spawnEnemyAtEdge(arena, target, mockRng)
    lu.assertTrue(enemy.x >= arena.x)
    lu.assertTrue(enemy.x <= arena.x + arena.width)
    lu.assertTrue(enemy.y >= arena.y)
    lu.assertTrue(enemy.y <= arena.y + arena.height)
end

function TestEntities:testConfigIsExposed()
    lu.assertNotNil(entities.config)
    lu.assertNotNil(entities.config.player)
    lu.assertNotNil(entities.config.enemies)
    lu.assertNotNil(entities.config.projectile)
end

-- ============================================
-- Bounce System Tests
-- ============================================
TestBounce = {}

function TestBounce:testBouncesOffLeftWall()
    local arena = { x = 0, y = 0, width = 100, height = 100 }
    local e = helpers.createBouncingEntity(-5, 50, -100, 0)

    local world = helpers.createMockWorld(arena)
    helpers.processSystem(systems.bounce, {e}, 1.0, world)

    lu.assertTrue(e.vx > 0, "velocity should reverse")
    lu.assertTrue(e.x >= arena.x, "position should be clamped inside")
end

function TestBounce:testBouncesOffRightWall()
    local arena = { x = 0, y = 0, width = 100, height = 100 }
    local e = helpers.createBouncingEntity(105, 50, 100, 0)

    local world = helpers.createMockWorld(arena)
    helpers.processSystem(systems.bounce, {e}, 1.0, world)

    lu.assertTrue(e.vx < 0, "velocity should reverse")
    lu.assertTrue(e.x <= arena.x + arena.width, "position should be clamped inside")
end

function TestBounce:testBouncesOffTopWall()
    local arena = { x = 0, y = 0, width = 100, height = 100 }
    local e = helpers.createBouncingEntity(50, -5, 0, -100)

    local world = helpers.createMockWorld(arena)
    helpers.processSystem(systems.bounce, {e}, 1.0, world)

    lu.assertTrue(e.vy > 0, "velocity should reverse")
end

function TestBounce:testBouncesOffBottomWall()
    local arena = { x = 0, y = 0, width = 100, height = 100 }
    local e = helpers.createBouncingEntity(50, 105, 0, 100)

    local world = helpers.createMockWorld(arena)
    helpers.processSystem(systems.bounce, {e}, 1.0, world)

    lu.assertTrue(e.vy < 0, "velocity should reverse")
end

function TestBounce:testNoBounceWhenInsideArena()
    local arena = { x = 0, y = 0, width = 100, height = 100 }
    local e = helpers.createBouncingEntity(50, 50, 100, 100)

    local world = helpers.createMockWorld(arena)
    helpers.processSystem(systems.bounce, {e}, 1.0, world)

    lu.assertEquals(e.vx, 100)
    lu.assertEquals(e.vy, 100)
end

-- ============================================
-- Lifetime System Tests
-- ============================================
TestLifetime = {}

function TestLifetime:testDecrementsLifetime()
    local e = { Lifetime = { remaining = 5.0 } }
    local world = helpers.createMockWorld()
    helpers.processSystem(systems.lifetime, {e}, 1.0, world)

    lu.assertEquals(e.Lifetime.remaining, 4.0)
end

function TestLifetime:testRemovesEntityWhenExpired()
    local e = { Lifetime = { remaining = 0.5 } }
    local world = helpers.createMockWorld()
    helpers.processSystem(systems.lifetime, {e}, 1.0, world)

    lu.assertEquals(#world.removed, 1)
    lu.assertEquals(world.removed[1], e)
end

function TestLifetime:testDoesNotRemoveEntityWithRemainingTime()
    local e = { Lifetime = { remaining = 5.0 } }
    local world = helpers.createMockWorld()
    helpers.processSystem(systems.lifetime, {e}, 1.0, world)

    lu.assertEquals(#world.removed, 0)
end

-- ============================================
-- Input Abstraction Tests
-- ============================================
TestInput = {}

function TestInput:setUp()
    input.reset()
end

function TestInput:testIsDownReturnsFalseByDefault()
    lu.assertFalse(input.isDown("up"))
    lu.assertFalse(input.isDown("down"))
    lu.assertFalse(input.isDown("left"))
    lu.assertFalse(input.isDown("right"))
end

function TestInput:testSetStateUpdatesInput()
    input.setState({ up = true, left = true })
    lu.assertTrue(input.isDown("up"))
    lu.assertTrue(input.isDown("left"))
    lu.assertFalse(input.isDown("down"))
    lu.assertFalse(input.isDown("right"))
end

function TestInput:testResetClearsState()
    input.setState({ up = true, down = true })
    input.reset()
    lu.assertFalse(input.isDown("up"))
    lu.assertFalse(input.isDown("down"))
end

function TestInput:testGetMousePosition()
    input.setMouse(100, 200)
    local x, y = input.getMousePosition()
    lu.assertEquals(x, 100)
    lu.assertEquals(y, 200)
end

-- ============================================
-- Player Input System Tests
-- ============================================
TestPlayerInput = {}

function TestPlayerInput:setUp()
    input.reset()
end

function TestPlayerInput:testNoMovementWhenNoInput()
    local e = helpers.createPlayerInputEntity(50, 50, 200)
    helpers.processSystem(systems.playerInput, {e}, 1.0)

    lu.assertEquals(e.vx, 0)
    lu.assertEquals(e.vy, 0)
end

function TestPlayerInput:testMoveUp()
    input.setState({ up = true })
    local e = helpers.createPlayerInputEntity(50, 50, 200)
    helpers.processSystem(systems.playerInput, {e}, 1.0)

    lu.assertEquals(e.vx, 0)
    lu.assertEquals(e.vy, -200)
end

function TestPlayerInput:testMoveDown()
    input.setState({ down = true })
    local e = helpers.createPlayerInputEntity(50, 50, 200)
    helpers.processSystem(systems.playerInput, {e}, 1.0)

    lu.assertEquals(e.vx, 0)
    lu.assertEquals(e.vy, 200)
end

function TestPlayerInput:testMoveLeft()
    input.setState({ left = true })
    local e = helpers.createPlayerInputEntity(50, 50, 200)
    helpers.processSystem(systems.playerInput, {e}, 1.0)

    lu.assertEquals(e.vx, -200)
    lu.assertEquals(e.vy, 0)
end

function TestPlayerInput:testMoveRight()
    input.setState({ right = true })
    local e = helpers.createPlayerInputEntity(50, 50, 200)
    helpers.processSystem(systems.playerInput, {e}, 1.0)

    lu.assertEquals(e.vx, 200)
    lu.assertEquals(e.vy, 0)
end

function TestPlayerInput:testDiagonalMovementNormalized()
    input.setState({ up = true, right = true })
    local e = helpers.createPlayerInputEntity(50, 50, 200)
    helpers.processSystem(systems.playerInput, {e}, 1.0)

    -- Diagonal should be normalized (0.7071 factor)
    local expected = 200 * 0.7071
    helpers.assertNear(e.vx, expected, 0.1, "vx")
    helpers.assertNear(e.vy, -expected, 0.1, "vy")
end

function TestPlayerInput:testSpeedConfigurable()
    input.setState({ right = true })
    local slowEntity = helpers.createPlayerInputEntity(0, 0, 100)
    local fastEntity = helpers.createPlayerInputEntity(0, 0, 400)

    helpers.processSystem(systems.playerInput, {slowEntity, fastEntity}, 1.0)

    lu.assertEquals(slowEntity.vx, 100)
    lu.assertEquals(fastEntity.vx, 400)
end

-- ============================================
-- Event System Tests
-- ============================================
TestEvents = {}

function TestEvents:setUp()
    events.clear()
end

function TestEvents:testEmitCallsListeners()
    local called = false
    events.on("test", function()
        called = true
    end)
    events.emit("test")
    lu.assertTrue(called)
end

function TestEvents:testEmitPassesArguments()
    local receivedData = nil
    events.on("test", function(data)
        receivedData = data
    end)
    events.emit("test", { value = 42 })
    lu.assertEquals(receivedData.value, 42)
end

function TestEvents:testMultipleListeners()
    local count = 0
    events.on("test", function() count = count + 1 end)
    events.on("test", function() count = count + 1 end)
    events.emit("test")
    lu.assertEquals(count, 2)
end

function TestEvents:testOnReturnsUnsubscribe()
    local called = false
    local unsubscribe = events.on("test", function()
        called = true
    end)
    unsubscribe()
    events.emit("test")
    lu.assertFalse(called)
end

function TestEvents:testClearRemovesAllListeners()
    events.on("test1", function() end)
    events.on("test2", function() end)
    events.clear()
    lu.assertEquals(events.listenerCount("test1"), 0)
    lu.assertEquals(events.listenerCount("test2"), 0)
end

function TestEvents:testListenerCount()
    lu.assertEquals(events.listenerCount("test"), 0)
    events.on("test", function() end)
    lu.assertEquals(events.listenerCount("test"), 1)
    events.on("test", function() end)
    lu.assertEquals(events.listenerCount("test"), 2)
end

function TestEvents:testNoErrorWhenEmittingUnknownEvent()
    -- Should not throw
    events.emit("nonexistent", { data = "test" })
    lu.assertTrue(true)
end

-- ============================================
-- Collision System with Events Tests
-- ============================================
TestCollisionEvents = {}

function TestCollisionEvents:setUp()
    events.clear()
end

function TestCollisionEvents:testEmitsEnemyHitPlayerEvent()
    local receivedEvent = nil
    events.on("collision", function(data)
        receivedEvent = data
    end)

    -- Create player and enemy at same position (colliding)
    local player = {
        x = 50, y = 50,
        Collider = { radius = 10 },
        PlayerInput = { speed = 200 },
        Health = { current = 10, max = 10 }
    }
    local enemy = {
        x = 50, y = 50,
        Collider = { radius = 10 },
        DamagesPlayer = { amount = 1 }
    }

    -- Set up collision system
    local world = helpers.createMockWorld()
    systems.collision:onAddToWorld(world)
    systems.collision:onAdd(player)
    systems.collision:onAdd(enemy)
    systems.collision.world = world

    systems.collision:update(1/60)

    lu.assertNotNil(receivedEvent)
    lu.assertEquals(receivedEvent.type, "enemy_hit_player")
    lu.assertEquals(receivedEvent.enemy, enemy)
    lu.assertEquals(receivedEvent.player, player)
    lu.assertEquals(receivedEvent.damage, 1)
end

function TestCollisionEvents:testEmitsProjectileHitEnemyEvent()
    local receivedEvent = nil
    events.on("collision", function(data)
        receivedEvent = data
    end)

    -- Create enemy and projectile at same position (colliding)
    local player = {
        x = 0, y = 0,
        Collider = { radius = 10 },
        PlayerInput = { speed = 200 },
        Health = { current = 10, max = 10 }
    }
    local enemy = {
        x = 100, y = 100,
        Collider = { radius = 10 },
        DamagesPlayer = { amount = 1 }
    }
    local projectile = {
        x = 100, y = 100,
        Collider = { radius = 5 },
        DamagesEnemy = { amount = 1 }
    }

    -- Set up collision system
    local world = helpers.createMockWorld()
    systems.collision:onAddToWorld(world)
    systems.collision:onAdd(player)
    systems.collision:onAdd(enemy)
    systems.collision:onAdd(projectile)
    systems.collision.world = world

    systems.collision:update(1/60)

    lu.assertNotNil(receivedEvent)
    lu.assertEquals(receivedEvent.type, "projectile_hit_enemy")
    lu.assertEquals(receivedEvent.projectile, projectile)
    lu.assertEquals(receivedEvent.enemy, enemy)
end

function TestCollisionEvents:testNoEventWhenNoCollision()
    local eventFired = false
    events.on("collision", function()
        eventFired = true
    end)

    -- Create player and enemy far apart (not colliding)
    local player = {
        x = 0, y = 0,
        Collider = { radius = 10 },
        PlayerInput = { speed = 200 },
        Health = { current = 10, max = 10 }
    }
    local enemy = {
        x = 100, y = 100,
        Collider = { radius = 10 },
        DamagesPlayer = { amount = 1 }
    }

    -- Set up collision system
    local world = helpers.createMockWorld()
    systems.collision:onAddToWorld(world)
    systems.collision:onAdd(player)
    systems.collision:onAdd(enemy)
    systems.collision.world = world

    systems.collision:update(1/60)

    lu.assertFalse(eventFired)
end

-- Run all tests
os.exit(lu.LuaUnit.run())
