# Space Scavenger — TODO / Future Work

Items deliberately left out of the current build. Keep for later reference.

## Deferred by the product owner

| ID | Item | Notes |
|---|---|---|
| TODO-01 | **Co-op multiplayer** | Deterministic seed generation already makes shared worlds easier: only deltas (mined/looted/named) and player state need syncing. |
| TODO-02 | **Base building / claiming a planet** | Claimed planets could act as personal refuel points and quick-travel anchors. |
| TODO-03 | **Factions with reputation** | Stations would belong to factions; prices and access depend on reputation. |
| TODO-04 | **3D version** | Keep simulation code separated from rendering so a 3D renderer could reuse it. |
| TODO-05 | **Distress beacon (G3)** | Broadcast a signal asking for help when stranded. Open design: who answers (station tug, NPC, nobody), wait time, rescue fee or cargo penalty, chance of hostile response. |
| TODO-06 | **Threats, enemies and NPCs (G8)** | Pirates, automated defence drones on derelicts, NPC traders. Requires a combat/weapons design ("weapons disabled in warp" already anticipated). |

## Needs confirmation

| ID | Item | Notes |
|---|---|---|
| TODO-T07 | **Fail state at hull 0 (G2)** | Implemented default: Relaxed/Standard reload the last save (autosave), Ironman deletes the save. Alternatives: respawn at last station losing cargo, or a towing fee. |

## Additional suggestions found during the build

| ID | Item | Notes |
|---|---|---|
| TODO-07 | **Audio** | Engine hum, thruster, laser, tractor, alarm sounds; ambient music per biome. Sound volumes would go in `game_config.json`. |
| TODO-08 | **In-game key rebinding UI** | Bindings are already defined in `game_config.json`; an options screen to edit them in game is pending. |
| TODO-09 | **Export presets and CI** | Add `export_presets.cfg` (Windows, Linux, macOS, Web) and a GitHub Actions workflow running the headless tests and exports. Needs Godot export templates. |
| TODO-10 | **Moving orbits** | Planets and moons are static today. Real orbital motion would enable true gravity slingshots (the current "gravity assist" is a fuel-efficiency bonus). |
| TODO-11 | **Art pass** | Everything is drawn procedurally with vector shapes. Sprites, shaders (heat haze, warp streaks, nebula clouds) and particles would improve readability. |
| TODO-12 | **Tutorial / onboarding** | Guided first flight: thrust, stop, mine, collect, refuel. |
| TODO-13 | **Localization** | Move UI strings to a translation CSV (Godot supports this natively). |
| TODO-14 | **Tech tree visual editor** | A small editor plugin or web page to edit `tech_tree.json` and preview the graph and costs. |
| TODO-15 | **Balancing telemetry** | Optional local log of fuel/energy over time and causes of death to help tune the config file. |
| TODO-16 | **Cloud saves / Steam integration** | GodotSteam plugin: achievements, cloud saves, workshop for mods. |
| TODO-17 | **Planet landing / surface scanning** | Orbit a planet to run a longer scan for rare resources. |
| TODO-18 | **Ship customisation** | Hull skins and colours; multiple hull classes with different slot counts. |
| TODO-19 | **Save thumbnails** | Screenshot attached to each save slot in the load menu. |
| TODO-20 | **Controller-friendly menus** | Menus are mouse-first today; full focus navigation for gamepad is pending. |
| TODO-21 | **Warp safety** | Hitting an asteroid at warp speed is very dangerous (damage per impact is capped by `collision_max_damage`). Consider an automatic warp drop near dense fields or a proximity alarm. |
| TODO-22 | **Persistent loose drops** | Loot dropped from salvage is transient: it vanishes if you fly away and its chunk unloads. Could be saved per chunk. |
| TODO-23 | **Moving hazards persistence** | Comets, ion storms and drifting asteroids reset to their generated position when their chunk reloads. |
