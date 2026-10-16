# Space Scavenger — Requirements

Version 1.1 · 2026-10-15 · Status: **Approved for build**

Space Scavenger is a 2D top-down space survival and exploration game. The player flies a solitary research/scavenger vessel through a procedurally generated, infinite universe, gathering resources from derelicts and celestial bodies, and managing fuel and energy to sustain long-distance travel.

**Legend** — Priority: **M** Must · **S** Should · **C** Could.
Implementation status and verification for each ID: [REQUIREMENTS_STATUS.md](REQUIREMENTS_STATUS.md).
Every numeric value mentioned below (limits, costs, rates, prices) lives in `config/game_config.json`; every technology lives in `config/tech_tree.json` (see CFG-01/02).

---

## 1. Decisions log (gap clarifications)

| ID | Topic | Decision |
|---|---|---|
| G1 | Name | Final name is **Space Scavenger**. |
| G2 | Fail state | Warn the player early when fuel, energy or hull run low and suggest the nearest planet, station or resource field (SHP-09). At hull 0 the ship is destroyed and the game reloads the last save (Relaxed/Standard) or ends the run (Ironman). *Fail-state behaviour to be confirmed — see TODO-T07.* |
| G3 | Distress beacon | Deferred to TODO (broadcast a signal asking for help). |
| G4 | Quick travel | Costs resources (fuel, scaling with distance) and is limited to a maximum distance that the tech tree can extend. |
| G5 | Controls | Mouse sets waypoints/targets; WASD flies manually. Manual input cancels autopilot. |
| G6 | Cargo | Both weight **and** volume are tracked and both have limits. |
| G7 | Research | Costs resources **and** time. A **Lab module** must be installed and enabled before research can start. |
| G8 | Threats/NPCs | Deferred to TODO. |
| G9 | Fuel vs energy | Both exist. Chemical engines burn fuel; the tech tree unlocks a fuel→energy converter and later an Ion Drive that thrusts on energy, so late game can run on energy alone. |
| G10 | Tractor vs proximity | Proximity collection only picks up *small* drops in a very small radius. Tractor beam is **short range** but pulls any drop, including large ones. |

---

## 2. Requirements

### 2.1 Configuration (CFG)
| ID | Requirement | Pri |
|---|---|---|
| CFG-01 | All tunable values (limits, prices, costs, rates, spawn chances, item weights/volumes, recipes, modules, difficulty, achievements, warnings) are read from one editable file: `config/game_config.json`. | M |
| CFG-02 | Every technology node (branch, cost, research time, prerequisites, effects) is defined in one editable file: `config/tech_tree.json`. | M |
| CFG-03 | Optional override files in `user://mods/` are deep-merged over both files at startup (mod support). | S |
| CFG-04 | Input bindings (keyboard and gamepad) are defined in the config file. | S |

### 2.2 Camera (CAM)
| ID | Requirement | Pri |
|---|---|---|
| CAM-01 | Fixed top-down view centred on the ship. | M |
| CAM-02 | Smooth dynamic zoom (mouse wheel / gamepad). | M |
| CAM-03 | Camera follows with inertia and leads in the direction of velocity. | M |
| CAM-04 | Photo mode: pause, hide HUD, free camera pan and zoom. | C |

### 2.3 Navigation & Universe (NAV)
| ID | Requirement | Pri |
|---|---|---|
| NAV-01 | Infinite 2D procedural universe. | M |
| NAV-02 | Chunks generate around the ship and unload when far away. | M |
| NAV-03 | Deterministic, seed-based generation; universes can be shared by seed. | M |
| NAV-04 | Floating origin so precision never degrades at extreme distances. | M |
| NAV-05 | Newtonian-lite flight: thrust, rotation, drift; counter-thrust needed to stop. | M |
| NAV-06 | Manual flight with WASD (A/D rotate, W thrust, S retro, Q/E lateral RCS). | M |
| NAV-07 | Mouse click sets a waypoint or selects an object as target; autopilot flies to it. | M |
| NAV-08 | Thrust consumes fuel (or energy with Ion Drive). | M |
| NAV-09 | Standard flight mode with low consumption. | M |
| NAV-10 | Warp mode: high speed, high fuel use, salvage tools disabled. | M |
| NAV-11 | Stars, planets and moons exert gravity within a sphere of influence. | M |
| NAV-12 | Gravity assist: thrusting deep inside a gravity well is more fuel-efficient. | C |
| NAV-13 | Navigate to any discovered object selected in the ship console. | M |
| NAV-14 | Quick travel to a discovered object: costs fuel by distance, limited by a maximum range. | M |
| NAV-15 | Autopilot shows distance, ETA and estimated fuel to the target. | S |

### 2.4 World entities (WLD)
| ID | Requirement | Pri |
|---|---|---|
| WLD-01 | Stars with a thermal danger zone that damages shields then hull. | M |
| WLD-02 | Solar energy harvesting near stars when a Solar Scoop is installed. | M |
| WLD-03 | Planets and moons with gravity. | M |
| WLD-04 | High concentration of derelicts and scrap in low planetary orbit. | M |
| WLD-05 | Asteroid fields: hazards that can be mined with the salvage laser. | M |
| WLD-06 | Asteroids yield Iron, Titanium and Rare Ore. | M |
| WLD-07 | Derelicts (stations, satellites, vessels) yield fuel cells, electronics, scrap alloys and battery units. | M |
| WLD-08 | Hazards: black holes, nebulae (reduce sensors, regenerate shields), ion storms (drain energy), solar flares, comets (ice). | S |
| WLD-09 | Anomalies: wormholes, unknown signals (caches), ghost ships, timed rescue missions. | C |
| WLD-10 | Trading outposts/stations: sell, buy, refuel, recharge, repair, sell discovery data. | S |
| WLD-11 | Sector "biomes": dense core regions vs sparse rim regions; richness grows with distance from origin. | S |
| WLD-12 | Derelicts carry procedural log entries (lore) added to the codex. | C |

### 2.5 Resources & scavenging (RES)
| ID | Requirement | Pri |
|---|---|---|
| RES-01 | Fuel (tank) is refilled from Fuel Cells. | M |
| RES-02 | Energy (battery) powers shields, sensors, tractor, laser, life support, modules; refilled from Battery Units, solar scoop or converter. | M |
| RES-03 | Scrap alloys and minerals are used for repairs, crafting, research. | M |
| RES-04 | Tractor beam: short range, pulls any drop, costs energy. | M |
| RES-05 | Salvage laser breaks asteroids and derelict hulls into collectable fragments. | M |
| RES-06 | Proximity collection automatically picks up small drops in a very small radius. | M |
| RES-07 | Cargo tracks weight and volume; both have limits. | M |
| RES-08 | Refining/crafting turns raw materials into refined goods (recipes in config). | S |
| RES-09 | Jettison cargo (spawns a floating drop). | S |
| RES-10 | Collector drones fetch nearby drops automatically (tech unlock). | C |
| RES-11 | Deep scan of an object reveals its contents and yields sellable discovery data. | S |

### 2.6 Ship systems & survival (SHP)
| ID | Requirement | Pri |
|---|---|---|
| SHP-01 | Fuel consumed continuously while thrusting. | M |
| SHP-02 | Life support and active sensors drain energy over time. | M |
| SHP-03 | Without fuel the ship drifts using weak RCS thrusters only. | M |
| SHP-04 | Shields absorb impacts and heat; regenerate using energy. | M |
| SHP-05 | Hull takes damage when shields are down. | M |
| SHP-06 | Hull 0 = ship destroyed → reload last save / run ends in Ironman. | M |
| SHP-07 | Modular component slots; modules are unlocked by research and draw energy. | S |
| SHP-08 | Fuel→energy converter and energy-based Ion Drive via tech tree. | S |
| SHP-09 | Low fuel / energy / hull warnings with a suggestion and one-key course to the nearest helpful place. | M |
| SHP-10 | Repair hull using scrap alloys. | M |

### 2.7 HUD, radar & console (HUD)
| ID | Requirement | Pri |
|---|---|---|
| HUD-01 | Fuel and energy gauges with consumption rates. | M |
| HUD-02 | Shield and hull gauges. | M |
| HUD-03 | Speedometer + vector arrow (velocity vs heading). | M |
| HUD-04 | Radar/mini-map with POIs (derelicts, hazards, resources, bodies) within radar range. | M |
| HUD-05 | Cargo quick view (weight and volume). | M |
| HUD-06 | Target panel and off-screen target indicator. | M |
| HUD-07 | Galaxy map: zoomable explored space, filters, click to target. | S |
| HUD-08 | Codex/logbook: discoveries with stats, notes, discovery date, lore logs. | S |
| HUD-09 | Toast notifications and warning banner. | M |
| HUD-10 | Help overlay listing controls. | S |

### 2.8 Naming (NAM)
| ID | Requirement | Pri |
|---|---|---|
| NAM-01 | On discovering a star, planet or moon the player can type a name or accept a random one. | M |
| NAM-02 | Random names follow astronomical conventions (catalogue IDs e.g. "HD 40307", planets get b/c/d…, moons get Roman numerals). | M |
| NAM-03 | Objects can be renamed later from the codex. | C |

### 2.9 Save & restore (SAV)
| ID | Requirement | Pri |
|---|---|---|
| SAV-01 | Save and restore the full game state. | M |
| SAV-02 | Delta saves: seed + only what changed (mined, looted, named, discovered). | M |
| SAV-03 | List of all discovered objects, usable for targeting and quick travel. | M |
| SAV-04 | Multiple save slots plus autosave. | S |
| SAV-05 | Versioned save format with migration hook. | S |

### 2.10 Technology tree (TEC)
| ID | Requirement | Pri |
|---|---|---|
| TEC-01 | Tech tree researched with resources. | M |
| TEC-02 | Research takes time and needs the Lab module enabled. | M |
| TEC-03 | Branches: Engines, Fuel & Power, Hull & Shields, Electronics, Salvage, Cargo. | M |
| TEC-04 | Researched techs change ship stats and unlock modules/recipes. | M |
| TEC-05 | All nodes defined in `config/tech_tree.json`. | M |

### 2.11 Meta & quality of life (META)
| ID | Requirement | Pri |
|---|---|---|
| META-01 | Statistics (distance, discoveries, salvage, deaths…) and achievements (defined in config). | S |
| META-02 | Difficulty presets: Relaxed, Standard, Ironman (permadeath). | S |
| META-03 | Seed shown in game and entered at New Game (shareable). | S |
| META-04 | Settings: UI scale, colourblind-safe palette, game speed, persisted per player. | S |

### 2.12 Non-functional (NFR)
| ID | Requirement | Pri |
|---|---|---|
| NFR-01 | 60 FPS without hitches while chunks stream (generation off the main thread). | M |
| NFR-02 | No precision jitter at extreme distances. | M |
| NFR-03 | Keyboard + mouse, basic gamepad support. | S |
| NFR-04 | Automated tests for determinism, stats, cargo and save round-trip. | S |
| NFR-05 | Engine: Godot 4.x, GDScript only. | M |
