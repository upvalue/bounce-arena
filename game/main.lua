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
local enemiesClearedTime = nil  -- for adaptive wave mode
local playerLevel = 0
local pendingLevelUp = false  -- true when waiting for player to choose upgrade

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
                    local enemy
                    if enemyType.isTurret then
                        enemy = entities.spawnTurretAtEdge(arena, nil, enemyType)
                    else
                        enemy = entities.spawnEnemyAtEdge(arena, player, nil, enemyType)
                    end
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
    enemiesClearedTime = nil
    playerLevel = 0
    pendingLevelUp = false
    events.clear()

    -- Clear system world references (required for restart)
    local allSystems = {
        systems.playerInput, systems.movementDelay, systems.seeking,
        systems.attraction, systems.movement, systems.bounce,
        systems.arenaClamp, systems.lifetime, systems.damageCooldown,
        systems.invulnerability, systems.shooting, systems.flash,
        systems.collision, systems.render, systems.aimingLine, systems.hud
    }
    for _, sys in ipairs(allSystems) do
        sys.world = nil
    end

    -- Create fresh world
    world = tiny.world()
    world.arena = arena
    world.config = config

    -- Add systems in order (update systems first, then render systems)
    for _, sys in ipairs(allSystems) do
        world:addSystem(sys)
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
        elseif data.type == "enemy_projectile_hit_player" then
            data.player.Health.current = data.player.Health.current - data.damage
            flashEntity(data.player)
            makeInvulnerable(data.player)
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

            -- Check for level up
            local newLevel = math.floor(score / config.levelUp.sizePerLevel)
            if newLevel > playerLevel then
                playerLevel = newLevel
                pendingLevelUp = true
            end
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
    if pendingLevelUp then return end  -- Pause during level selection

    -- Update input state from Love2D
    input.update()

    -- Update game time
    gameTime = gameTime + dt

    -- Wave spawning (fixed or adaptive mode)
    local nextWave = currentWave + 1
    if nextWave <= #config.waves then
        local waveConfig = config.waves[nextWave]
        local shouldSpawn = false

        if config.waveMode == "fixed" then
            -- Fixed mode: spawn at configured time
            shouldSpawn = gameTime >= waveConfig.start
        else
            -- Adaptive mode: spawn after delay when enemies cleared, or at fixed time
            if enemiesAlive <= 0 then
                if enemiesClearedTime == nil then
                    enemiesClearedTime = gameTime
                end
                local timeSinceCleared = gameTime - enemiesClearedTime
                shouldSpawn = timeSinceCleared >= config.adaptiveWave.delay
                           or gameTime >= waveConfig.start
            elseif gameTime >= waveConfig.start then
                -- Fixed time passed while enemies still alive - spawn anyway
                shouldSpawn = true
            end
        end

        if shouldSpawn then
            spawnWave(waveConfig)
            enemiesClearedTime = nil  -- reset for next wave
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

    -- Calculate next wave countdown
    local nextWaveStr = ""
    local nextWave = currentWave + 1
    if nextWave <= #config.waves then
        local waveConfig = config.waves[nextWave]
        local timeUntil

        if config.waveMode == "fixed" then
            timeUntil = math.max(0, waveConfig.start - gameTime)
        else
            -- Adaptive mode
            if enemiesClearedTime then
                local adaptiveTime = config.adaptiveWave.delay - (gameTime - enemiesClearedTime)
                local fixedTime = waveConfig.start - gameTime
                timeUntil = math.max(0, math.min(adaptiveTime, fixedTime))
            else
                timeUntil = math.max(0, waveConfig.start - gameTime)
            end
        end

        if timeUntil < 5 then
            nextWaveStr = string.format("   Next: %.1fs", timeUntil)
        end
    end

    local hud = string.format("Time: %s   Wave: %d/%d   Level: %d   Size: %d   HP: %d/%d   Ammo: %d/%d%s",
        timeStr, currentWave, #config.waves, playerLevel, score, player.Health.current, player.Health.max,
        config.projectile.maxCount - projectilesActive, config.projectile.maxCount, nextWaveStr)
    love.graphics.print(hud, 10, 10)

    -- Run draw systems
    world:update(0, function(_, system)
        return system.isDrawSystem
    end)

    -- Level up overlay (drawn on top of gameplay)
    if pendingLevelUp then
        local screenW = love.graphics.getWidth()

        -- Draw semi-transparent overlay
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)

        -- Draw level up UI
        drawCenteredText("Level " .. playerLevel .. "!", titleFont, {1, 1, 0.2}, screenH / 4)
        drawCenteredText("Choose an upgrade:", storyFont, {1, 1, 1}, screenH / 3)

        local optionY = screenH / 2 - 30
        drawCenteredText("1. Speed Boost (+10%)", storyFont, {0.8, 0.8, 0.8}, optionY)
        drawCenteredText("2. Heal +8 HP", storyFont, {0.8, 0.8, 0.8}, optionY + 40)
        drawCenteredText("3. Max HP +5", storyFont, {0.8, 0.8, 0.8}, optionY + 80)
    end
end

function love.keypressed(key)
    -- Level up selection (before other key handling)
    if pendingLevelUp then
        if key == "1" then
            -- Speed boost
            player.PlayerInput.speed = player.PlayerInput.speed * config.levelUp.speedMultiplier
            pendingLevelUp = false
        elseif key == "2" then
            -- Heal +8 HP (capped at max)
            player.Health.current = math.min(player.Health.current + config.levelUp.healAmount, player.Health.max)
            pendingLevelUp = false
        elseif key == "3" then
            -- Max HP increase (no heal)
            player.Health.max = player.Health.max + config.levelUp.maxHpIncrease
            pendingLevelUp = false
        end
        return  -- Don't process other keys during level up
    end

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
