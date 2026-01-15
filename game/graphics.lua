local graphics = {}

-- Sketchy style - rough, hand-drawn look with visible line breaks
function graphics.drawSketchy(x, y, radius, color, time)
    time = time or love.timer.getTime()
    local r, g, b = color[1], color[2], color[3]

    -- Tight parameters
    local strokes = 7
    local arcLen = 0.6
    local jitter = 0.02
    local speed = 3
    local lineWidth = 1.5
    local innerStrokes = 4

    love.graphics.setColor(r, g, b, 1)
    love.graphics.setLineWidth(lineWidth)

    -- Draw several arcs that don't quite connect
    for i = 1, strokes do
        local startAngle = (i / strokes) * math.pi * 2 + math.sin(time * speed + i) * 0.2
        local arcLength = math.pi * arcLen + math.sin(time * (speed + 1) + i * 2) * 0.3

        -- Slight radius variation per stroke
        local strokeRadius = radius * (0.95 + math.sin(time + i * 1.5) * 0.08)

        -- Draw arc as line segments
        local segments = 12
        local verts = {}
        for j = 0, segments do
            local angle = startAngle + (j / segments) * arcLength
            local jit = math.sin(time * (speed * 4) + j * 3 + i) * radius * jitter
            table.insert(verts, x + math.cos(angle) * (strokeRadius + jit))
            table.insert(verts, y + math.sin(angle) * (strokeRadius + jit))
        end
        if #verts >= 4 then
            love.graphics.line(verts)
        end
    end

    -- Inner sketchy detail
    love.graphics.setColor(r, g, b, 0.4)
    for i = 1, innerStrokes do
        local startAngle = (i / innerStrokes) * math.pi * 2 + time * 0.5
        local arcLength = math.pi * 0.4
        local innerRadius = radius * 0.5

        local segments = 8
        local verts = {}
        for j = 0, segments do
            local angle = startAngle + (j / segments) * arcLength
            local jit = math.sin(time * (speed * 3) + j * 2 + i) * radius * jitter * 0.75
            table.insert(verts, x + math.cos(angle) * (innerRadius + jit))
            table.insert(verts, y + math.sin(angle) * (innerRadius + jit))
        end
        if #verts >= 4 then
            love.graphics.line(verts)
        end
    end

    love.graphics.setLineWidth(1)
end

-- Sparkle style for experience orbs - pulsing star with shimmer
function graphics.drawSparkle(x, y, radius, color, time)
    time = time or love.timer.getTime()
    local r, g, b = color[1], color[2], color[3]

    -- Gentle pulsing size
    local pulse = 0.9 + 0.1 * math.sin(time * 3)
    local size = radius * pulse

    -- Rotating 4-point star
    local rotation = time * 2
    local points = 4

    love.graphics.setLineWidth(1.5)

    -- Outer star rays
    love.graphics.setColor(r, g, b, 0.4)
    for i = 1, points do
        local angle = rotation + (i / points) * math.pi * 2
        local rayLen = size * 2.5
        local x2 = x + math.cos(angle) * rayLen
        local y2 = y + math.sin(angle) * rayLen
        love.graphics.line(x, y, x2, y2)
    end

    -- Inner star (offset 45 degrees)
    love.graphics.setColor(r, g, b, 1)
    local verts = {}
    for i = 1, points * 2 do
        local angle = rotation + (i / (points * 2)) * math.pi * 2
        local len = (i % 2 == 1) and size * 1.5 or size * 0.5
        table.insert(verts, x + math.cos(angle) * len)
        table.insert(verts, y + math.sin(angle) * len)
    end
    love.graphics.polygon("line", verts)

    -- Center dot
    love.graphics.setColor(r, g, b, 0.8)
    love.graphics.circle("fill", x, y, size * 0.3)

    love.graphics.setLineWidth(1)
end

-- Sketchy turret - center with direction lines
function graphics.drawTurret(x, y, radius, color, directions, lineLength, time)
    time = time or love.timer.getTime()
    local r, g, b = color[1], color[2], color[3]

    -- Draw sketchy direction lines
    love.graphics.setColor(r, g, b, 1)
    love.graphics.setLineWidth(2)
    for i, dir in ipairs(directions) do
        local jitX = math.sin(time * 4 + i) * 2
        local jitY = math.cos(time * 3.5 + i) * 2
        local endX = x + dir[1] * lineLength + jitX
        local endY = y + dir[2] * lineLength + jitY
        love.graphics.line(x, y, endX, endY)
    end

    -- Draw sketchy center
    graphics.drawSketchy(x, y, radius, color, time)
end

-- Sketchy oval for carrier
function graphics.drawOval(x, y, width, height, color, time)
    time = time or love.timer.getTime()
    local r, g, b = color[1], color[2], color[3]

    local strokes = 6
    local jitter = 0.02
    local speed = 2

    love.graphics.setColor(r, g, b, 1)
    love.graphics.setLineWidth(1.5)

    -- Draw sketchy oval arcs
    for i = 1, strokes do
        local startAngle = (i / strokes) * math.pi * 2 + math.sin(time * speed + i) * 0.2
        local arcLength = math.pi * 0.55 + math.sin(time * (speed + 1) + i * 2) * 0.2

        local segments = 12
        local verts = {}
        for j = 0, segments do
            local angle = startAngle + (j / segments) * arcLength
            local jitAmount = math.sin(time * (speed * 4) + j * 3 + i) * jitter
            local rx = (width / 2) * (1 + jitAmount)
            local ry = (height / 2) * (1 + jitAmount)
            table.insert(verts, x + math.cos(angle) * rx)
            table.insert(verts, y + math.sin(angle) * ry)
        end
        if #verts >= 4 then
            love.graphics.line(verts)
        end
    end

    -- Inner detail
    love.graphics.setColor(r, g, b, 0.4)
    for i = 1, 3 do
        local startAngle = (i / 3) * math.pi * 2 + time * 0.5
        local arcLength = math.pi * 0.35

        local segments = 8
        local verts = {}
        for j = 0, segments do
            local angle = startAngle + (j / segments) * arcLength
            local rx = (width / 2) * 0.5
            local ry = (height / 2) * 0.5
            table.insert(verts, x + math.cos(angle) * rx)
            table.insert(verts, y + math.sin(angle) * ry)
        end
        if #verts >= 4 then
            love.graphics.line(verts)
        end
    end

    love.graphics.setLineWidth(1)
end

-- Sketchy mine with blast radius indicator
function graphics.drawMine(x, y, radius, blastRadius, color, triggered, time)
    time = time or love.timer.getTime()
    local r, g, b = color[1], color[2], color[3]

    -- Draw blast radius indicator when triggered
    if triggered then
        love.graphics.setColor(r, g, b, 0.15)
        love.graphics.setLineWidth(1)
        -- Sketchy blast radius circle
        local segments = 16
        local verts = {}
        for i = 0, segments do
            local angle = (i / segments) * math.pi * 2
            local jit = math.sin(time * 8 + i * 2) * blastRadius * 0.03
            table.insert(verts, x + math.cos(angle) * (blastRadius + jit))
            table.insert(verts, y + math.sin(angle) * (blastRadius + jit))
        end
        love.graphics.polygon("line", verts)
    end

    -- Draw sketchy mine body
    graphics.drawSketchy(x, y, radius, color, time)
end

-- Main draw function
function graphics.drawCircle(x, y, radius, color, style, options)
    options = options or {}
    graphics.drawSketchy(x, y, radius, color, options.time)
end

return graphics
