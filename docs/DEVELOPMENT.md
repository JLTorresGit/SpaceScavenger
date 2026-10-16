# Development Guide

## Environment

| Tool | Version | Notes |
|---|---|---|
| Godot | 4.7.2 standard build (GDScript) | `winget install GodotEngine.GodotEngine`. The .NET build is not needed. |
| Renderer | GL Compatibility | Runs on modest GPUs and is ready for a Web export. |
| Python | 3.x (optional) | Only for `tools/gen_docs.py`. |

On this machine winget installed the console binary at
`%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`.
Add that folder to `PATH` (or alias it as `godot`) to use the commands below.

## Everyday commands

```bash
godot --path . -e
```
Opens the editor.

```bash
godot --path .
```
Runs the game.

```bash
godot --headless --path . res://tests/tests.tscn
```
Runs the unit tests (exit code 0 = pass).

```bash
godot --path . -- --autotest=./autotest_shots
```
Runs the scripted play session and saves screenshots. The session covers the menu, flight, autopilot, laser, tractor, warp streaming, a star system, scanning, every window, docking, the low-fuel warning, save/load, photo mode, and death followed by a reload. It prints summary lines prefixed with `[autotest]`, including the minimum FPS while warping.

```bash
python tools/gen_docs.py
```
Regenerates `docs/TECH_TREE.md` and `docs/CONFIG_REFERENCE.md` from the config files.

## Test suite

`tests/tests.gd` covers:

| Area | Checks |
|---|---|
| Scripts | Every script under `scripts/` loads and compiles. |
| Config | Both JSON files parse; key values exist; input bindings are applied. |
| Generation | Chunks and systems are deterministic; different seeds differ; ids are unique; far coordinates work. |
| Home content | The home system and station exist; the start position is clear. |
| Naming | Roman numerals, planet and moon suffixes, deterministic star names. |
| Stats & modules | Tech effects, Ion Drive engine mode, slot limits, disabled modules. |
| Cargo | Weight and volume limits are both enforced. |
| Crafting | Inputs consumed, outputs added, locked recipes blocked. |
| Research | Cost paid up front, pause without the Lab, completion, prerequisites, Lab requirement. |
| Saves | JSON round trip of seed, difficulty, cargo, research, removals, names and 1e9-scale coordinates. |
| Data integrity | Every tech prerequisite, cost item, unlocked module or recipe, effect stat, recipe item and loot item exists. |

Run the tests after any change to config or code. Data typos are caught by the integrity checks.

## Coding conventions

* GDScript with static types where the type is known. Values that come from other scripts' untyped members (`e.position`, `ship.velocity`) need an explicit type: write `var p: Vector2 = …`, because `:=` cannot infer a type from a Variant.
* No numeric literals for gameplay values in code. Add them to `game_config.json` and read them with `Config.fval/ival/dict`.
* Generation code (`Generator`, `Naming`) must stay pure (no nodes, no global mutable state) because it runs on worker threads.
* Entities are dictionary-driven: the generator describes them, `Universe.spawn` builds them, and `setup()` reads the dictionary.
* UI is built in code with `UiKit` helpers. Windows extend `WindowPanel` and implement `_build()` and `refresh()`. Use `set_anchors_and_offsets_preset` (not `set_anchors_preset`) when filling a parent created earlier.
* Avoid multi-statement one-line lambdas; call a small method instead.
* Persistent state goes in `Game` and must be added to both `to_dict()` and `from_dict()`. Bump `SAVE_VERSION` and extend `migrate()` when the format changes.

## How-to recipes

### Add a technology
1. Add a node to `config/tech_tree.json` (see the format in [CONFIGURATION.md](CONFIGURATION.md#3-tech_treejson-format)).
2. Run the tests (they validate references), then run `python tools/gen_docs.py`.

### Add a ship stat that tech can improve
1. Add the key to `ship` in `game_config.json`.
2. Use it in code with `Game.stat("key")`.
3. Reference it from tech or module `effects`.

### Add an item / recipe / module
Add entries to `items`, `recipes` or `modules` in `game_config.json`. If something should not be available at the start, set `"starting": false` and unlock it from a tech node.

### Add a new kind of world object
1. Create `scripts/entities/<kind>.gd` extending `SpaceEntity`. Implement `_setup()`, `_draw()`, and optionally `scan_info()`, `_destroyed()` and `on_ship_contact()`.
2. Register it in `Universe.SCRIPTS`.
3. Emit dictionaries for it from `Generator.chunk_at` or `system_at` with a stable id and add the spawn chance to `world.spawn`.
4. Add a `radar_colors.<kind>` entry and `discovery.range` / `data_value` entries.
5. If it affects the ship, handle it in `Ship._environment` (hazard) or through `on_ship_contact`.

### Add a window
Subclass `WindowPanel`, add a case in `main._window()`, and, if it needs a hotkey, add an `input_bindings` action and a `WINDOW_KEYS` entry in `main.gd`.

## Exporting (pending, TODO-09)

1. In the editor, install the export templates (Editor → Manage Export Templates).
2. Add presets for Windows, Linux, macOS and Web. Include `*.json` in **Resources → Filters to export non-resource files** so the `config/` files are packed.
3. Optionally ship a `config/` folder next to the executable. It overrides the packed files, so testers can tune values.

## Repository layout

```
SpaceScavenger/
├─ project.godot          engine settings (window, renderer, autoloads)
├─ icon.svg
├─ README.md
├─ config/                game_config.json, tech_tree.json
├─ docs/                  this documentation + images/
├─ scenes/main.tscn
├─ scripts/
│  ├─ main.gd
│  ├─ autoload/           config.gd, game.gd
│  ├─ world/              generator, universe, naming, camera_rig, starfield
│  ├─ entities/           space_entity + 12 entity kinds
│  ├─ ship/               ship.gd, drone.gd
│  └─ ui/                 hud, radar, main_menu, window_panel, simple_windows,
│                         game_windows, map_window, ui_kit
├─ tests/                 tests.tscn, tests.gd
└─ tools/gen_docs.py
```
