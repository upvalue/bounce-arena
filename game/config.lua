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
    speed = 200,
    maxHp = 10,
    color = {0.2, 0.8, 0.2}
}

-- Enemy settings
config.enemy = {
    size = 12,
    speed = 80,
    damage = 1,
    color = {0.9, 0.2, 0.2}
}

-- Projectile settings
config.projectile = {
    size = 5,
    speed = 400,
    lifetime = 5,
    damage = 1,
    color = {1, 0.8, 0.2}
}

-- Spawn settings
config.spawn = {
    initialEnemies = 5
}

return config
