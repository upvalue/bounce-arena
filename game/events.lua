-- Simple event bus for decoupled communication
-- Allows systems to communicate without direct coupling

local events = {}

-- Internal state
events.listeners = {}

-- Register a listener for an event
-- Returns an unsubscribe function
function events.on(event, callback)
    events.listeners[event] = events.listeners[event] or {}
    table.insert(events.listeners[event], callback)

    -- Return unsubscribe function
    return function()
        events.off(event, callback)
    end
end

-- Remove a listener
function events.off(event, callback)
    local listeners = events.listeners[event]
    if not listeners then return end

    for i = #listeners, 1, -1 do
        if listeners[i] == callback then
            table.remove(listeners, i)
            break
        end
    end
end

-- Emit an event to all listeners
function events.emit(event, ...)
    local listeners = events.listeners[event]
    if not listeners then return end

    for _, callback in ipairs(listeners) do
        callback(...)
    end
end

-- Clear all listeners (useful for testing)
function events.clear()
    events.listeners = {}
end

-- Clear listeners for a specific event
function events.clearEvent(event)
    events.listeners[event] = nil
end

-- Get listener count for an event (useful for testing)
function events.listenerCount(event)
    local listeners = events.listeners[event]
    return listeners and #listeners or 0
end

return events
