-- Movement system tests
package.path = package.path .. ";game/?.lua;game/?/init.lua"

local lu = require("spec.luaunit")
local helpers = require("spec.helpers")

-- Load systems (need to mock love first)
_G.love = { keyboard = { isDown = function() return false end } }
local systems = require("systems")

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

function TestMovement:testMultipleEntities()
    local e1 = helpers.createMovingEntity(0, 0, 10, 0)
    local e2 = helpers.createMovingEntity(100, 100, -10, -10)

    helpers.processSystem(systems.movement, {e1, e2}, 1.0)

    lu.assertEquals(e1.x, 10)
    lu.assertEquals(e1.y, 0)
    lu.assertEquals(e2.x, 90)
    lu.assertEquals(e2.y, 90)
end

os.exit(lu.LuaUnit.run())
