local tiny = require("lib.tiny")
local systems = require("systems")
local entities = require("entities")
local config = require("config")
local input = require("input")
local events = require("events")

-- Game state: "intro", "playing", "paused", "gameover", or "won"
local gameState = "intro"

-- Game tracking
local score = 0
local currentWave = 0
local gameTime = 0
local enemiesAlive = 0
local projectilesActive = 0

-- Fonts
local titleFont
local storyFont
local promptFont
local gameFont

-- ECS world
local world
local player

local function spawnWave(waveConfig)
    local arena = config.arena
    currentWave = currentWave + 1

    -- Spawn each enemy type
    for typeName, count in pairs(waveConfig) do
        if typeName ~= "start" then
            local enemyType = config.enemies[typeName]
            if enemyType then
                for i = 1, count do
                    local enemy = entities.spawnEnemyAtEdge(arena, player, nil, enemyType)
                    world:addEntity(enemy)
                    enemiesAlive = enemiesAlive + 1
                end
            end
        end
    end
end

local function startGame()
    local arena = config.arena

    -- Reset game state
    score = 0
    currentWave = 0
    gameTime = 0
    enemiesAlive = 0
    projectilesActive = 0
    events.clear()

    -- Create ECS world once, or clear existing entities
    if world then
        world:clearEntities()
    else
        world = tiny.world()
        world.arena = arena
        world.config = config

        -- Add systems in order (update systems first, then render systems)
        world:addSystem(systems.playerInput)
        world:addSystem(systems.seeking)
        world:addSystem(systems.attraction)
        world:addSystem(systems.movement)
        world:addSystem(systems.bounce)
        world:addSystem(systems.arenaClamp)
        world:addSystem(systems.lifetime)
        world:addSystem(systems.damageCooldown)
        world:addSystem(systems.invulnerability)
        world:addSystem(systems.flash)
        world:addSystem(systems.collision)
        world:addSystem(systems.render)
        world:addSystem(systems.aimingLine)
        world:addSystem(systems.hud)
    end

    -- Create player at center
    player = entities.createPlayer(
        arena.x + arena.width / 2,
        arena.y + arena.height / 2
    )
    world:addEntity(player)

    -- Helper to flash an entity red
    local function flashEntity(entity)
        entity.Flash = {
            remaining = config.effects.flashDuration,
            color = config.effects.flashColor
        }
        world:addEntity(entity)  -- refresh so flash system picks it up
    end

    -- Helper to make player invulnerable
    local function makeInvulnerable(p)
        p.Invulnerable = {
            remaining = config.invuln.duration,
            flashTimer = 0  -- flash immediately
        }
        world:addEntity(p)  -- refresh for invuln system
    end

    -- Set up collision event handlers
    events.on("collision", function(data)
        if data.type == "enemy_hit_player" then
            data.player.Health.current = data.player.Health.current - data.damage
            flashEntity(data.player)
            makeInvulnerable(data.player)
        elseif data.type == "projectile_hit_player" then
            data.player.Health.current = data.player.Health.current - data.damage
            flashEntity(data.player)
            makeInvulnerable(data.player)
            projectilesActive = projectilesActive - 1
        elseif data.type == "projectile_hit_enemy" then
            if data.projectileDestroyed then
                projectilesActive = projectilesActive - 1
            end

            if data.killed then
                enemiesAlive = enemiesAlive - 1
                -- Spawn experience at enemy position with enemy's exp value
                local exp = entities.createExperience(data.enemy.x, data.enemy.y, player, data.enemy.expValue)
                world:addEntity(exp)
            else
                -- Enemy survived, flash it
                flashEntity(data.enemy)
            end
        elseif data.type == "experience_collected" then
            score = score + data.value
            -- Grow player
            local growth = config.experience.growthAmount
            player.Collider.radius = player.Collider.radius + growth
            player.Render.radius = player.Render.radius + growth
            player.ArenaClamp.margin = player.ArenaClamp.margin + growth
        end
    end)

    -- Handle projectile expiration from lifetime system
    events.on("entity_expired", function(entity)
        if entity.DamagesEnemy then
            projectilesActive = math.max(0, projectilesActive - 1)
        end
    end)

    gameState = "playing"
end

local function drawCenteredText(text, font, color, y)
    local screenW = love.graphics.getWidth()
    love.graphics.setFont(font)
    love.graphics.setColor(color[1], color[2], color[3], color[4] or 1)
    local textW = font:getWidth(text)
    love.graphics.print(text, (screenW - textW) / 2, y)
end

function love.load()
    love.window.setTitle("Shape Seasons")

    -- Create fonts
    titleFont = love.graphics.newFont(48)
    storyFont = love.graphics.newFont(18)
    promptFont = love.graphics.newFont(14)
    gameFont = love.graphics.newFont(12)
end

function love.update(dt)
    if gameState ~= "playing" then return end

    -- Update input state from Love2D
    input.update()

    -- Update game time
    gameTime = gameTime + dt

    -- Wave spawning based on start times
    local nextWave = currentWave + 1
    if nextWave <= #config.waves then
        local waveConfig = config.waves[nextWave]
        if gameTime >= waveConfig.start then
            spawnWave(waveConfig)
        end
    end

    -- Update ECS
    world:update(dt, function(_, system)
        return not system.isDrawSystem
    end)

    -- Check game over
    if player.Health.current <= 0 then
        gameState = "gameover"
    end

    -- Check win condition
    if currentWave >= #config.waves and enemiesAlive <= 0 then
        gameState = "won"
    end
end

function love.draw()
    local screenH = love.graphics.getHeight()

    if gameState == "intro" then
        drawCenteredText("shape seasons", titleFont, {1, 1, 1}, screenH / 3)
        drawCenteredText("you are a shape, trying to grow big enough in time for winter", storyFont, {0.7, 0.7, 0.7}, screenH / 2)
        drawCenteredText("press enter to play", promptFont, {0.5, 0.5, 0.5}, screenH * 2 / 3)
        return
    end

    if gameState == "gameover" then
        drawCenteredText("game over", titleFont, {0.9, 0.2, 0.2}, screenH / 3)
        drawCenteredText("size: " .. score, storyFont, {1, 1, 1}, screenH / 2)
        drawCenteredText("press enter to play again", promptFont, {0.5, 0.5, 0.5}, screenH * 2 / 3)
        return
    end

    if gameState == "won" then
        drawCenteredText("you survived the winter!", titleFont, {0.2, 0.8, 0.2}, screenH / 3)
        drawCenteredText("size: " .. score, storyFont, {1, 1, 1}, screenH / 2)
        drawCenteredText("press enter to play again", promptFont, {0.5, 0.5, 0.5}, screenH * 2 / 3)
        return
    end

    if gameState == "paused" then
        drawCenteredText("paused", titleFont, {1, 1, 1}, screenH / 4)
        drawCenteredText("WASD to move, click to shoot", storyFont, {0.7, 0.7, 0.7}, screenH / 2 - 30)
        drawCenteredText("press escape to resume", promptFont, {0.5, 0.5, 0.5}, screenH / 2 + 20)
        drawCenteredText("press R to restart", promptFont, {0.5, 0.5, 0.5}, screenH / 2 + 50)
        return
    end

    -- Reset to game font for UI
    love.graphics.setFont(gameFont)

    -- Draw arena border
    local arena = config.arena
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("line", arena.x, arena.y, arena.width, arena.height)

    -- Draw horizontal HUD
    local minutes = math.floor(gameTime / 60)
    local seconds = math.floor(gameTime % 60)
    local timeStr = string.format("%d:%02d", minutes, seconds)
    local hud = string.format("Time: %s   Wave: %d/%d   Size: %d   HP: %d/%d   Ammo: %d/%d",
        timeStr, currentWave, #config.waves, score, player.Health.current, player.Health.max,
        config.projectile.maxCount - projectilesActive, config.projectile.maxCount)
    love.graphics.print(hud, 10, 10)

    -- Run draw systems
    world:update(0, function(_, system)
        return system.isDrawSystem
    end)
end

function love.keypressed(key)
    if key == "return" and (gameState == "intro" or gameState == "gameover" or gameState == "won") then
        startGame()
    elseif key == "escape" and gameState == "playing" then
        gameState = "paused"
    elseif key == "escape" and gameState == "paused" then
        gameState = "playing"
    elseif key == "r" and gameState == "paused" then
        startGame()
    end
end

function love.mousepressed(x, y, button)
    if gameState ~= "playing" then return end

    if button == 1 and player and projectilesActive < config.projectile.maxCount then
        local dirX = x - player.x
        local dirY = y - player.y
        local len = math.sqrt(dirX * dirX + dirY * dirY)
        if len > 0 then
            -- Spawn projectile outside player's collider to avoid self-hit
            local offset = player.Collider.radius + config.projectile.size + 2
            local spawnX = player.x + (dirX / len) * offset
            local spawnY = player.y + (dirY / len) * offset
            local projectile = entities.createProjectile(spawnX, spawnY, dirX, dirY)
            world:addEntity(projectile)
            projectilesActive = projectilesActive + 1
        end
    end
end
