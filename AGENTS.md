# Bounce Arena - Agent Guide

A Love2D arena shooter using the tiny-ecs Entity Component System, with web deployment via love.js.

## Project Structure

```
recurse-jam/
├── game/                    # Game source files
│   ├── main.lua             # LÖVE callbacks, world setup
│   ├── systems.lua          # All ECS systems
│   ├── entities.lua         # Entity factory functions
│   ├── config.lua           # Centralized game configuration
│   ├── input.lua            # Input abstraction layer
│   ├── events.lua           # Event bus for decoupled communication
│   ├── conf.lua             # LÖVE configuration
│   ├── lib/
│   │   └── tiny.lua         # tiny-ecs library
│   └── spec/                # Test suite
│       ├── luaunit.lua      # Test framework
│       ├── helpers.lua      # Test utilities
│       └── run_tests.lua    # All tests (44 tests)
├── dist/                    # Built web output
├── .github/workflows/       # CI/CD
│   └── deploy.yml           # Auto-deploy to GitHub Pages
├── package.json             # pnpm scripts
└── CLAUDE.md                # This file
```

## Commands

```bash
# Run game natively (fastest for development)
love game

# Run tests
pnpm test

# Build for web
pnpm build

# Build and serve locally
pnpm serve

# Clean build output
pnpm clean
```

## Architecture Overview

This game uses an Entity Component System (ECS) pattern via tiny-ecs:

- **Entities**: Tables with component data as fields
- **Components**: Plain data (Position, Velocity, Health, etc.)
- **Systems**: Logic that processes entities with specific components

### Key Modules

| Module | Purpose |
|--------|---------|
| `config.lua` | All game settings in one place |
| `input.lua` | Abstracts Love2D input for testability |
| `events.lua` | Pub/sub event bus for loose coupling |
| `entities.lua` | Factory functions for creating entities |
| `systems.lua` | All game logic systems |

### Why ECS?

- Adding new entity types = combining existing components
- Adding new behaviors = adding new systems
- Systems are testable in isolation
- No inheritance hierarchies to manage

## Configuration

All game settings are centralized in `game/config.lua`:

```lua
local config = require("config")

config.arena      -- { x, y, width, height }
config.player     -- { size, speed, maxHp, color }
config.enemy      -- { size, speed, damage, color }
config.projectile -- { size, speed, lifetime, damage, color }
config.spawn      -- { initialEnemies }
```

To modify game balance, edit `config.lua`. All modules import from this single source.

## Input System

The input layer (`game/input.lua`) decouples game logic from Love2D APIs:

```lua
local input = require("input")

-- In game code (systems.lua)
if input.isDown("up") then ... end
if input.isDown("left") then ... end
local mx, my = input.getMousePosition()

-- In tests (set state directly)
input.setState({ up = true, right = true })
input.setMouse(100, 200)
input.reset()
```

This allows testing player input without Love2D running.

## Event System

The event bus (`game/events.lua`) enables loose coupling between systems:

```lua
local events = require("events")

-- Subscribe to events
events.on("collision", function(data)
    if data.type == "enemy_hit_player" then
        -- Play sound, show particles, etc.
    end
end)

-- Emit events (done by collision system)
events.emit("collision", {
    type = "enemy_hit_player",
    enemy = enemy,
    player = player,
    damage = 1
})

-- Cleanup
events.clear()  -- Remove all listeners
```

### Available Events

| Event | Data | Emitted When |
|-------|------|--------------|
| `collision` | `{type, enemy, player, damage}` | Enemy hits player |
| `collision` | `{type, projectile, enemy, damage}` | Projectile hits enemy |

## Components Reference

Components are just table fields. An entity "has" a component if that field exists.

| Component | Fields | Description |
|-----------|--------|-------------|
| `x, y` | numbers | Position (required for most entities) |
| `vx, vy` | numbers | Velocity |
| `Health` | `{current, max}` | Hit points |
| `Collider` | `{radius}` | Circle collision bounds |
| `SeeksTarget` | `{target, speed}` | Moves toward target entity |
| `Bounces` | `{}` | Flag: bounces off arena walls |
| `Lifetime` | `{remaining}` | Auto-removes when timer expires |
| `DamagesPlayer` | `{amount}` | Deals damage to player on collision |
| `DamagesEnemy` | `{amount}` | Deals damage to enemies on collision |
| `PlayerInput` | `{speed}` | Responds to WASD input |
| `ArenaClamp` | `{margin}` | Stays inside arena bounds |
| `Render` | `{type, color, radius, layer}` | Visual representation |

## Systems Reference

Systems are defined in `systems.lua`. They run in registration order.

### Update Systems (run in love.update)

| System | Filter | Purpose |
|--------|--------|---------|
| `playerInput` | PlayerInput | WASD movement (via input abstraction) |
| `seeking` | SeeksTarget | Move toward target |
| `movement` | vx, vy | Apply velocity to position |
| `bounce` | Bounces | Reverse velocity at arena edges |
| `arenaClamp` | ArenaClamp | Clamp position to arena |
| `lifetime` | Lifetime | Decrement timer, remove if expired |
| `collision` | Collider | Detect collisions, emit events |

### Draw Systems (run in love.draw)

| System | Filter | Purpose |
|--------|--------|---------|
| `render` | Render | Draw entities (sorted by layer) |
| `aimingLine` | PlayerInput | Draw mouse targeting line |
| `hud` | Health + PlayerInput | Draw HP display |

Draw systems have `isDrawSystem = true` flag.

## Entity Factories

Defined in `entities.lua`. Use these to create entities:

```lua
entities.createPlayer(x, y)           -- Player with input, health, collision
entities.createEnemy(x, y, target)    -- Enemy that seeks target
entities.createProjectile(x, y, dirX, dirY)  -- Bouncing projectile
entities.spawnEnemyAtEdge(arena, target, rng) -- Enemy at random edge
```

## Adding New Entity Types

1. Create a factory function in `entities.lua`:

```lua
function entities.createHomingMissile(x, y, target)
    return {
        x = x, y = y, vx = 0, vy = 0,
        Collider = { radius = 4 },
        SeeksTarget = { target = target, speed = 300 },
        Lifetime = { remaining = 3 },
        DamagesEnemy = { amount = 2 },
        Render = { type = "circle", radius = 4, color = {1, 0.5, 0}, layer = 8 }
    }
end
```

2. Spawn it in the game:

```lua
local missile = entities.createHomingMissile(player.x, player.y, nearestEnemy)
world:addEntity(missile)
```

## Adding New Components

1. Document the component in this file
2. Add it to entities that need it
3. Create or modify systems to process it

Example: Adding a `Poisoned` status effect:

```lua
-- Component: Poisoned = { damagePerSecond, remaining, tickTimer }

-- In systems.lua:
systems.poison = tiny.processingSystem()
systems.poison.filter = tiny.requireAll("Health", "Poisoned")
function systems.poison:process(e, dt)
    e.Poisoned.tickTimer = e.Poisoned.tickTimer - dt
    if e.Poisoned.tickTimer <= 0 then
        e.Health.current = e.Health.current - e.Poisoned.damagePerSecond
        e.Poisoned.tickTimer = 1.0
    end
    e.Poisoned.remaining = e.Poisoned.remaining - dt
    if e.Poisoned.remaining <= 0 then
        e.Poisoned = nil  -- Remove component
    end
end
```

## Adding New Systems

1. Create the system in `systems.lua`:

```lua
systems.mySystem = tiny.processingSystem()
systems.mySystem.filter = tiny.requireAll("ComponentA", "ComponentB")
function systems.mySystem:process(e, dt)
    -- Process each matching entity
end
```

2. Register it in `main.lua` (order matters):

```lua
world:addSystem(systems.mySystem)
```

3. For draw systems, add the flag:

```lua
systems.mySystem.isDrawSystem = true
```

## Testing

Tests use luaunit and are located in `game/spec/`. Run with `pnpm test`.

### Test Structure

```lua
-- game/spec/run_tests.lua contains all tests
-- Tests are organized by system/module:

TestMovement = {}      -- Movement system tests
TestSeeking = {}       -- Seeking system tests
TestEntities = {}      -- Entity factory tests
TestBounce = {}        -- Bounce system tests
TestLifetime = {}      -- Lifetime system tests
TestInput = {}         -- Input abstraction tests
TestPlayerInput = {}   -- Player input system tests
TestEvents = {}        -- Event bus tests
TestCollisionEvents = {} -- Collision event emission tests
```

### Writing Tests

```lua
-- Use helpers for common patterns
local helpers = require("spec.helpers")

function TestMySystem:testSomething()
    -- Create test entity
    local e = helpers.createMovingEntity(0, 0, 100, 0)

    -- Process with system
    helpers.processSystem(systems.movement, {e}, 1.0)

    -- Assert results
    lu.assertEquals(e.x, 100)
end

-- For input-dependent tests
function TestPlayerInput:testMoveUp()
    input.setState({ up = true })  -- Set input state directly
    local e = helpers.createPlayerInputEntity(50, 50, 200)
    helpers.processSystem(systems.playerInput, {e}, 1.0)
    lu.assertEquals(e.vy, -200)
end

-- For event tests
function TestCollision:testEmitsEvent()
    events.clear()
    local received = nil
    events.on("collision", function(data) received = data end)
    -- ... trigger collision ...
    lu.assertNotNil(received)
end
```

### Test Helpers

```lua
helpers.createMockWorld(arena)           -- Mock ECS world
helpers.processSystem(system, entities, dt, world)  -- Run system on entities
helpers.createMovingEntity(x, y, vx, vy) -- Entity with position + velocity
helpers.createBouncingEntity(...)        -- Entity with Bounces component
helpers.createSeekingEntity(...)         -- Entity with SeeksTarget
helpers.createPlayerInputEntity(...)     -- Entity with PlayerInput
helpers.assertNear(actual, expected, tolerance)  -- Float comparison
```

## Web Deployment

The game auto-deploys to GitHub Pages on push to main.

### Manual Build

```bash
pnpm build   # Creates dist/ folder
pnpm serve   # Build and serve locally
```

### GitHub Pages Setup

1. Go to repo Settings → Pages
2. Set Source to "GitHub Actions"
3. Push to main branch
4. Game available at `https://<user>.github.io/<repo>/`

## Dependencies

- [LÖVE 11.x](https://love2d.org/) - Game framework
- [tiny-ecs](https://github.com/bakpakin/tiny-ecs) - ECS library (included)
- [love.js](https://github.com/Davidobot/love.js) - Web export (dev dependency)
- [luaunit](https://github.com/bluebird75/luaunit) - Test framework (included)
