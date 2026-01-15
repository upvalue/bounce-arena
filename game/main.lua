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
local levelUpChoices = {}     -- random choices for current level up
local gameLog = {}  -- event log for end game screen

-- Available level up upgrades (heal is always slot 1)
local upgrades = {
    heal = {
        label = "Heal +8 HP",
        apply = function(p)
            p.Health.current = math.min(p.Health.current + config.levelUp.healAmount, p.Health.max)
        end
    },
    speed = {
        label = "Speed Boost (+10%)",
        apply = function(p)
            p.PlayerInput.speed = p.PlayerInput.speed * config.levelUp.speedMultiplier
        end
    },
    maxHp = {
        label = "Max HP +5",
        apply = function(p)
            p.Health.max = p.Health.max + config.levelUp.maxHpIncrease
        end
    },
    invuln = {
        label = "Invulnerability (12s)",
        apply = function(p, w)
            p.Invulnerable = { remaining = 12, flashTimer = 0 }
            w:addEntity(p)
        end
    }
}

-- Pick random upgrades for slots 2 and 3
local function pickLevelUpChoices()
    local pool = {"speed", "maxHp", "invuln"}
    -- Shuffle and pick 2
    local i = math.random(1, 3)
    local j = math.random(1, 2)
    if j >= i then j = j + 1 end
    levelUpChoices = {
        "heal",     -- always slot 1
        pool[i],    -- random slot 2
        pool[j]     -- random slot 3
    }
end

-- Fonts
local titleFont
local storyFont
local promptFont
local gameFont

-- ECS world
local world
local player

local function formatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%d:%02d", m, s)
end

local function logEvent(message)
    table.insert(gameLog, formatTime(gameTime) .. " - " .. message)
end

local function spawnWave(waveConfig)
    local arena = config.arena
    currentWave = currentWave + 1
    logEvent("Wave " .. currentWave .. " started")

    -- Spawn each enemy type
    for typeName, count in pairs(waveConfig) do
        if typeName ~= "start" then
            local enemyType = config.enemies[typeName]
            if enemyType then
                for i = 1, count do
                    local enemy
                    if enemyType.isTurret then
                        enemy = entities.spawnTurretAtEdge(arena, nil, enemyType)
                    elseif enemyType.isCarrier then
                        enemy = entities.spawnCarrierAtEdge(arena, player, nil)
                    elseif enemyType.isMine then
                        enemy = entities.spawnMineAtEdge(arena, player, nil)
                    elseif enemyType.isFlapper then
                        enemy = entities.spawnFlapperAtEdge(arena, nil)
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
    gameLog = {}
    events.clear()

    -- Clear system world references (required for restart)
    local allSystems = {
        systems.playerInput, systems.movementDelay, systems.seeking,
        systems.fleeing, systems.spawner, systems.mineDetector, systems.oscillation,
        systems.attraction, systems.movement, systems.bounce,
        systems.arenaClamp, systems.lifetime, systems.fade, systems.damageCooldown,
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

    -- Apply debug settings if enabled
    if config.debug.enabled then
        score = config.debug.startSize
        currentWave = config.debug.startWave - 1  -- so first spawn is startWave
        playerLevel = math.floor(score / config.levelUp.sizePerLevel)

        -- Apply size growth corresponding to starting score
        local accumulatedGrowth = score * config.experience.growthAmount
        player.Collider.radius = player.Collider.radius + accumulatedGrowth
        player.Render.radius = player.Render.radius + accumulatedGrowth
        player.ArenaClamp.margin = player.ArenaClamp.margin + accumulatedGrowth

        if config.debug.startMaxHealth then
            player.Health.max = config.debug.startMaxHealth
        end
        if config.debug.startHealth then
            player.Health.current = config.debug.startHealth
        else
            player.Health.current = player.Health.max
        end

        player.PlayerInput.speed = player.PlayerInput.speed * config.debug.speedMultiplier

        logEvent("DEBUG MODE: Wave " .. config.debug.startWave .. ", Size " .. score)
    end

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
        elseif data.type == "mine_exploded" then
            data.player.Health.current = data.player.Health.current - data.damage
            flashEntity(data.player)
            makeInvulnerable(data.player)
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
                pickLevelUpChoices()
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

    -- Handle carrier spawning enemies
    events.on("enemy_spawned", function(data)
        enemiesAlive = enemiesAlive + 1
    end)

    -- Handle mine removal (when exploding or killed)
    events.on("mine_removed", function(data)
        enemiesAlive = enemiesAlive - 1
        -- Show AOE explosion effect
        local mine = data.mine
        if mine.MineDetonator then
            local aoeEffect = entities.createAoeEffect(mine.x, mine.y, mine.MineDetonator.aoeRadius)
            world:addEntity(aoeEffect)
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

local function drawEventLog()
    love.graphics.setFont(promptFont)
    love.graphics.setColor(0.6, 0.6, 0.6)
    local y = 10
    for _, entry in ipairs(gameLog) do
        love.graphics.print(entry, 10, y)
        y = y + 18
    end
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
        drawEventLog()
        return
    end

    if gameState == "won" then
        drawCenteredText("you survived the winter!", titleFont, {0.2, 0.8, 0.2}, screenH / 3)
        drawCenteredText("size: " .. score, storyFont, {1, 1, 1}, screenH / 2)
        drawCenteredText("press enter to play again", promptFont, {0.5, 0.5, 0.5}, screenH * 2 / 3)
        drawEventLog()
        return
    end

    if gameState == "paused" then
        drawCenteredText("paused", titleFont, {1, 1, 1}, screenH / 4)
        drawCenteredText("WASD to move, click to shoot", storyFont, {0.7, 0.7, 0.7}, screenH / 2 - 30)
        drawCenteredText("press escape to resume", promptFont, {0.5, 0.5, 0.5}, screenH / 2 + 20)
        drawCenteredText("press R to restart", promptFont, {0.5, 0.5, 0.5}, screenH / 2 + 50)
        drawCenteredText("press Shift+Q to quit", promptFont, {0.5, 0.5, 0.5}, screenH / 2 + 80)
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
        for i, key in ipairs(levelUpChoices) do
            drawCenteredText(i .. ". " .. upgrades[key].label, storyFont, {0.8, 0.8, 0.8}, optionY + (i-1) * 40)
        end
    end
end

function love.keypressed(key)
    -- Level up selection (before other key handling)
    if pendingLevelUp then
        local choice = tonumber(key)
        if choice and choice >= 1 and choice <= #levelUpChoices then
            local upgradeKey = levelUpChoices[choice]
            local upgrade = upgrades[upgradeKey]
            upgrade.apply(player, world)
            logEvent("Level " .. playerLevel .. ": " .. upgrade.label)
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
    elseif key == "q" and gameState == "paused" and love.keyboard.isDown("lshift", "rshift") then
        gameState = "gameover"
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
