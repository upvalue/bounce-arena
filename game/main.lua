local tiny = require("lib.tiny")
local systems = require("systems")
local entities = require("entities")
local config = require("config")
local input = require("input")
local events = require("events")
local music = require("music")

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

-- Season/level tracking
local currentSeason = "spring"
local currentSeasonLevel = 1
local pendingAbilitySelection = false
local pendingSecondarySelection = false
local pendingWaveConfig = nil  -- Wave waiting to spawn after selection

-- Ability selection choices
local abilityChoices = {"shield", "freeze", "teleport"}
local abilityNames = {
    shield = "Shell",
    freeze = "Chill",
    teleport = "Blink"
}
local abilityDescriptions = {
    shield = "Invulnerability + repel projectiles",
    freeze = "Stop all enemies for 3s",
    teleport = "Warp to cursor (5s cooldown)"
}

-- Secondary weapon selection choices
local secondaryChoices = {"bomb", "missile", "sniper"}
local secondaryNames = {
    bomb = "Splat",
    missile = "Whomper",
    sniper = "Plinker"
}
local secondaryDescriptions = {
    bomb = "Timed explosion, high damage",
    missile = "Flies to cursor, explodes on contact",
    sniper = "Piercing instant-kill shot"
}

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

-- Images
local splashImage

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

-- Find the season for a given wave number by scanning backwards
local function getSeasonForWave(waveNum)
    local season = "spring"  -- default
    for i = 1, waveNum do
        if config.waves[i] and config.waves[i].season then
            season = config.waves[i].season
        end
    end
    return season
end

local function spawnWave(waveConfig)
    local arena = config.arena
    currentWave = currentWave + 1
    logEvent("Wave " .. currentWave .. " started")

    -- Reset secondary weapon ammo
    if player and player.SecondaryWeapon then
        player.SecondaryWeapon.ammo = player.SecondaryWeapon.maxAmmo
    end

    -- Reset ability uses (except teleport which uses cooldown)
    if player and player.Ability then
        if player.Ability.type ~= "teleport" then
            player.Ability.uses = player.Ability.maxUses
        end
    end

    -- Spawn each enemy type
    for typeName, count in pairs(waveConfig) do
        if typeName ~= "start" and typeName ~= "season" then
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

    -- Reset season state
    currentSeason = "spring"
    currentSeasonLevel = 1
    pendingAbilitySelection = false
    pendingSecondarySelection = false
    pendingWaveConfig = nil

    -- Clear system world references (required for restart)
    local allSystems = {
        systems.playerInput, systems.movementDelay, systems.seeking,
        systems.fleeing, systems.spawner, systems.mineDetector, systems.oscillation,
        systems.freeze, systems.attraction, systems.movement, systems.bounce,
        systems.arenaClamp, systems.lifetime, systems.fade, systems.damageCooldown,
        systems.invulnerability, systems.shooting, systems.flash,
        systems.bombTimer, systems.collision, systems.render, systems.aimingLine, systems.hud
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
    -- Initialize ability and secondary weapon (nil until selected in normal game)
    player.Ability = nil
    player.SecondaryWeapon = nil
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

        -- Set ability from debug config (can be nil)
        if config.debug.ability then
            player.Ability = {
                type = config.debug.ability,
                uses = 1, maxUses = 1,
                cooldown = 0, active = false
            }
        end

        -- Set secondary weapon from debug config (can be nil)
        if config.debug.secondaryWeapon then
            player.SecondaryWeapon = {
                type = config.debug.secondaryWeapon,
                ammo = 1, maxAmmo = 1
            }
        end

        -- Backwards scan to find current season for debug start wave
        currentSeason = getSeasonForWave(config.debug.startWave)
        currentSeasonLevel = config.seasons[currentSeason].level

        -- Check if we need to prompt for ability (level 2+, no ability)
        if currentSeasonLevel >= 2 and not player.Ability then
            pendingAbilitySelection = true
        end

        -- Check if we need to prompt for secondary (level 3+, no secondary)
        if currentSeasonLevel >= 3 and not player.SecondaryWeapon then
            pendingSecondarySelection = true
        end

        logEvent("DEBUG MODE: Wave " .. config.debug.startWave .. ", Size " .. score .. ", Season " .. currentSeason)
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
        elseif data.type == "mine_killed_enemy" then
            enemiesAlive = enemiesAlive - 1
            local exp = entities.createExperience(data.enemy.x, data.enemy.y, player, data.enemy.expValue)
            world:addEntity(exp)
        elseif data.type == "enemy_killed_on_contact" then
            enemiesAlive = enemiesAlive - 1
            local exp = entities.createExperience(data.enemy.x, data.enemy.y, player, data.enemy.expValue)
            world:addEntity(exp)
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

    -- Handle secondary weapon explosions (bomb, missile)
    events.on("secondary_explosion", function(data)
        -- Create visual effect
        local aoeEffect = entities.createSecondaryAoeEffect(data.x, data.y, data.radius)
        world:addEntity(aoeEffect)

        -- Check if player is in blast radius (self-damage)
        if player and not player.Invulnerable then
            local pdx = player.x - data.x
            local pdy = player.y - data.y
            local pdist = math.sqrt(pdx * pdx + pdy * pdy)
            if pdist < data.radius then
                player.Health.current = player.Health.current - data.damage
                flashEntity(player)
                makeInvulnerable(player)
            end
        end

        -- Deal damage to all enemies in radius
        for _, entity in ipairs(world.entities) do
            if entity.Health and entity.DamagesPlayer then
                local dx = entity.x - data.x
                local dy = entity.y - data.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < data.radius then
                    entity.Health.current = entity.Health.current - data.damage
                    if entity.Health.current <= 0 then
                        -- Handle enemy death
                        enemiesAlive = enemiesAlive - 1
                        local exp = entities.createExperience(entity.x, entity.y, player, entity.expValue)
                        world:addEntity(exp)
                        -- If mine is killed, emit mine_removed
                        if entity.MineDetonator then
                            events.emit("mine_removed", { mine = entity })
                        end
                        world:removeEntity(entity)
                    else
                        -- Flash surviving enemies
                        flashEntity(entity)
                    end
                end
            end
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

-- Draw left-aligned selection options with name and description columns
local function drawSelectionOptions(choices, names, descriptions, font, startY, lineHeight)
    local screenW = love.graphics.getWidth()
    love.graphics.setFont(font)

    -- Calculate column positions (centered block)
    local maxNameWidth = 0
    for _, key in ipairs(choices) do
        local nameText = names[key]
        local w = font:getWidth("1. " .. nameText)
        if w > maxNameWidth then maxNameWidth = w end
    end

    local totalWidth = maxNameWidth + 20 + 300  -- name + gap + description
    local startX = (screenW - totalWidth) / 2

    for i, key in ipairs(choices) do
        local y = startY + (i - 1) * lineHeight
        -- Draw number and name
        love.graphics.setColor(0.9, 0.9, 0.7)
        love.graphics.print(i .. ". " .. names[key], startX, y)
        -- Draw description
        love.graphics.setColor(0.6, 0.6, 0.6)
        love.graphics.print(descriptions[key], startX + maxNameWidth + 20, y)
    end
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

local function drawControls(startY)
    local controls = {
        "WASD - Move",
        "Left click - Shoot",
        "Right click - Secondary (summer)",
        "Shift - Ability (autumn)"
    }
    local lineHeight = 24
    for i, line in ipairs(controls) do
        drawCenteredText(line, storyFont, {1, 1, 1}, startY + (i - 1) * lineHeight)
    end
end

-- Music checkbox position and size (set in draw for responsive layout)
local musicCheckbox = { x = 0, y = 0, size = 16 }

local function drawMusicCheckbox(y)
    local screenW = love.graphics.getWidth()
    local label = "Music"
    local labelWidth = promptFont:getWidth(label)
    local checkboxSize = musicCheckbox.size
    local totalWidth = checkboxSize + 8 + labelWidth
    local startX = (screenW - totalWidth) / 2

    -- Store position for click detection
    musicCheckbox.x = startX
    musicCheckbox.y = y

    -- Draw checkbox
    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", startX, y, checkboxSize, checkboxSize)

    -- Draw checkmark if enabled
    if music.isEnabled() then
        love.graphics.setColor(0.3, 1, 0.3)
        love.graphics.line(startX + 3, y + 8, startX + 6, y + 12, startX + 13, y + 4)
    end

    -- Draw label
    love.graphics.setFont(promptFont)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(label, startX + checkboxSize + 8, y + 4)
    love.graphics.setLineWidth(1)
end

local function isInsideCheckbox(mx, my)
    -- Include checkbox and label area for easier clicking
    local labelWidth = promptFont:getWidth("Music")
    local totalWidth = musicCheckbox.size + 8 + labelWidth
    return mx >= musicCheckbox.x and mx <= musicCheckbox.x + totalWidth and
           my >= musicCheckbox.y and my <= musicCheckbox.y + musicCheckbox.size
end

function love.load()
    love.window.setTitle("Shape Seasons")

    -- Load pixel font (Press Start 2P - works best at multiples of 8)
    local pixelFont = "assets/fonts/PressStart2P-Regular.ttf"
    titleFont = love.graphics.newFont(pixelFont, 32)
    storyFont = love.graphics.newFont(pixelFont, 12)
    promptFont = love.graphics.newFont(pixelFont, 8)
    gameFont = love.graphics.newFont(pixelFont, 8)

    -- Load images
    splashImage = love.graphics.newImage("assets/splash.png")

    -- Initialize and start background music
    music.init()
    music.setVolume(config.music.volume)
    music.setEnabled(config.music.enabled)
end

function love.update(dt)
    -- Update music (independent of game state)
    music.update()

    if gameState ~= "playing" then return end
    if pendingLevelUp then return end  -- Pause during level selection
    if pendingAbilitySelection then return end  -- Pause during ability selection
    if pendingSecondarySelection then return end  -- Pause during secondary selection

    -- Update input state from Love2D
    input.update()

    -- Update game time
    gameTime = gameTime + dt

    -- Wave spawning (fixed or adaptive mode)
    local nextWave = currentWave + 1
    if nextWave <= #config.waves then
        local waveConfig = config.waves[nextWave]
        local shouldSpawn = false

        -- Debug mode: spawn first wave after 1 second instead of configured time
        local isDebugFirstWave = config.debug.enabled
            and config.debug.startWave > 1
            and currentWave == config.debug.startWave - 1

        if isDebugFirstWave then
            shouldSpawn = gameTime >= 1
        elseif config.waveMode == "fixed" then
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
            -- Check for season change BEFORE spawning
            if waveConfig.season and waveConfig.season ~= currentSeason then
                currentSeason = waveConfig.season
                currentSeasonLevel = config.seasons[currentSeason].level
                logEvent("Season changed to " .. config.seasons[currentSeason].name)

                -- Check for rewards
                local reward = config.seasons[currentSeason].reward
                if reward == "ability" and not player.Ability then
                    pendingWaveConfig = waveConfig  -- Store for later
                    pendingAbilitySelection = true
                    -- DON'T spawn wave yet - wait for selection
                elseif reward == "secondary" and not player.SecondaryWeapon then
                    pendingWaveConfig = waveConfig
                    pendingSecondarySelection = true
                    -- DON'T spawn wave yet - wait for selection
                else
                    spawnWave(waveConfig)
                end
            else
                spawnWave(waveConfig)
            end
            enemiesClearedTime = nil  -- reset for next wave
        end
    end

    -- Update ECS
    world:update(dt, function(_, system)
        return not system.isDrawSystem
    end)

    -- Shield ability: repel projectiles while active
    if player and player.Ability and player.Ability.active then
        local cfg = config.abilities.shield
        for _, entity in ipairs(world.entities) do
            if entity.EnemyProjectile or (entity.DamagesPlayer and entity.vx) then
                local dx = entity.x - player.x
                local dy = entity.y - player.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < cfg.repelRadius and dist > 0 then
                    entity.vx = (dx / dist) * cfg.repelForce
                    entity.vy = (dy / dist) * cfg.repelForce
                end
            end
        end
        -- Deactivate when invulnerability ends
        if not player.Invulnerable then
            player.Ability.active = false
        end
    end

    -- Teleport ability: cooldown countdown
    if player and player.Ability and player.Ability.type == "teleport" then
        if player.Ability.cooldown > 0 then
            player.Ability.cooldown = player.Ability.cooldown - dt
        end
    end

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
        -- Draw splash image scaled to fill screen
        local screenW = love.graphics.getWidth()
        local imgW, imgH = splashImage:getDimensions()
        local scaleX = screenW / imgW
        local scaleY = screenH / imgH
        local scale = math.max(scaleX, scaleY)  -- cover entire screen
        local offsetX = (screenW - imgW * scale) / 2
        local offsetY = (screenH - imgH * scale) / 2
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(splashImage, offsetX, offsetY, 0, scale, scale)

        -- Semi-transparent overlay for text readability
        love.graphics.setColor(0, 0, 0, 0.4)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)

        drawCenteredText("shape seasons", titleFont, {1, 1, 1}, 20)
        drawCenteredText("grow big enough to survive winter", storyFont, {1, 1, 1}, 65)

        drawControls(105)

        drawMusicCheckbox(210)
        drawCenteredText("press enter to play", storyFont, {1, 1, 1}, 240)
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
        drawCenteredText("paused", titleFont, {1, 1, 1}, 20)

        drawControls(70)

        drawCenteredText("Escape - Resume", storyFont, {1, 1, 1}, 175)
        drawCenteredText("R - Restart", storyFont, {1, 1, 1}, 199)
        drawCenteredText("Shift+Q - Quit", storyFont, {1, 1, 1}, 223)
        drawMusicCheckbox(260)
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

    -- Secondary weapon status
    local secondaryStr = ""
    if player.SecondaryWeapon then
        local displayName = secondaryNames[player.SecondaryWeapon.type] or player.SecondaryWeapon.type
        secondaryStr = string.format("   [%s: %d/%d]",
            displayName:upper(),
            player.SecondaryWeapon.ammo,
            player.SecondaryWeapon.maxAmmo)
    end

    -- Ability status
    local abilityStr = ""
    if player.Ability then
        local a = player.Ability
        local displayName = abilityNames[a.type] or a.type
        if a.type == "teleport" then
            if a.cooldown > 0 then
                abilityStr = string.format("   {%s: %.1fs}", displayName:upper(), a.cooldown)
            else
                abilityStr = string.format("   {%s: READY}", displayName:upper())
            end
        else
            abilityStr = string.format("   {%s: %d/%d}", displayName:upper(), a.uses, a.maxUses)
        end
    end

    -- Season name for HUD
    local seasonName = config.seasons[currentSeason].name

    local hud = string.format("%s   Time: %s   Wave: %d/%d   Level: %d   Size: %d   HP: %d/%d   Ammo: %d/%d%s%s%s",
        seasonName, timeStr, currentWave, #config.waves, playerLevel, score, player.Health.current, player.Health.max,
        config.projectile.maxCount - projectilesActive, config.projectile.maxCount, secondaryStr, abilityStr, nextWaveStr)
    love.graphics.print(hud, 10, 10)

    -- Run draw systems
    world:update(0, function(_, system)
        return system.isDrawSystem
    end)

    -- Shield ability visual effect
    if player and player.Ability and player.Ability.active then
        local shieldRadius = player.Collider.radius + config.abilities.shield.repelRadius * 0.3
        love.graphics.setColor(0.3, 0.7, 1, 0.4)  -- light blue, transparent
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", player.x, player.y, shieldRadius)
        love.graphics.setLineWidth(1)
    end

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

    -- Ability selection overlay
    if pendingAbilitySelection then
        local screenW = love.graphics.getWidth()

        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)

        drawCenteredText("Summer Has Arrived!", titleFont, {1, 0.8, 0.2}, screenH / 4)
        drawCenteredText("Choose your ability:", storyFont, {1, 1, 1}, screenH / 3)

        drawSelectionOptions(abilityChoices, abilityNames, abilityDescriptions, storyFont, screenH / 2 - 30, 40)
    end

    -- Secondary weapon selection overlay
    if pendingSecondarySelection then
        local screenW = love.graphics.getWidth()

        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)

        drawCenteredText("Autumn Has Arrived!", titleFont, {1, 0.5, 0.2}, screenH / 4)
        drawCenteredText("Choose your weapon:", storyFont, {1, 1, 1}, screenH / 3)

        drawSelectionOptions(secondaryChoices, secondaryNames, secondaryDescriptions, storyFont, screenH / 2 - 30, 40)
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

    -- Ability selection
    if pendingAbilitySelection then
        local choice = tonumber(key)
        if choice and choice >= 1 and choice <= #abilityChoices then
            local abilityType = abilityChoices[choice]
            player.Ability = {
                type = abilityType,
                uses = 1, maxUses = 1,
                cooldown = 0, active = false
            }
            logEvent("Selected ability: " .. abilityType)
            pendingAbilitySelection = false

            -- Check if secondary is also needed (level 3+)
            if currentSeasonLevel >= 3 and not player.SecondaryWeapon then
                pendingSecondarySelection = true
            elseif pendingWaveConfig then
                -- Spawn the waiting wave
                spawnWave(pendingWaveConfig)
                pendingWaveConfig = nil
            end
        end
        return
    end

    -- Secondary weapon selection
    if pendingSecondarySelection then
        local choice = tonumber(key)
        if choice and choice >= 1 and choice <= #secondaryChoices then
            local weaponType = secondaryChoices[choice]
            player.SecondaryWeapon = {
                type = weaponType,
                ammo = 1, maxAmmo = 1
            }
            logEvent("Selected weapon: " .. weaponType)
            pendingSecondarySelection = false

            -- Spawn the waiting wave if any
            if pendingWaveConfig then
                spawnWave(pendingWaveConfig)
                pendingWaveConfig = nil
            end
        end
        return
    end

    -- Ability activation (shift key)
    if (key == "lshift" or key == "rshift") and gameState == "playing" then
        if not player or not player.Ability then return end

        local ability = player.Ability

        if ability.type == "shield" then
            if ability.uses > 0 then
                -- Grant invulnerability
                player.Invulnerable = { remaining = config.abilities.shield.duration, flashTimer = 0 }
                ability.active = true
                ability.uses = ability.uses - 1
                world:addEntity(player)  -- refresh for invuln system
            end

        elseif ability.type == "freeze" then
            if ability.uses > 0 then
                -- Add Frozen component to all enemies
                for _, entity in ipairs(world.entities) do
                    if entity.DamagesPlayer and not entity.Frozen then
                        entity.Frozen = { remaining = config.abilities.freeze.duration }
                        entity.vx, entity.vy = 0, 0
                        world:addEntity(entity)
                    end
                end
                ability.uses = ability.uses - 1
            end

        elseif ability.type == "teleport" then
            if ability.cooldown <= 0 then
                local mx, my = love.mouse.getPosition()
                -- Clamp to arena bounds
                local arena = config.arena
                local margin = player.ArenaClamp.margin
                player.x = math.max(arena.x + margin, math.min(arena.x + arena.width - margin, mx))
                player.y = math.max(arena.y + margin, math.min(arena.y + arena.height - margin, my))
                player.vx, player.vy = 0, 0
                ability.cooldown = config.abilities.teleport.cooldown
            end
        end
        return
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
    -- Handle music checkbox click on intro and paused screens
    if button == 1 and (gameState == "intro" or gameState == "paused") then
        if isInsideCheckbox(x, y) then
            music.toggle()
            return
        end
    end

    if gameState ~= "playing" then return end
    if pendingLevelUp then return end
    if pendingAbilitySelection then return end
    if pendingSecondarySelection then return end

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

    -- Right-click: fire secondary weapon
    if button == 2 and player and player.SecondaryWeapon and player.SecondaryWeapon.ammo > 0 then
        local weaponType = player.SecondaryWeapon.type
        local dirX = x - player.x
        local dirY = y - player.y
        local len = math.sqrt(dirX * dirX + dirY * dirY)

        if weaponType == "bomb" then
            -- Drop bomb at player position
            local bomb = entities.createBomb(player.x, player.y)
            world:addEntity(bomb)
        elseif weaponType == "missile" then
            -- Fire missile toward cursor
            if len > 0 then
                local cfg = config.secondaryWeapons.missile
                local offset = player.Collider.radius + cfg.size + 2
                local spawnX = player.x + (dirX / len) * offset
                local spawnY = player.y + (dirY / len) * offset
                local missile = entities.createMissile(spawnX, spawnY, dirX, dirY)
                world:addEntity(missile)
            end
        elseif weaponType == "sniper" then
            -- Fire sniper shot toward cursor
            if len > 0 then
                local cfg = config.secondaryWeapons.sniper
                local offset = player.Collider.radius + cfg.size + 2
                local spawnX = player.x + (dirX / len) * offset
                local spawnY = player.y + (dirY / len) * offset
                local shot = entities.createSniperShot(spawnX, spawnY, dirX, dirY)
                world:addEntity(shot)
            end
        end

        -- Consume ammo
        player.SecondaryWeapon.ammo = player.SecondaryWeapon.ammo - 1
        logEvent("Used " .. weaponType)
    end
end
