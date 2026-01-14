# Bounce Arena - Agent Guide

A Love2D arena shooter using the tiny-ecs Entity Component System.

## Project Structure

```
recurse-jam/
├── lib/
│   └── tiny.lua         # tiny-ecs library (https://github.com/bakpakin/tiny-ecs)
├── main.lua             # LÖVE callbacks, world setup, game config
├── systems.lua          # All ECS systems
├── entities.lua         # Entity factory functions and config
└── AGENTS.md            # This file
```

## Running the Game

```bash
love .
```

## Architecture Overview

This game uses an Entity Component System (ECS) pattern via tiny-ecs:

- **Entities**: Tables with component data as fields
- **Components**: Plain data (Position, Velocity, Health, etc.)
- **Systems**: Logic that processes entities with specific components

### Why ECS?

- Adding new entity types = combining existing components
- Adding new behaviors = adding new systems
- Systems are testable in isolation
- No inheritance hierarchies to manage

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
| `playerInput` | PlayerInput | WASD movement |
| `seeking` | SeeksTarget | Move toward target |
| `movement` | vx, vy | Apply velocity to position |
| `bounce` | Bounces | Reverse velocity at arena edges |
| `arenaClamp` | ArenaClamp | Clamp position to arena |
| `lifetime` | Lifetime | Decrement timer, remove if expired |
| `collision` | Collider | Handle all collision detection |

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

## Configuration

Entity stats are in `entities.lua`:

```lua
local config = {
    player = { size = 15, speed = 200, maxHp = 10, color = {0.2, 0.8, 0.2} },
    enemy = { size = 12, speed = 80, damage = 1, color = {0.9, 0.2, 0.2} },
    projectile = { size = 5, speed = 400, lifetime = 5, damage = 1, color = {1, 0.8, 0.2} }
}
```

Arena config is in `main.lua`:

```lua
local ARENA = { x = 50, y = 50, width = 700, height = 500 }
```

## Testing

Systems can be unit tested by:

1. Creating a minimal world
2. Adding test entities
3. Running the system
4. Asserting results

```lua
-- Example test
local world = tiny.world()
local e = { x = 0, y = 0, vx = 100, vy = 0 }
world:addEntity(e)
world:addSystem(systems.movement)
world:update(1.0)
assert(e.x == 100)
```

## Dependencies

- [LÖVE 11.x](https://love2d.org/)
- [tiny-ecs](https://github.com/bakpakin/tiny-ecs) (included in lib/)
