-- Input abstraction layer
-- Decouples game logic from Love2D input APIs for testability

local input = {}

-- Internal state that can be manipulated for testing
input.state = {
    up = false,
    down = false,
    left = false,
    right = false,
    shift = false
}

input.mouse = {
    x = 0,
    y = 0,
    buttons = {}
}

-- Update input state from Love2D (call this in love.update)
function input.update()
    if love and love.keyboard then
        input.state.up = love.keyboard.isDown("w", "up")
        input.state.down = love.keyboard.isDown("s", "down")
        input.state.left = love.keyboard.isDown("a", "left")
        input.state.right = love.keyboard.isDown("d", "right")
        input.state.shift = love.keyboard.isDown("lshift", "rshift")
    end

    if love and love.mouse then
        input.mouse.x, input.mouse.y = love.mouse.getPosition()
    end
end

-- Check if a direction is pressed
function input.isDown(key)
    return input.state[key] or false
end

-- Get mouse position
function input.getMousePosition()
    return input.mouse.x, input.mouse.y
end

-- Check if mouse button is pressed
function input.isMouseDown(button)
    return input.mouse.buttons[button] or false
end

-- For testing: reset all input state
function input.reset()
    input.state = {
        up = false,
        down = false,
        left = false,
        right = false,
        shift = false
    }
    input.mouse = {
        x = 0,
        y = 0,
        buttons = {}
    }
end

-- For testing: set specific input state
function input.setState(newState)
    for k, v in pairs(newState) do
        input.state[k] = v
    end
end

-- For testing: set mouse state
function input.setMouse(x, y, buttons)
    input.mouse.x = x or input.mouse.x
    input.mouse.y = y or input.mouse.y
    if buttons then
        input.mouse.buttons = buttons
    end
end

return input
