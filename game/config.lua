-- Centralized game configuration
-- All game settings in one place for easy tuning and testing

local config = {}
-- Debug/testing settings (set enabled = true to use)
config.debug = {
    enabled = true,
    startWave = 9,          -- skip to this wave (1 = normal start)
    startSize = 119,         -- starting score/size
    startHealth = nil,      -- starting HP (nil = use maxHp)
    startMaxHealth = 10,    -- starting max HP (nil = use config.player.maxHp)
    speedMultiplier = 1,   -- multiply player speed
    secondaryWeapon = nil,  -- nil, "bomb", "missile", or "sniper"
    ability = nil,          -- nil, "shield", "freeze", or "teleport"
}

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
    maxHp = 12,
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
        color = {0.2, 0.8, 0.3},  -- green
        destroyedOnContact = true
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
    },
    xBallTurret = {
        size = 18,
        speed = 0,
        damage = 0,
        health = 4,
        expValue = 4,
        color = {1, 0.5, 0.2},  -- orange to match projectiles
        fireRate = 2.5,
        directions = {{1, 0}, {-1, 0}},
        isTurret = true,
        isBallTurret = true
    },
    carrier = {
        size = 20,
        speed = 40,              -- slow, flees player
        wanderSpeed = 15,        -- slower random movement when player is far
        fleeRadius = 150,        -- start fleeing when player is within this distance
        damage = 1,
        health = 3,
        expValue = 5,
        color = {1, 0.6, 0.8},   -- pink
        spawnInterval = 5,       -- spawn fastTrooper every 5s
        isCarrier = true
    },
    mine = {
        size = 12,
        speed = 0,
        damage = 0,
        health = 3,
        expValue = 3,
        color = {0.5, 0.5, 0.5}, -- gray
        detonationRange = 80,    -- triggers when player this close
        aoeDamage = 3,
        aoeRadius = 100,
        fuseTime = 1.5,          -- time from trigger to explosion
        isMine = true
    },
    flapper = {
        size = 10,
        speed = 120,
        damage = 1,
        health = 1,
        expValue = 2,
        color = {0.4, 0.8, 1},   -- light blue
        travelDistance = 200,    -- ~1/3 arena width
        isFlapper = true
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

-- Ball turret projectile settings (bouncing)
config.ballTurretProjectile = {
    size = 6,
    speed = 120,
    lifetime = 8,
    damage = 1,
    color = {1, 0.5, 0.2}  -- orange
}

-- Visual effects
config.effects = {
    flashDuration = 0.1,
    flashColor = {1, 0, 0},  -- red
    aoeExplosion = {
        duration = 0.4,
        color = {1, 0.3, 0.3, 0.6}  -- red with alpha
    }
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

-- Secondary weapon settings (right-click)
config.secondaryWeapons = {
    bomb = {
        fuseTime = 2.0,       -- seconds before explosion
        aoeRadius = 100,      -- explosion radius
        aoeDamage = 5,        -- damage to all enemies in radius
        size = 10,
        color = {0.8, 0.4, 0.1}  -- orange-brown
    },
    missile = {
        speed = 500,
        aoeRadius = 80,       -- explosion radius on contact
        aoeDamage = 3,
        size = 8,
        color = {1, 0.2, 0.2}    -- red
    },
    sniper = {
        speed = 1200,         -- very fast
        size = 3,             -- small projectile
        color = {1, 1, 0.2}      -- bright yellow
    }
}

-- Ability settings (shift key)
config.abilities = {
    shield = {
        duration = 3,        -- seconds of invulnerability
        repelRadius = 100,   -- radius to push projectiles away
        repelForce = 500     -- velocity applied to projectiles
    },
    freeze = {
        duration = 3         -- seconds enemies stay frozen
    },
    teleport = {
        cooldown = 5         -- seconds between uses
    }
}

-- Wave mode: "fixed" or "adaptive"
-- fixed: waves spawn at configured start times
-- adaptive: next wave spawns 5s after enemies cleared, or at fixed time if passed
config.waveMode = "adaptive"

-- Adaptive wave settings
config.adaptiveWave = {
    delay = 5  -- seconds after all enemies killed before next wave
}

-- Season-to-level mapping
config.seasons = {
    spring = { level = 1, name = "Spring" },
    summer = { level = 2, name = "Summer", reward = "ability" },
    autumn = { level = 3, name = "Autumn", reward = "secondary" },
    winter = { level = 4, name = "Winter", reward = nil }
}

-- Wave definitions: start time and enemy counts by type
config.waves = {
    -- Level 1: Spring (waves 1-5)
    { start = 0,  trooper = 7, season = "spring" },
    { start = 20, trooper = 10, toughTrooper = 1 },
    { start = 40, trooper = 13, toughTrooper = 5 },
    { start = 60, trooper = 16, toughTrooper = 7 },
    { start = 80, trooper = 20, toughTrooper = 8 },

    -- Level 2: Summer (waves 6-9) - ability selection
    { start = 100, trooper = 5, flapper = 2, season = "summer" },
    { start = 120, trooper = 5, carrier = 2},
    { start = 140, trooper = 10, carrier = 2, toughTrooper = 3},
    { start = 160, trooper = 15, carrier = 2, toughTrooper = 3, flapper = 3},

    -- Level 3: Autumn (waves 10-4) - secondary weapon selection

    -- Level 4: Winter - nothing yet
    -- { start = 200, trooper = 1, season = "winter" },
}

--[[config.waves = {
    -- Level 1: Spring (waves 1-8)
    { start = 0,  trooper = 7, season = "spring" },
    { start = 20, trooper = 10, toughTrooper = 1 },
    { start = 40, trooper = 13, toughTrooper = 5 },
    { start = 60, trooper = 16, toughTrooper = 7 },
    { start = 80, trooper = 20, toughTrooper = 8 },
    { start = 100, trooper = 15, toughTrooper = 6, xTurret = 1, yTurret = 1 },
    { start = 120, trooper = 10, toughTrooper = 5, xyTurret = 2 },
    { start = 140, trooper = 10, toughTrooper = 5, fastTrooper = 2 },

    -- Level 2: Summer (waves 9+) - ability selection
    { start = 160, trooper = 5, xBallTurret = 1, season = "summer" },
    { start = 200, trooper = 5, flapper = 2 },
    { start = 180, trooper = 10, carrier = 2, toughTrooper = 3},
    { start = 220, trooper = 13, carrier = 2, toughTrooper = 2, flapper = 1 } ,
    { start = 240 } ,
    { start = 260 } ,
    { start = 280 } ,

    -- Level 3: Autumn - secondary weapon selection
    -- { start = 180, trooper = 1, season = "autumn" },

    -- Level 4: Winter - nothing yet
    -- { start = 200, trooper = 1, season = "winter" },
}]]

-- Experience drop settings
config.experience = {
    size = 4,
    value = 1,
    color = {0.3, 0.5, 1},  -- blue
    attractRadius = 150,
    attractSpeed = 200,
    growthAmount = 0.05
}

-- Level up settings
config.levelUp = {
    sizePerLevel = 40,
    speedMultiplier = 1.1,  -- 10% speed increase
    healAmount = 8,         -- HP restored by heal option
    maxHpIncrease = 5       -- max HP added (no heal)
}

return config
