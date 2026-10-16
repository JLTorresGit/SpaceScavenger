extends Node
## Loads the single tuning file (config/game_config.json) and the tech tree
## (config/tech_tree.json), merges optional mod overrides from user://mods/,
## and builds the InputMap from the configured bindings.

signal reloaded

const GAME_CONFIG_PATH := "config/game_config.json"
const TECH_TREE_PATH := "config/tech_tree.json"
const MOD_DIR := "user://mods/"

var data: Dictionary = {}
var tech: Dictionary = {}
var tech_nodes: Dictionary = {}   # id -> node dictionary
var load_errors: PackedStringArray = []


func _ready() -> void:
	reload()


func reload() -> void:
	load_errors.clear()
	data = _load_json(_resolve(GAME_CONFIG_PATH))
	tech = _load_json(_resolve(TECH_TREE_PATH))
	var mod_cfg := _load_json(MOD_DIR + "game_config.json", true)
	if not mod_cfg.is_empty():
		deep_merge(data, mod_cfg)
	var mod_tech := _load_json(MOD_DIR + "tech_tree.json", true)
	if not mod_tech.is_empty():
		_merge_tech(mod_tech)
	tech_nodes.clear()
	for n in tech.get("nodes", []):
		tech_nodes[str(n["id"])] = n
	apply_input_bindings()
	reloaded.emit()


## Exported builds read a config folder placed next to the executable first,
## so the files stay editable without re-exporting.
func _resolve(rel: String) -> String:
	if not OS.has_feature("editor"):
		var external := OS.get_executable_path().get_base_dir().path_join(rel)
		if FileAccess.file_exists(external):
			return external
	return "res://" + rel


func _load_json(path: String, optional := false) -> Dictionary:
	if not FileAccess.file_exists(path):
		if not optional:
			load_errors.append("Missing config file: " + path)
			push_error("Missing config file: " + path)
		return {}
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		var msg := "%s line %d: %s" % [path, json.get_error_line(), json.get_error_message()]
		load_errors.append(msg)
		push_error(msg)
		return {}
	return json.data if json.data is Dictionary else {}


static func deep_merge(base: Dictionary, over: Dictionary) -> void:
	for k in over.keys():
		if base.has(k) and base[k] is Dictionary and over[k] is Dictionary:
			deep_merge(base[k], over[k])
		else:
			base[k] = over[k]


func _merge_tech(over: Dictionary) -> void:
	for list_name in ["branches", "nodes"]:
		if not over.has(list_name):
			continue
		var list: Array = tech.get(list_name, [])
		for entry in over[list_name]:
			var replaced := false
			for i in list.size():
				if list[i]["id"] == entry["id"]:
					list[i] = entry
					replaced = true
					break
			if not replaced:
				list.append(entry)
		tech[list_name] = list


# --- Accessors --------------------------------------------------------------

## Reads a value by dotted path, e.g. get_v("ship.thrust").
func get_v(path: String, default: Variant = null) -> Variant:
	var cur: Variant = data
	for part in path.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return default
	return cur


func fval(path: String, default := 0.0) -> float:
	return float(get_v(path, default))


func ival(path: String, default := 0) -> int:
	return int(get_v(path, default))


func dict(path: String) -> Dictionary:
	var v: Variant = get_v(path, {})
	return v if v is Dictionary else {}


func item(id: String) -> Dictionary:
	return dict("items." + id)


func item_name(id: String) -> String:
	return str(item(id).get("name", id.capitalize()))


func color(arr: Variant, alpha := 1.0) -> Color:
	if arr is Array and arr.size() >= 3:
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), alpha)
	return Color(1, 1, 1, alpha)


static func rand_range(rng: RandomNumberGenerator, arr: Variant) -> float:
	if arr is Array and arr.size() >= 2:
		return rng.randf_range(float(arr[0]), float(arr[1]))
	return float(arr)


static func rand_int(rng: RandomNumberGenerator, arr: Variant) -> int:
	if arr is Array and arr.size() >= 2:
		return rng.randi_range(int(arr[0]), int(arr[1]))
	return int(arr)


## Picks a key from a {key: weight} dictionary.
static func weighted_pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k in weights.keys():
		total += float(weights[k] if not (weights[k] is Dictionary) else weights[k].get("weight", 1.0))
	var roll := rng.randf() * total
	for k in weights.keys():
		roll -= float(weights[k] if not (weights[k] is Dictionary) else weights[k].get("weight", 1.0))
		if roll <= 0.0:
			return str(k)
	return str(weights.keys().back())


# --- Input bindings ---------------------------------------------------------

func apply_input_bindings() -> void:
	var bindings: Dictionary = data.get("input_bindings", {})
	for action in bindings.keys():
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.35)
		for spec in bindings[action]:
			var ev := _event_from_spec(str(spec))
			if ev:
				InputMap.action_add_event(action, ev)


func _event_from_spec(spec: String) -> InputEvent:
	var mouse_buttons := {
		"MouseLeft": MOUSE_BUTTON_LEFT, "MouseRight": MOUSE_BUTTON_RIGHT, "MouseMiddle": MOUSE_BUTTON_MIDDLE,
		"WheelUp": MOUSE_BUTTON_WHEEL_UP, "WheelDown": MOUSE_BUTTON_WHEEL_DOWN,
	}
	if mouse_buttons.has(spec):
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse_buttons[spec]
		return mb
	if spec.begins_with("JoyButton:"):
		var jb := InputEventJoypadButton.new()
		jb.button_index = int(spec.get_slice(":", 1))
		return jb
	if spec.begins_with("JoyAxis:"):
		var axis_spec := spec.get_slice(":", 1)
		var jm := InputEventJoypadMotion.new()
		jm.axis = int(axis_spec.left(axis_spec.length() - 1))
		jm.axis_value = -1.0 if axis_spec.ends_with("-") else 1.0
		return jm
	var code := OS.find_keycode_from_string(spec)
	if code == KEY_NONE:
		push_warning("Unknown key in input_bindings: " + spec)
		return null
	var key := InputEventKey.new()
	key.keycode = code
	return key


## Human-readable key list for an action (first keyboard/mouse binding).
func binding_text(action: String) -> String:
	var specs: Array = dict("input_bindings").get(action, [])
	var shown: PackedStringArray = []
	for s in specs:
		if not str(s).begins_with("Joy"):
			shown.append(str(s))
	return " / ".join(shown) if not shown.is_empty() else "-"
