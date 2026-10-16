# Space Scavenger

2D top-down space survival and exploration in an infinite, procedurally generated universe.
Built with **Godot 4.7 (GDScript only)**, with all art drawn procedurally (no asset files).

Full documentation is in [docs/](docs/README.md): player guide, game flow, architecture diagrams,
configuration guide, generated tech tree and config reference, requirements with traceability, development guide and TODO list.

## Run

1. Install Godot 4.7+ (standard build, not .NET), e.g. `winget install GodotEngine.GodotEngine`.
2. Open the project: `godot --path . -e` (editor) or run directly: `godot --path .`

## Tuning (single files)

| File | Contents |
|---|---|
| `config/game_config.json` | Every limit, rate, price, cost, spawn chance, item, loot table, recipe, module, difficulty preset, achievement, warning threshold, palette and key binding. |
| `config/tech_tree.json` | Every technology node: branch, tier, cost, research time, prerequisites, stat effects, unlocks. |

Edit and press **F6** in game to hot-reload (or restart). Optional overrides placed in
`user://mods/game_config.json` / `user://mods/tech_tree.json` are deep-merged on top (mod support).
In exported builds a `config/` folder next to the executable takes priority, so the files stay editable.

Tech effects use `{"stat": <ship stat>, "op": "add" | "mul" | "set", "value": n}` where the stat is any key of
`ship` in `game_config.json`.

## Controls (default)

| Key | Action |
|---|---|
| W / S | Main thrust / retro thrust |
| A / D | Rotate |
| Q / E | RCS strafe |
| Shift (hold) | Warp — high speed, high fuel use, tools disabled |
| Left click | Set waypoint, or target the clicked object; autopilot engages |
| Right click | Clear target |
| Space (hold) | Salvage laser, aimed with the mouse |
| F (hold) | Tractor beam (short range, pulls large drops) |
| V | Deep scan (target / object under mouse / nearest) |
| G | Launch collector drones (Drone Bay module) |
| X / Enter | Dock at a station (slow down inside the docking ring) |
| T | Set course to the suggested help when a warning is shown |
| R / N / H | Use fuel cell / battery unit / repair hull |
| Wheel, = / - | Zoom |
| Tab | Galaxy map |
| C | Codex (discoveries, logs, rename, quick travel) |
| K | Technology tree |
| I | Cargo & crafting |
| U | Ship modules |
| O | Statistics & achievements |
| P | Photo mode |
| F1 | Help |
| F5 / F9 | Quick save / quick load |
| Esc | Pause menu / close window |

Basic gamepad bindings are included; all bindings are in `input_bindings` in the config file.

## Project layout

```
config/            game_config.json, tech_tree.json  (all tuning)
docs/              REQUIREMENTS.md, TODO.md
scenes/main.tscn   entry scene (everything else is built in code)
scripts/
  autoload/        config.gd (loads config, input map), game.gd (state, cargo, research, saves, settings)
  world/           generator.gd (deterministic chunks/systems), universe.gd (streaming, floating origin,
                   gravity, queries), naming.gd, camera_rig.gd, starfield.gd
  entities/        star, planet/moon, asteroid/comet, derelict, pickup, station, nebula, ion storm,
                   black hole, wormhole, beacon (signal / rescue pod), asteroid-field marker
  ship/            ship.gd (flight, autopilot, tools, survival), drone.gd
  ui/              hud.gd, radar.gd, main_menu.gd, window_panel.gd, simple_windows.gd,
                   game_windows.gd, map_window.gd, ui_kit.gd
  main.gd          world/UI orchestration, input routing, death/reload, autosave, autotest
tests/             tests.tscn + tests.gd (headless unit tests)
```

### Key technical choices

- **Infinite universe**: 4,000-unit chunks streamed around the ship (generated on worker threads), plus
  star systems on a 50,000-unit cell grid. Everything is derived from `seed + coordinates`, so only
  player changes are saved (mined/looted ids, names, discoveries).
- **Floating origin**: world coordinates are 64-bit; node positions are re-centred whenever the ship moves
  20,000 units from the origin, so there is no jitter far from home.
- **Saves**: versioned JSON in `user://saves/` (manual slots, quicksave, autosave; Ironman keeps one slot).
  `Game.migrate()` is the hook for future format changes.

## Tests

```bash
godot --headless --path . res://tests/tests.tscn
```

Scripted play session that saves screenshots (menus, flight, salvage, warp, station, warnings, death/reload):

```bash
godot --path . -- --autotest=./autotest_shots
```
