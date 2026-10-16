extends Node
## Persistent game state: ship resources, cargo, research, modules, discoveries,
## statistics, save/load and player settings. Scene nodes read and write it.

signal toast(text: String, kind: String)
signal cargo_changed
signal stats_recalculated
signal research_changed
signal discovered(entry: Dictionary)
signal achievement_unlocked(achievement: Dictionary)
signal credits_changed
signal names_changed

const SAVE_VERSION := 1
const SAVE_DIR := "user://saves/"
const SETTINGS_PATH := "user://settings.json"
const AUTOSAVE_SLOT := "autosave"

var active := false
var world_seed := 0
var difficulty := "standard"
var origin_x := 0.0          # floating-origin offset (64-bit floats)
var origin_y := 0.0
var ship_state := {}         # position/velocity snapshot used by save/load
var fuel := 0.0
var energy := 0.0
var shield := 0.0
var hull := 0.0
var credits := 0
var data_points := 0
var cargo := {}              # item id -> count
var researched := {}         # tech id -> true
var research := {}           # {"id", "remaining", "total"} or empty
var modules_unlocked := {}   # module id -> true
var modules_installed: Array = []
var modules_enabled := {}    # module id -> bool
var recipes_unlocked := {}   # recipe id -> true
var engine_mode := "fuel"
var discoveries := {}        # id -> entry
var names := {}              # id -> player-chosen name
var removed := {}            # id -> true (delta save: mined / looted / collected)
var visited := {}            # "cx,cy" -> true
var scanned := {}            # id -> true
var logs: Array = []         # lore entries {title, text, date}
var stats := {}
var achievements := {}       # id -> date string
var target := {}             # {id, name, kind, wx, wy}
var active_rescue := {}      # {id, remaining}
var play_time := 0.0
var current_slot := ""
var ship_stats := {}         # computed from base + tech + modules

var settings := {
	"ui_scale": 1.0,
	"colorblind": false,
	"game_speed": 1.0,
	"ask_names": true,
	"fullscreen": false,
	"show_hints": true,
}


func _ready() -> void:
	load_settings()
	recalc_stats()


# --- Lifecycle --------------------------------------------------------------

func new_game(seed_value: int, diff: String) -> void:
	_reset()
	world_seed = seed_value
	difficulty = diff if Config.dict("difficulty").has(diff) else "standard"
	credits = int(diff_cfg().get("start_credits", 0))
	for m in Config.get_v("starting_modules", []):
		modules_unlocked[str(m)] = true
		modules_installed.append(str(m))
		modules_enabled[str(m)] = true
	for m in Config.dict("modules").keys():
		if Config.dict("modules")[m].get("starting", false):
			modules_unlocked[m] = true
	for r in Config.dict("recipes").keys():
		if Config.dict("recipes")[r].get("starting", false):
			recipes_unlocked[r] = true
	var start_cargo := Config.dict("start.cargo")
	for item_id in start_cargo.keys():
		cargo[item_id] = int(start_cargo[item_id])
	recalc_stats()
	fuel = stat("fuel_capacity")
	energy = stat("energy_capacity")
	shield = stat("shield_max")
	hull = stat("hull_max")
	ship_state = {"wx": 0.0, "wy": 0.0, "vx": 0.0, "vy": 0.0, "rot": -PI / 2.0}
	current_slot = ""
	active = true
	cargo_changed.emit()
	credits_changed.emit()


func _reset() -> void:
	origin_x = 0.0
	origin_y = 0.0
	cargo = {}
	researched = {}
	research = {}
	modules_unlocked = {}
	modules_installed = []
	modules_enabled = {}
	recipes_unlocked = {}
	engine_mode = "fuel"
	discoveries = {}
	names = {}
	removed = {}
	visited = {}
	scanned = {}
	logs = []
	stats = {}
	achievements = {}
	target = {}
	active_rescue = {}
	play_time = 0.0
	data_points = 0


func diff_cfg() -> Dictionary:
	return Config.dict("difficulty." + difficulty)


func consumption_mult() -> float:
	return float(diff_cfg().get("consumption_multiplier", 1.0))


func damage_mult() -> float:
	return float(diff_cfg().get("damage_multiplier", 1.0))


func is_permadeath() -> bool:
	return bool(diff_cfg().get("permadeath", false))


func notify(text: String, kind := "info") -> void:
	toast.emit(text, kind)


# --- Ship stats ---------------------------------------------------------------

func recalc_stats() -> void:
	var s: Dictionary = Config.dict("ship").duplicate(true)
	engine_mode = "fuel"
	for tech_id in researched.keys():
		var node: Dictionary = Config.tech_nodes.get(tech_id, {})
		_apply_effects(s, node.get("effects", []))
		var sets: Dictionary = node.get("sets", {})
		if sets.has("engine_mode"):
			engine_mode = str(sets["engine_mode"])
	for m in modules_installed:
		if modules_enabled.get(m, true):
			_apply_effects(s, Config.dict("modules." + m).get("effects", []))
	ship_stats = s
	fuel = minf(fuel, stat("fuel_capacity"))
	energy = minf(energy, stat("energy_capacity"))
	shield = minf(shield, stat("shield_max"))
	hull = minf(hull, stat("hull_max"))
	stats_recalculated.emit()


static func _apply_effects(s: Dictionary, effects: Array) -> void:
	for e in effects:
		var key := str(e.get("stat", ""))
		var v := float(e.get("value", 0.0))
		var cur := float(s.get(key, 0.0))
		match str(e.get("op", "add")):
			"add": s[key] = cur + v
			"mul": s[key] = cur * v
			"set": s[key] = v


func stat(key: String) -> float:
	return float(ship_stats.get(key, 0.0))


# --- Cargo --------------------------------------------------------------------

func count(item_id: String) -> int:
	return int(cargo.get(item_id, 0))


func cargo_weight() -> float:
	var w := 0.0
	for k in cargo.keys():
		w += float(Config.item(k).get("weight", 1.0)) * int(cargo[k])
	return w


func cargo_volume() -> float:
	var v := 0.0
	for k in cargo.keys():
		v += float(Config.item(k).get("volume", 1.0)) * int(cargo[k])
	return v


## How many units of an item still fit, limited by both weight and volume.
func space_for(item_id: String) -> int:
	var def := Config.item(item_id)
	var w := maxf(float(def.get("weight", 1.0)), 0.001)
	var v := maxf(float(def.get("volume", 1.0)), 0.001)
	var by_w := floori((stat("cargo_max_weight") - cargo_weight()) / w + 0.0001)
	var by_v := floori((stat("cargo_max_volume") - cargo_volume()) / v + 0.0001)
	return maxi(0, mini(by_w, by_v))


## Which limit blocks this item: "", "weight" or "volume".
func cargo_limit_reason(item_id: String) -> String:
	var def := Config.item(item_id)
	if cargo_weight() + float(def.get("weight", 1.0)) > stat("cargo_max_weight") + 0.0001:
		return "weight"
	if cargo_volume() + float(def.get("volume", 1.0)) > stat("cargo_max_volume") + 0.0001:
		return "volume"
	return ""


func add_item(item_id: String, n: int, ignore_limits := false) -> int:
	var added := n if ignore_limits else mini(n, space_for(item_id))
	if added <= 0:
		return 0
	cargo[item_id] = count(item_id) + added
	cargo_changed.emit()
	return added


func remove_item(item_id: String, n: int) -> bool:
	if count(item_id) < n:
		return false
	cargo[item_id] = count(item_id) - n
	if cargo[item_id] <= 0:
		cargo.erase(item_id)
	cargo_changed.emit()
	return true


func has_cost(cost: Dictionary) -> bool:
	for k in cost.keys():
		if count(k) < int(cost[k]):
			return false
	return true


func pay_cost(cost: Dictionary) -> bool:
	if not has_cost(cost):
		return false
	for k in cost.keys():
		remove_item(k, int(cost[k]))
	return true


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in cost.keys():
		parts.append("%d %s" % [int(cost[k]), Config.item_name(k)])
	return ", ".join(parts) if not parts.is_empty() else "free"


func use_item(item_id: String) -> bool:
	var use: Dictionary = Config.item(item_id).get("use", {})
	if use.is_empty() or count(item_id) <= 0:
		return false
	var amount := float(use.get("amount", 0))
	match str(use.get("restore", "")):
		"fuel":
			if fuel >= stat("fuel_capacity") - 0.5:
				notify("Fuel tank is already full.")
				return false
			fuel = minf(stat("fuel_capacity"), fuel + amount)
		"energy":
			if energy >= stat("energy_capacity") - 0.5:
				notify("Battery is already full.")
				return false
			energy = minf(stat("energy_capacity"), energy + amount)
		"hull":
			if hull >= stat("hull_max") - 0.5:
				notify("Hull is already at full integrity.")
				return false
			hull = minf(stat("hull_max"), hull + amount)
		_:
			return false
	remove_item(item_id, 1)
	notify("Used %s." % Config.item_name(item_id), "good")
	return true


## Uses the first cargo item that restores the given resource (cheapest first).
func use_best(restore: String) -> bool:
	var candidates: Array = []
	for k in cargo.keys():
		var use: Dictionary = Config.item(k).get("use", {})
		if str(use.get("restore", "")) == restore:
			candidates.append(k)
	candidates.sort_custom(func(a, b): return float(Config.item(a).get("price", 0)) < float(Config.item(b).get("price", 0)))
	if candidates.is_empty():
		notify("No items in cargo restore %s." % restore, "warning")
		return false
	return use_item(candidates[0])


func add_credits(n: int) -> void:
	credits += n
	if n > 0:
		stat_add("credits_earned", n)
	credits_changed.emit()


# --- Crafting -----------------------------------------------------------------

func recipe_block_reason(recipe_id: String) -> String:
	var r := Config.dict("recipes." + recipe_id)
	if r.is_empty():
		return "Unknown recipe"
	if not recipes_unlocked.has(recipe_id):
		return "Not researched"
	var module := str(r.get("module", ""))
	if module != "" and not module_active(module):
		return "Needs %s module" % Config.dict("modules." + module).get("name", module)
	if not has_cost(r.get("inputs", {})):
		return "Missing inputs"
	return ""


func craft(recipe_id: String) -> bool:
	var reason := recipe_block_reason(recipe_id)
	if reason != "":
		notify(reason, "warning")
		return false
	var r := Config.dict("recipes." + recipe_id)
	pay_cost(r.get("inputs", {}))
	var outputs: Dictionary = r.get("outputs", {})
	for k in outputs.keys():
		var n := int(outputs[k])
		var added := add_item(k, n)
		if added < n:
			# Output that does not fit is lost to space; warn the player.
			notify("Cargo full: %d %s lost." % [n - added, Config.item_name(k)], "warning")
	stat_add("items_crafted")
	notify("Crafted %s." % r.get("name", recipe_id), "good")
	return true


# --- Modules ------------------------------------------------------------------

func module_active(id: String) -> bool:
	return modules_installed.has(id) and modules_enabled.get(id, true)


func free_slots() -> int:
	return int(stat("module_slots")) - modules_installed.size()


func install_module(id: String) -> bool:
	if not modules_unlocked.has(id) or modules_installed.has(id):
		return false
	if free_slots() <= 0:
		notify("No free module slots.", "warning")
		return false
	modules_installed.append(id)
	modules_enabled[id] = true
	recalc_stats()
	return true


func uninstall_module(id: String) -> void:
	if id == "lab" and not research.is_empty():
		notify("Research paused: Lab removed.", "warning")
	modules_installed.erase(id)
	modules_enabled.erase(id)
	recalc_stats()


func set_module_enabled(id: String, on: bool) -> void:
	modules_enabled[id] = on
	recalc_stats()


func module_energy_drain() -> float:
	var total := 0.0
	for m in modules_installed:
		if modules_enabled.get(m, true):
			total += float(Config.dict("modules." + m).get("energy_per_sec", 0.0))
	if not research.is_empty() and module_active("lab"):
		total += float(Config.dict("modules.lab").get("research_energy_per_sec", 0.0))
	return total


# --- Research -----------------------------------------------------------------

func lab_ready() -> bool:
	return module_active("lab")


func research_block_reason(id: String) -> String:
	var node: Dictionary = Config.tech_nodes.get(id, {})
	if node.is_empty():
		return "Unknown technology"
	if researched.has(id):
		return "Already researched"
	if not research.is_empty():
		return "Another research is running"
	for req in node.get("requires", []):
		if not researched.has(req):
			return "Requires " + str(Config.tech_nodes.get(req, {}).get("name", req))
	if not lab_ready():
		return "Install and enable the Research Lab module"
	if not has_cost(node.get("cost", {})):
		return "Missing resources"
	return ""


func start_research(id: String) -> bool:
	var reason := research_block_reason(id)
	if reason != "":
		notify(reason, "warning")
		return false
	var node: Dictionary = Config.tech_nodes[id]
	pay_cost(node.get("cost", {}))
	research = {"id": id, "remaining": float(node.get("time", 60)), "total": float(node.get("time", 60))}
	notify("Research started: " + str(node.get("name", id)))
	research_changed.emit()
	return true


func cancel_research() -> void:
	if research.is_empty():
		return
	# Cancelling refunds half of the cost (rounded down) to discourage spam.
	var node: Dictionary = Config.tech_nodes.get(research["id"], {})
	var cost: Dictionary = node.get("cost", {})
	for k in cost.keys():
		add_item(k, int(cost[k]) / 2, true)
	research = {}
	research_changed.emit()


## Called every frame while the game runs. Research only advances while the
## Lab module is installed, enabled and the ship has energy.
func process_research(delta: float) -> void:
	if research.is_empty() or not lab_ready() or energy <= 0.0:
		return
	research["remaining"] = float(research["remaining"]) - delta
	if research["remaining"] <= 0.0:
		complete_research(str(research["id"]))


func complete_research(id: String) -> void:
	var node: Dictionary = Config.tech_nodes.get(id, {})
	researched[id] = true
	research = {}
	var unlocks: Dictionary = node.get("unlocks", {})
	for m in unlocks.get("modules", []):
		modules_unlocked[str(m)] = true
	for r in unlocks.get("recipes", []):
		recipes_unlocked[str(r)] = true
	recalc_stats()
	stat_add("techs_researched")
	notify("Research complete: " + str(node.get("name", id)), "good")
	research_changed.emit()


# --- Discoveries, names, codex -----------------------------------------------

func is_discovered(id: String) -> bool:
	return discoveries.has(id)


func add_discovery(entry: Dictionary) -> void:
	var id := str(entry["id"])
	if discoveries.has(id):
		return
	entry["time"] = play_time
	entry["date"] = Time.get_datetime_string_from_system(false, true)
	if not entry.has("notes"):
		entry["notes"] = []
	discoveries[id] = entry
	var kind := str(entry.get("kind", ""))
	stat_add("discoveries")
	match kind:
		"star": stat_add("systems_discovered")
		"planet": stat_add("planets_discovered")
		"moon": stat_add("moons_discovered")
	var value := float(Config.dict("discovery.data_value").get(kind, 5))
	data_points += int(value * Config.fval("discovery.discovery_data_fraction", 0.5))
	discovered.emit(entry)


func name_of(id: String, fallback: String) -> String:
	return str(names.get(id, fallback))


func set_name_for(id: String, new_name: String, by_player := true) -> void:
	new_name = new_name.strip_edges()
	if new_name == "":
		return
	names[id] = new_name
	if discoveries.has(id):
		discoveries[id]["name"] = new_name
	if by_player:
		stat_add("bodies_named")
	names_changed.emit()


func add_log(title: String, text: String) -> void:
	logs.append({"title": title, "text": text, "date": Time.get_datetime_string_from_system(false, true)})


func set_target(t: Dictionary) -> void:
	target = t


# --- Statistics and achievements ---------------------------------------------

func stat_add(key: String, amount: float = 1.0) -> void:
	stats[key] = float(stats.get(key, 0.0)) + amount
	_check_achievements(key)


func stat_max(key: String, value: float) -> void:
	if value > float(stats.get(key, 0.0)):
		stats[key] = value
		_check_achievements(key)


func _check_achievements(key: String) -> void:
	for a in Config.get_v("achievements", []):
		if str(a.get("stat", "")) != key or achievements.has(a["id"]):
			continue
		if float(stats.get(key, 0.0)) >= float(a.get("threshold", 0)):
			achievements[a["id"]] = Time.get_datetime_string_from_system(false, true)
			notify("Achievement unlocked: " + str(a.get("name", a["id"])), "achievement")
			achievement_unlocked.emit(a)


# --- Save / load --------------------------------------------------------------

func to_dict() -> Dictionary:
	get_tree().call_group("save_hooks", "_before_save")
	return {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"seed": world_seed, "difficulty": difficulty,
		"ship": ship_state,
		"fuel": fuel, "energy": energy, "shield": shield, "hull": hull,
		"credits": credits, "data_points": data_points,
		"cargo": cargo, "researched": researched.keys(), "research": research,
		"modules_unlocked": modules_unlocked.keys(), "modules_installed": modules_installed,
		"modules_enabled": modules_enabled, "recipes_unlocked": recipes_unlocked.keys(),
		"discoveries": discoveries, "names": names, "removed": removed.keys(),
		"visited": visited.keys(), "scanned": scanned.keys(), "logs": logs,
		"stats": stats, "achievements": achievements, "target": target,
		"active_rescue": active_rescue, "play_time": play_time,
	}


func from_dict(d: Dictionary) -> void:
	d = migrate(d)
	_reset()
	world_seed = int(d.get("seed", 0))
	difficulty = str(d.get("difficulty", "standard"))
	ship_state = d.get("ship", {})
	credits = int(d.get("credits", 0))
	data_points = int(d.get("data_points", 0))
	for k in d.get("cargo", {}).keys():
		cargo[k] = int(d["cargo"][k])
	for k in d.get("researched", []): researched[k] = true
	research = d.get("research", {})
	for k in d.get("modules_unlocked", []): modules_unlocked[k] = true
	modules_installed = Array(d.get("modules_installed", []))
	modules_enabled = d.get("modules_enabled", {})
	for k in d.get("recipes_unlocked", []): recipes_unlocked[k] = true
	discoveries = d.get("discoveries", {})
	names = d.get("names", {})
	for k in d.get("removed", []): removed[k] = true
	for k in d.get("visited", []): visited[k] = true
	for k in d.get("scanned", []): scanned[k] = true
	logs = d.get("logs", [])
	stats = d.get("stats", {})
	achievements = d.get("achievements", {})
	target = d.get("target", {})
	active_rescue = d.get("active_rescue", {})
	play_time = float(d.get("play_time", 0.0))
	recalc_stats()
	fuel = float(d.get("fuel", stat("fuel_capacity")))
	energy = float(d.get("energy", stat("energy_capacity")))
	shield = float(d.get("shield", stat("shield_max")))
	hull = float(d.get("hull", stat("hull_max")))
	active = true
	cargo_changed.emit()
	credits_changed.emit()
	research_changed.emit()


## Upgrades older save dictionaries to SAVE_VERSION. Add a step per version bump.
func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	# Example for the future:
	# if v < 2: d["new_field"] = default; v = 2
	d["version"] = v
	return d


func slot_path(slot: String) -> String:
	return SAVE_DIR + slot + ".json"


func save_game(slot: String) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		notify("Save failed: " + error_string(FileAccess.get_open_error()), "danger")
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	current_slot = slot
	return true


func read_save(slot: String) -> Dictionary:
	if not FileAccess.file_exists(slot_path(slot)):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot_path(slot)))
	return parsed if parsed is Dictionary else {}


func load_game(slot: String) -> bool:
	var d := read_save(slot)
	if d.is_empty():
		notify("Save slot is empty or unreadable.", "danger")
		return false
	from_dict(d)
	current_slot = slot
	return true


func delete_save(slot: String) -> void:
	if FileAccess.file_exists(slot_path(slot)):
		DirAccess.remove_absolute(slot_path(slot))


## Returns [{slot, saved_at, seed, difficulty, play_time}] newest first.
func list_saves() -> Array:
	var out: Array = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var slot := file.get_basename()
		var d := read_save(slot)
		if d.is_empty():
			continue
		out.append({"slot": slot, "saved_at": str(d.get("saved_at", "")), "seed": int(d.get("seed", 0)),
			"difficulty": str(d.get("difficulty", "")), "play_time": float(d.get("play_time", 0.0))})
	out.sort_custom(func(a, b): return a["saved_at"] > b["saved_at"])
	return out


func manual_slot_name(index: int) -> String:
	return "slot_%d" % index


## Ironman runs keep a single save named after the seed.
func autosave_slot() -> String:
	return "ironman_%d" % world_seed if is_permadeath() else AUTOSAVE_SLOT


# --- Settings -----------------------------------------------------------------

func load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if parsed is Dictionary:
			for k in parsed.keys():
				settings[k] = parsed[k]
	apply_settings()


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))
	apply_settings()


func apply_settings() -> void:
	Engine.time_scale = clampf(float(settings.get("game_speed", 1.0)), 0.25, 2.0)
	if DisplayServer.get_name() != "headless":
		var want_full := bool(settings.get("fullscreen", false))
		var mode := DisplayServer.window_get_mode()
		var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		if want_full != is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_full else DisplayServer.WINDOW_MODE_WINDOWED)


## Colour from the active palette (normal or colour-blind safe).
func pal(key: String, alpha := 1.0) -> Color:
	var set_name := "colorblind" if settings.get("colorblind", false) else "normal"
	return Config.color(Config.dict("palette." + set_name).get(key, [1, 1, 1]), alpha)
