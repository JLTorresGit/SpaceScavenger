# Game Flow

## 1. Application states

```mermaid
stateDiagram-v2
  [*] --> MainMenu
  MainMenu --> Playing : New Game (seed + difficulty)
  MainMenu --> Playing : Continue / Load
  MainMenu --> MenuWindow : Load list / Settings
  MenuWindow --> MainMenu : close

  Playing --> Window : hotkey (Tab C K I U O F1) / Esc
  Window --> Playing : close / same hotkey / Esc
  Window --> Window : switch window (pause → save, load, settings…)
  Playing --> Naming : discovered star, planet or moon
  Naming --> Playing : accept / keep catalogue name
  Playing --> Docked : X near a station, slow enough
  Docked --> Playing : close station window
  Playing --> PhotoMode : P
  PhotoMode --> Playing : P / Esc
  Playing --> Destroyed : hull reaches 0

  Destroyed --> Playing : Reload last save (Relaxed / Standard)
  Destroyed --> MainMenu : Main Menu
  Destroyed --> GameOver : Ironman (save deleted)
  GameOver --> MainMenu

  Window --> MainMenu : Save & Main Menu
  Window --> [*] : Save & Quit
```

Every state except **Playing** pauses the world simulation. Research and timers only advance in **Playing**.

| Main menu | In flight |
|---|---|
| ![Main menu](images/00_menu.png) | ![Start](images/01_start.png) |

## 2. Core gameplay loop

```mermaid
flowchart LR
  Explore["Explore<br/>fly, warp, autopilot"] --> Discover["Discover<br/>stars, planets, stations,<br/>anomalies (codex)"]
  Discover --> Scan["Scan (V)<br/>contents + discovery data"]
  Scan --> Salvage["Salvage<br/>laser asteroids & derelicts"]
  Salvage --> Collect["Collect<br/>proximity (small) /<br/>tractor (large)"]
  Collect --> Use{"Use resources"}
  Use --> Survive["Survive<br/>refuel, recharge, repair"]
  Use --> Craft["Craft<br/>refinery recipes"]
  Use --> Research["Research<br/>tech tree (Lab)"]
  Use --> Trade["Trade at stations<br/>sell cargo & data, buy, services"]
  Research --> Upgrade["Upgrade ship<br/>stats, modules, recipes,<br/>Ion Drive"]
  Trade --> Upgrade
  Craft --> Research
  Upgrade --> Explore
  Survive --> Explore
```

## 3. Resource economy

```mermaid
flowchart TB
  subgraph Sources
    AST["Asteroids<br/>iron, titanium, rare ore"]
    COM["Comets<br/>ice"]
    DER["Derelicts<br/>fuel cells, batteries,<br/>electronics, scrap"]
    GHO["Ghost ships / signals<br/>data cores, credits"]
    STA["Stations<br/>buy items & services"]
    SUN["Stars + Solar Scoop<br/>energy"]
    SCN["Scans & discoveries<br/>discovery data"]
  end
  subgraph Ship
    FUEL[("Fuel")]
    EN[("Energy")]
    HULL[("Hull / Shield")]
    CARGO[("Cargo<br/>weight + volume limits")]
    CR[("Credits")]
    DATA[("Discovery data")]
  end
  subgraph Sinks
    THR["Thrust & warp"]
    QT["Quick travel"]
    SYS["Life support, sensors,<br/>modules, shields, tools"]
    DMG["Heat, impacts, black holes,<br/>life-support failure"]
    RES["Research costs"]
  end
  AST --> CARGO
  COM --> CARGO
  DER --> CARGO
  GHO --> CARGO
  GHO --> CR
  STA --> CARGO
  STA --> FUEL
  STA --> EN
  STA --> HULL
  SUN --> EN
  SCN --> DATA
  DATA -->|sell at station| CR
  CARGO -->|sell| CR
  CR --> STA
  CARGO -->|fuel cell R| FUEL
  CARGO -->|battery N| EN
  CARGO -->|scrap / plates H| HULL
  CARGO -->|refinery| CARGO
  CARGO --> RES
  FUEL -->|converter module| EN
  FUEL --> THR
  FUEL --> QT
  EN --> SYS
  EN -->|Ion Drive| THR
  EN --> QT
  DMG --> HULL
```

## 4. Navigation options

```mermaid
flowchart TB
  N{"How to travel?"}
  N -->|short / precise| M["Manual: WASD + Q/E<br/>Newtonian drift, gravity wells"]
  N -->|to a point or object| A["Click → autopilot<br/>steers around stars & planets,<br/>brakes on arrival"]
  N -->|empty space, fast| W["Hold Shift: Warp<br/>6000 u/s, heavy fuel use,<br/>laser & tractor disabled"]
  N -->|known place, far| Q["Quick travel (codex / map)<br/>fuel ∝ distance, max range,<br/>energy cost"]
  N -->|lucky| WH["Wormhole<br/>jump 60k-150k u"]
  A -.->|WASD takes over| M
  A -.->|Shift while autopiloting| W
```

| Autopilot to a station | Galaxy map with quick-travel range |
|---|---|
| ![Autopilot](images/03_autopilot.png) | ![Map](images/10_window_map.png) |

**Out of propellant:** main engines stop and only weak RCS thrusters remain (`ship.rcs_thrust`). The distress beacon is deferred (TODO-05).

## 5. Discovery and naming

```mermaid
sequenceDiagram
  participant Ship
  participant Game
  participant Main
  participant Dialog as Naming dialog
  loop every 0.25 s
    Ship->>Ship: entity within discovery range?
  end
  Ship->>Game: add_discovery(entry) (+ discovery data, stats)
  Game-->>Main: discovered(entry)
  Main->>Main: toast "Discovered: …"
  alt star / planet / moon and "Ask to name" setting on
    Main->>Dialog: queue → open when no other window is open
    Dialog->>Game: set_name_for(id, name) or keep the catalogue name
  end
  Note over Game: Default names follow conventions:<br/>stars "HD 40307" / "Tau Ceti" / "61 Cygni",<br/>planets "<star> b", moons "<planet> II".<br/>Renaming a star renames its default planets and moons.
```

Discovered objects appear in the **Codex** (C) and on the **Galaxy Map** (Tab), where they can be targeted, renamed or used as quick-travel destinations.

## 6. Salvage and collection

```mermaid
flowchart LR
  L["Hold Space<br/>laser aims at mouse"] --> HP["Target integrity drops<br/>(laser_dps)"]
  HP -->|0| D["Destroyed"]
  D --> Loot["Loot table roll<br/>× richness × salvage_yield"]
  D --> Split["Large asteroid → 2 fragments"]
  D --> Log["Derelict → lore log in codex"]
  Loot --> Drops["Floating drops"]
  Drops -->|small, within proximity_range| Cargo
  Drops -->|large: hold F tractor,<br/>pulls within tractor_range| Cargo["Cargo<br/>(if weight & volume allow)"]
  Drops -->|drones G| Cargo
  Cargo -->|full| Warn["'Cargo full (weight/volume)'<br/>jettison or craft"]
```

| Laser in action | Drops after salvage |
|---|---|
| ![Laser](images/04a_laser.png) | ![Drops](images/04_salvage_drops.png) |

## 7. Survival and warnings

```mermaid
flowchart TB
  T["HUD checks every 0.2 s"] --> C{"hull < 35%?<br/>fuel < 25%?<br/>energy < 20%?"}
  C -->|no| OK["No banner"]
  C -->|yes| W["Warning banner<br/>LOW or CRITICAL (< 10%)"]
  W --> I["Hint: press R / N / H if a usable item is in cargo"]
  W --> S["Nearest help from loaded objects + codex<br/>fuel → station, derelict, comet<br/>energy → star (if scoop), station, derelict<br/>hull → station, derelict, asteroid field"]
  S -->|press T| AP["Target set + autopilot"]
  E["Energy 0"] --> LS["Sensors offline, shields stop,<br/>life support fails → hull damage"]
  LS --> D{"Hull 0"}
  D -->|Relaxed / Standard| R["Reload last save"]
  D -->|Ironman| G["Run over, save deleted"]
```

| Low fuel suggestion | Destroyed |
|---|---|
| ![Low fuel](images/12_low_fuel_warning.png) | ![Destroyed](images/14_destroyed_dialog.png) |

Thresholds and suggestion kinds are in `warnings` in `game_config.json`. The fail state is the implemented default and is still awaiting confirmation (TODO-T07).

## 8. Research

```mermaid
stateDiagram-v2
  [*] --> Locked
  Locked --> Available : all prerequisites researched
  Available --> Running : Start (Lab installed + enabled, cost paid)
  Running --> Paused : Lab disabled / removed, or energy = 0
  Paused --> Running : condition cleared
  Running --> Available : Cancel (50% refund)
  Running --> Researched : time elapsed
  Researched --> [*] : stats recalculated, modules / recipes unlocked
```

Only one technology can be researched at a time. See [TECH_TREE.md](TECH_TREE.md).

![Tech tree](images/10_window_tech.png)

## 9. Docking and trade

```mermaid
sequenceDiagram
  participant Ship
  participant Main
  participant Station as Station window
  participant Game
  Ship->>Ship: within dock_range and speed ≤ dock_max_speed
  Ship-->>Ship: hint "Press X to dock"
  Ship->>Main: docked(station)
  Main->>Game: autosave
  Main->>Station: open (game paused)
  Station->>Game: refuel / recharge / repair (credits)
  Station->>Game: sell cargo, sell discovery data
  Station->>Game: buy items (limited by cargo space)
```

![Station](images/11_station.png)

## 10. Hazards and anomalies at a glance

| Object | Effect | Counter-play |
|---|---|---|
| Star heat zone (dashed red ring) | Damage grows quadratically toward the surface; flares ×3 with a warning | Keep out; Thermal Plating, Heat Shield module |
| Solar flare | Temporary heat spike | Leave when warned |
| Planet / moon gravity | Pulls the ship; collisions hurt | Gravity Assist tech makes thrust deep in wells cheaper |
| Black hole | Huge gravity, heavy damage near the horizon | Autopilot avoids it; keep away |
| Nebula | Radar range ×0.35, shield regen ×2.5 | Recharge shields, navigate carefully |
| Ion storm (drifts) | Drains energy | Go around |
| Asteroid field | Collisions; mining target | Slow down; never warp through it |
| Wormhole | Jumps 60k–150k units | Free long-distance travel |
| Unknown signal | Credits and supply cache | Fly into it |
| Escape pod | Timed rescue (120 s) for a reward | Reach it in time |
| Ghost ship | Rich derelict with data cores | Salvage it |
