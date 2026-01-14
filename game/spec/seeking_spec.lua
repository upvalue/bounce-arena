-- Seeking system tests
package.path = package.path .. ";game/?.lua;game/?/init.lua"

local lu = require("spec.luaunit")
local helpers = require("spec.helpers")

-- Load systems (need to mock love first)
_G.love = { keyboard = { isDown = function() return false end } }
local systems = require("systems")

TestSeeking = {}

function TestSeeking:testSeeksTowardTarget()
    local target = { x = 100, y = 0 }
    local e = helpers.createSeekingEntity(0, 0, target, 100)

    helpers.processSystem(systems.seeking, {e}, 1.0)

    -- Should move toward target (positive x direction)
    lu.assertEquals(e.vx, 100)
    lu.assertEquals(e.vy, 0)
end

function TestSeeking:testSeeksDiagonally()
    local target = { x = 100, y = 100 }
    local e = helpers.createSeekingEntity(0, 0, target, 100)

    helpers.processSystem(systems.seeking, {e}, 1.0)

    -- Should normalize diagonal movement
    -- Distance is sqrt(2) * 100, so velocity should be 100/sqrt(2) each axis
    local expected = 100 / math.sqrt(2)
    helpers.assertNear(e.vx, expected, 0.01, "vx")
    helpers.assertNear(e.vy, expected, 0.01, "vy")
end

function TestSeeking:testSeeksNegativeDirection()
    local target = { x = -50, y = -50 }
    local e = helpers.createSeekingEntity(0, 0, target, 100)

    helpers.processSystem(systems.seeking, {e}, 1.0)

    lu.assertTrue(e.vx < 0, "vx should be negative")
    lu.assertTrue(e.vy < 0, "vy should be negative")
end

function TestSeeking:testNoMovementWhenOnTarget()
    local target = { x = 50, y = 50 }
    local e = helpers.createSeekingEntity(50, 50, target, 100)

    helpers.processSystem(systems.seeking, {e}, 1.0)

    -- When on target, velocity should remain unchanged (dist = 0)
    lu.assertEquals(e.vx, 0)
    lu.assertEquals(e.vy, 0)
end

function TestSeeking:testNoMovementWhenNoTarget()
    local e = {
        x = 0, y = 0,
        vx = 50, vy = 50,
        SeeksTarget = { target = nil, speed = 100 }
    }

    helpers.processSystem(systems.seeking, {e}, 1.0)

    -- Velocity should remain unchanged when no target
    lu.assertEquals(e.vx, 50)
    lu.assertEquals(e.vy, 50)
end

function TestSeeking:testSpeedIsRespected()
    local target = { x = 100, y = 0 }
    local slow = helpers.createSeekingEntity(0, 0, target, 50)
    local fast = helpers.createSeekingEntity(0, 0, target, 200)

    helpers.processSystem(systems.seeking, {slow, fast}, 1.0)

    lu.assertEquals(slow.vx, 50)
    lu.assertEquals(fast.vx, 200)
end

os.exit(lu.LuaUnit.run())
