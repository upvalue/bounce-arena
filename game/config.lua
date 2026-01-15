-- Centralized game configuration
-- All game settings in one place for easy tuning and testing

local config = {}

-- Arena bounds
config.arena = {
    x = 50,
    y = 50,
    width = 700,
    height = 500
}

-- Player settings
config.player = {
    size = 15,
    speed = 300,
    maxHp = 15,
    color = {0.3, 0.5, 1}
}

-- Enemy types
config.enemies = {
    trooper = {
        size = 12,
        speed = 80,
        damage = 1,
        health = 1,
        expValue = 1,
        color = {0.2, 0.8, 0.3}  -- green
    },
    toughTrooper = {
        size = 14,
        speed = 60,
        damage = 2,
        health = 2,
        expValue = 2,
        color = {0.6, 0.2, 0.8}  -- purple
    },
    fastTrooper = {
        size = 8,
        speed = 350,  -- faster than player (300)
        damage = 1,
        health = 1,
        expValue = 2,
        movementDelay = 2,  -- seconds before starting to move
        color = {1, 0.6, 0.2}  -- orange
    },
    xTurret = {
        size = 16,
        speed = 0,
        damage = 0,
        health = 3,
        expValue = 3,
        color = {0.8, 0.3, 0.3},
        fireRate = 2.0,
        directions = {{1, 0}, {-1, 0}},  -- right, left
        isTurret = true
    },
    yTurret = {
        size = 16,
        speed = 0,
        damage = 0,
        health = 3,
        expValue = 3,
        color = {0.8, 0.3, 0.3},
        fireRate = 2.0,
        directions = {{0, 1}, {0, -1}},  -- down, up
        isTurret = true
    },
    xyTurret = {
        size = 16,
        speed = 0,
        damage = 0,
        health = 3,
        expValue = 3,
        color = {0.8, 0.3, 0.3},
        fireRate = 2.0,
        directions = {{0.707, 0.707}, {-0.707, 0.707}, {0.707, -0.707}, {-0.707, -0.707}},
        isTurret = true
    }
}

-- Turret projectile settings
config.turretProjectile = {
    size = 4,
    speed = 150,
    lifetime = 5,
    damage = 1,
    color = {1, 0.3, 0.3}  -- red-ish
}

-- Visual effects
config.effects = {
    flashDuration = 0.1,
    flashColor = {1, 0, 0}  -- red
}

-- Player invulnerability after being hit
config.invuln = {
    duration = 3,        -- seconds of invulnerability
    flashInterval = 0.5  -- flash every N seconds
}

-- Spawn settings
config.spawn = {
    safeRadius = 150  -- minimum distance from player
}

-- Knockback settings (when enemy hits player)
config.knockback = {
    speed = 400,      -- knockback velocity
    cooldown = 0.5    -- seconds before enemy can damage again
}

-- Projectile settings
config.projectile = {
    size = 5,
    speed = 800,
    lifetime = 5,
    damage = 1,
    color = {1, 0.8, 0.2},
    maxCount = 5,
    maxEnemyBounces = 1
}

-- Wave mode: "fixed" or "adaptive"
-- fixed: waves spawn at configured start times
-- adaptive: next wave spawns 5s after enemies cleared, or at fixed time if passed
config.waveMode = "adaptive"

-- Adaptive wave settings
config.adaptiveWave = {
    delay = 5  -- seconds after all enemies killed before next wave
}

-- Wave definitions: start time and enemy counts by type
config.waves = {
    -- each level should be 2:30 for a total playtime of 10 minutes

    -- level 1

    { start = 0,  trooper = 7},
    { start = 20, trooper = 10, toughTrooper = 1 },
    { start = 40, trooper = 13, toughTrooper = 5 },
    { start = 60, trooper = 16, toughTrooper = 7 },
    { start = 80, trooper = 20, toughTrooper = 8 },
    { start = 100, trooper = 15, toughTrooper = 6, xTurret = 1, yTurret = 1},
    { start = 120, trooper = 10, toughTrooper = 5, xyTurret = 2},
    { start = 140, trooper = 10, toughTrooper = 5, fastTrooper = 2},

    -- { start = 100, trooper = 20, toughTrooper = 8 },


}

-- Experience drop settings
config.experience = {
    size = 4,
    value = 1,
    color = {0.3, 0.5, 1},  -- blue
    attractRadius = 150,
    attractSpeed = 200,
    growthAmount = 0.04
}

-- Level up settings
config.levelUp = {
    sizePerLevel = 50,
    speedMultiplier = 1.1,  -- 10% speed increase
    healAmount = 8,         -- HP restored by heal option
    maxHpIncrease = 5       -- max HP added (no heal)
}

return config
