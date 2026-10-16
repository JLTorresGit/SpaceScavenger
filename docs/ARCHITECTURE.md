# Architecture

Space Scavenger is a Godot 4.7 project written only in GDScript. Except for `scenes/main.tscn` (one root node) and the test scene, every node is built in code. All art is drawn with `_draw()` vector shapes, so the project has no image or audio assets.

## 1. Big picture

```mermaid
flowchart TB
  subgraph Files["Editable data (res://config)"]
    GC["game_config.json<br/>all tunable values"]
    TT["tech_tree.json<br/>all technologies"]
  end
  subgraph User["Player data (user://)"]
    SV["saves/*.json<br/>slots, quicksave, autosave"]
    ST["settings.json"]
    MOD["mods/*.json<br/>optional overrides"]
  end
  subgraph Autoloads["Autoload singletons"]
    CFG["Config<br/>config.gd"]
    GAME["Game<br/>game.gd"]
  end
  subgraph World["World (pausable)"]
    UNI["Universe<br/>universe.gd"]
    GEN["Generator<br/>generator.gd (static, thread-safe)"]
    ENT["Entities<br/>scripts/entities/*"]
    SHIP["Ship<br/>ship.gd + drone.gd"]
    CAM["Camera rig"]
    SF["Starfield"]
  end
  subgraph UI["UI (always processing)"]
    MAIN["main.gd<br/>orchestrator"]
    HUD["HUD + Radar"]
    WIN["Windows<br/>menu, codex, map, tech, cargo,<br/>modules, station, settings…"]
  end

  GC --> CFG
  TT --> CFG
  MOD --> CFG
  CFG --> GAME
  CFG --> GEN
  GAME <--> SV
  GAME <--> ST
  MAIN --> UNI
  MAIN --> SHIP
  MAIN --> HUD
  MAIN --> WIN
  UNI -->|worker threads| GEN
  GEN -->|entity dictionaries| UNI
  UNI -->|spawns| ENT
  SHIP -->|queries: gravity, raycast, pickups| UNI
  SHIP <-->|fuel, energy, cargo, research| GAME
  HUD -->|reads| SHIP
  HUD -->|reads| GAME
  WIN -->|actions| GAME
  WIN -->|travel, target, jettison| MAIN
  CAM --> SHIP
  SF --> CAM
```

| Layer | Responsibility | Key files |
|---|---|---|
| **Config** | Loads the two JSON files, merges mod overrides, builds the `InputMap` from `input_bindings`, provides typed accessors (`fval`, `ival`, `dict`, `item`). | `scripts/autoload/config.gd` |
| **Game state** | Holds everything that persists: resources, cargo, credits, research, modules, discoveries, names, delta removals, statistics, achievements, target and settings. Computes ship stats. Saves and loads. | `scripts/autoload/game.gd` |
| **Generation** | Pure functions: `seed + coordinates → entity dictionaries`. No nodes, so they are safe to run on worker threads. | `scripts/world/generator.gd`, `naming.gd` |
| **Universe** | Streams chunks and star systems, owns entity nodes, keeps the floating origin, and answers spatial queries (gravity, raycast, entity at point). | `scripts/world/universe.gd` |
| **Entities** | One script per kind. Each draws itself and exposes flags (collidable, minable, discoverable…) plus hooks (`scan_info`, `_destroyed`, `on_ship_contact`). | `scripts/entities/*.gd` |
| **Ship** | Flight physics, autopilot, warp, laser, tractor, collection, scanning, drones, docking, environment damage, energy systems, quick travel, death. | `scripts/ship/ship.gd`, `drone.gd` |
| **UI** | HUD, radar, menus and modal windows, all built in code from `UiKit` helpers and one shared theme. | `scripts/ui/*.gd` |
| **Orchestrator** | Builds and destroys the world, routes input, opens windows (pausing the game), queues naming prompts, autosaves, and handles death and reload. Also contains the `--autotest` session. | `scripts/main.gd` |

## 2. Runtime scene tree

```mermaid
flowchart TB
  Root["Main (Node, PROCESS_ALWAYS)<br/>main.gd"]
  Root --> SFL["CanvasLayer -10"]
  SFL --> SFN["Starfield (screen-space parallax)"]
  Root --> W["World (Node2D, PAUSABLE)"]
  W --> U["Universe (Node2D)"]
  U --> LB["Back layer<br/>nebulae, ion storms, field markers"]
  U --> LBo["Bodies layer<br/>stars, planets, moons, asteroids,<br/>derelicts, stations, anomalies"]
  U --> LI["Items layer<br/>pickups, drones"]
  U --> S["Ship (drawn on top)"]
  W --> C["Camera2D (camera_rig.gd)"]
  Root --> UIL["CanvasLayer 10 (scaled by UI scale)"]
  UIL --> UR["UI root (Control + theme)"]
  UR --> H["HUD"]
  UR --> MM["Main menu"]
  UR --> WS["Windows (created on first use)"]
```

Opening any window calls `get_tree().paused = true`. The world is `PAUSABLE`, so it freezes. The UI, the camera (for photo mode) and `main.gd` keep processing.

## 3. Coordinates and the floating origin

32-bit float positions lose precision far from (0, 0). The game separates **world** coordinates from **node** coordinates:

```
world (64-bit float) = Game.origin + node.position (32-bit, always small)
```

```mermaid
sequenceDiagram
  participant Ship
  participant Universe
  participant Camera
  Ship->>Universe: position grows past origin_shift_threshold (20,000)
  Universe->>Universe: Game.origin += ship.position
  Universe->>Universe: every entity.position -= delta
  Universe->>Ship: ship.position -= delta (now ~0)
  Universe->>Camera: origin_shifted(delta) → camera.position -= delta
```

* Generator output, saves, discoveries and targets always use world coordinates (`wx`, `wy`).
* `Universe.to_local_pos(wx, wy)` and `world_x/world_y(pos)` convert between the two.
* `Universe.teleport(wx, wy)` (wormholes, quick travel, loading) clears every entity, sets the origin to the destination and streams fresh content around it.

## 4. Procedural generation

```mermaid
flowchart LR
  Seed["World seed"] --> H["hash3(seed, x, y, salt)<br/>64-bit mix, deterministic"]
  H --> SYS["System cell (50,000 u)<br/>Generator.system_at"]
  H --> CH["Chunk (4,000 u)<br/>Generator.chunk_at"]
  SYS --> Star["Star (class by weight)"]
  Star --> Pl["Planets 1-6<br/>orbits beyond the heat zone"]
  Pl --> Mo["Moons 0-3"]
  Pl --> Deb["Low-orbit debris<br/>derelicts, scrap, rocks"]
  Pl --> StS["Orbital station (chance)"]
  CH --> Bio["Biome noise<br/>core / normal / rim density"]
  CH --> Rich["Richness grows with<br/>distance from origin"]
  Bio --> Free["Free-space content<br/>asteroid fields, derelicts, scrap,<br/>nebulae, ion storms, black holes,<br/>comets, stations, wormholes,<br/>signals, ghost ships, rescue pods"]
  Rich --> Free
  SYS -. "blockers (stars, planets)" .-> Free
```

* **Deterministic:** every random choice comes from a `RandomNumberGenerator` seeded with `hash3(seed, x, y, salt)`. The same seed always produces the same universe, so seeds can be shared.
* **Exclusion:** chunk content avoids star heat zones and planets in nearby systems, and avoids a safe radius around the start position.
* **Home content:** system cell (0, 0) always has a G-class star with 3 planets. Chunk (0, 0) always contains the *Haven Prime* station, and chunk (0, −1) contains a starter derelict.
* **Stable ids:** each entity id encodes where it came from (`c3_-2_a7`, `s0_0_p1_m0`…). This is what makes delta saves possible.

## 5. Chunk streaming (threading)

```mermaid
sequenceDiagram
  participant Main as Main thread (Universe._process)
  participant Pool as WorkerThreadPool
  participant Gen as Generator
  Main->>Main: compute ship chunk (cx, cy) and system cells
  loop each missing chunk within load_radius_chunks
    Main->>Pool: add_task(_generate_task, key, seed)
    Pool->>Gen: chunk_at / system_at
    Gen-->>Pool: Array of entity dictionaries
    Pool-->>Main: push to _results (mutex)
  end
  Main->>Main: _collect_results → skip ids in Game.removed → spawn queue
  Main->>Main: spawn ≤ max_spawns_per_frame nodes per frame
  Main->>Main: free chunks beyond unload_radius_chunks and transients beyond transient_unload_distance
```

* Loading 5×5 chunks around the ship keeps about 150–300 entities alive. The autotest held ~60 FPS while warping at full speed.
* Results that arrive for a chunk that was unloaded or teleported away in the meantime are discarded (`_pending` check), and results from an old seed are ignored.

## 6. Entity model

```mermaid
classDiagram
  class SpaceEntity {
    id, kind, radius, data
    layer, persistent
    collidable, minable, selectable
    discoverable, is_hazard, has_gravity
    surface_g, influence, hp, velocity
    setup(d) / _setup()
    default_name() / display_name()
    discovery_range() / discovery_entry()
    scan_info()
    take_damage(amount) / _destroyed()
    on_ship_contact(ship)
  }
  SpaceEntity <|-- Star : heat zone, flares, gravity
  SpaceEntity <|-- Planet : planet / moon, gravity
  SpaceEntity <|-- Asteroid : asteroid / comet, ore drops, splits
  SpaceEntity <|-- Derelict : loot + lore log
  SpaceEntity <|-- Pickup : item stack, small / large
  SpaceEntity <|-- Station : docking, trade
  SpaceEntity <|-- Nebula : radar ×, shield regen ×
  SpaceEntity <|-- IonStorm : energy drain, drifts
  SpaceEntity <|-- BlackHole : extreme gravity
  SpaceEntity <|-- Wormhole : teleport
  SpaceEntity <|-- Beacon : signal cache / rescue pod
  SpaceEntity <|-- FieldMarker : asteroid field marker
```

The Universe indexes entities by role: `pickups`, `solids` (collidable), `gravity_sources` and `hazards`. Each frame the ship walks only the index it needs.

## 7. Ship stats pipeline

```mermaid
flowchart LR
  Base["game_config.json › ship<br/>(base stats)"] --> Calc["Game.recalc_stats()"]
  Tech["Researched technologies<br/>effects: add / mul / set"] --> Calc
  Mods["Installed + enabled modules<br/>effects"] --> Calc
  Calc --> Stats["Game.ship_stats"]
  Calc --> Mode["Game.engine_mode<br/>fuel | energy"]
  Stats --> Ship["Ship reads Game.stat(key) every frame"]
  Diff["Difficulty preset<br/>consumption × / damage ×"] --> Ship
```

`recalc_stats()` runs on research completion, module install/uninstall/toggle, load and config reload. Resources are clamped to the new capacities.

## 8. Ship frame update order

```mermaid
flowchart TB
  A["_flight: input / autopilot → rotation, thrust, warp,<br/>propellant use, gravity, speed cap, move"] --> B["_collisions: bounce off solids, impact damage (capped)"]
  B --> C["_environment: star heat + flares, scoop band,<br/>black hole, nebula, ion storm, contacts, docking range"]
  C --> D["_systems: life support, sensors, modules,<br/>scoop, converter, shield regen, hull regen"]
  D --> E["_tools: laser raycast, tractor pull, scan progress"]
  E --> F["_collect: proximity (small) / tractor (large)"]
  F --> G["_actions: dock, scan, drones, refuel / recharge / repair"]
  G --> H["_timers: discoveries (4 Hz), rescue countdown, stats"]
  H --> I["Game.process_research(dt)"]
  I --> J["clamp resources → rates for HUD → death check"]
```

## 9. Persistence (delta saves)

```mermaid
flowchart LR
  subgraph Save["save file (JSON, version 1)"]
    direction TB
    a["seed, difficulty, play_time"]
    b["ship: wx, wy, vx, vy, rot"]
    c["fuel, energy, shield, hull, credits, data"]
    d["cargo, researched, research in progress"]
    e["modules unlocked / installed / enabled, recipes"]
    f["discoveries, names, logs, scanned"]
    g["removed ids (mined, looted, collected)"]
    h["visited chunks, stats, achievements, target, rescue"]
  end
  Gen["Generator(seed)"] --> World["Rebuilt world"]
  g -->|filter| World
```

* The universe itself is never saved. It is regenerated from the seed, and anything in `removed` is skipped.
* Transient objects (salvage drops, asteroid fragments, jettisoned cargo) are not saved. See TODO-22.
* `Game.migrate()` upgrades older save versions. `SAVE_VERSION` is currently 1.
* Slots are `slot_1..5`, `quicksave` and `autosave`. Ironman runs keep a single `ironman_<seed>` slot.
* Autosave runs every `autosave.interval_sec`, but only when the hull is above `min_hull_fraction`, the ship has taken no damage for `quiet_time_sec`, and there is no heat. It also saves on docking and on a new game.

## 10. UI composition

* `UiKit` builds the shared `Theme` and small widgets (labels, buttons, bars, scroll areas).
* `WindowPanel` is the modal base class: a dim backdrop, a centred titled panel, `_build()` once, `refresh()` on every open, and Esc closes it.
* Window classes live in `simple_windows.gd` (pause, save/load, settings, help, naming, message, statistics), `game_windows.gd` (codex, tech, cargo, modules, station) and `map_window.gd`.
* UI scale is applied by scaling the UI `CanvasLayer`. The root control is resized to `viewport / scale` every frame.
* Two palettes (normal and colour-blind safe) are defined in config. `Game.pal(key)` returns the active colour, and the radar also encodes kind by shape.

## 11. Extension points

| To add… | Do this |
|---|---|
| A tunable number | Add it to `game_config.json` and read it with `Config.fval("section.key")`. |
| A technology | Add a node to `tech_tree.json`. No code is needed if it uses existing stats, modules or recipes. |
| An item, recipe or module | Add it to `items` / `recipes` / `modules` in `game_config.json`. Unlock it from a tech node if it should not be available at the start. |
| A new ship stat | Add it to `ship` in the config, then read it with `Game.stat("name")` where it applies. Techs and modules can then modify it. |
| A new entity kind | Create `scripts/entities/<kind>.gd` extending `SpaceEntity`, register it in `Universe.SCRIPTS`, emit it from `Generator.chunk_at`/`system_at`, and add a `radar_colors` entry and `discovery` values. |
| A new window | Subclass `WindowPanel`, then add it to `main._window()` and, if it has a hotkey, to `WINDOW_KEYS` plus `input_bindings`. |
