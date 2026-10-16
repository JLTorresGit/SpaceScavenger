extends Node
## Headless test suite. Run:
##   godot --headless --path . res://tests/tests.tscn
## Exit code 0 = all passed.

var failures := 0
var passes := 0


func _ready() -> void:
	_test_scripts_compile()
	_test_config()
	_test_determinism()
	_test_home_content()
	_test_naming()
	_test_stats_and_modules()
	_test_cargo_limits()
	_test_crafting()
	_test_research()
	_test_save_roundtrip()
	_test_tech_tree_integrity()
	print("\n%d passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		printerr("FAIL: " + what)


func _test_scripts_compile() -> void:
	var dirs := ["res://scripts/", "res://scripts/autoload/", "res://scripts/world/", "res://scripts/entities/", "res://scripts/ship/", "res://scripts/ui/"]
	for d in dirs:
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				var s: Script = load(d + f)
				check(s != null and s.can_instantiate() or (s != null and f in ["generator.gd", "naming.gd", "ui_kit.gd", "simple_windows.gd", "game_windows.gd"]), "script loads: " + d + f)


func _test_config() -> void:
	check(Config.load_errors.is_empty(), "config files parse without errors " + str(Config.load_errors))
	check(Config.fval("ship.thrust") > 0, "ship.thrust configured")
	check(Config.tech_nodes.size() >= 30, "tech tree has nodes (%d)" % Config.tech_nodes.size())
	check(InputMap.has_action("thrust") and InputMap.action_get_events("thrust").size() > 0, "input bindings applied")


func _test_determinism() -> void:
	var a := Generator.chunk_at(777, 3, -2)
	var b := Generator.chunk_at(777, 3, -2)
	check(JSON.stringify(a) == JSON.stringify(b), "chunk generation is deterministic")
	var c := Generator.chunk_at(778, 3, -2)
	check(JSON.stringify(a) != JSON.stringify(c) or a.is_empty(), "different seeds differ")
	var s1 := Generator.system_at(777, 1, 1)
	var s2 := Generator.system_at(777, 1, 1)
	check(JSON.stringify(s1) == JSON.stringify(s2), "system generation is deterministic")
	var far := Generator.chunk_at(777, 250000, -250000)
	check(far is Array, "far chunk generates")
	# Entity ids must be unique inside a chunk.
	var seen := {}
	var dup := false
	for x in range(-3, 4):
		for y in range(-3, 4):
			for e in Generator.chunk_at(99, x, y):
				if seen.has(e["id"]):
					dup = true
				seen[e["id"]] = true
	check(not dup, "entity ids are unique")


func _test_home_content() -> void:
	var home := Generator.system_at(4242, 0, 0)
	check(not home.is_empty(), "home system always exists")
	check(home["entities"][0]["kind"] == "star", "home system has a star first")
	var has_station := false
	for e in Generator.chunk_at(4242, 0, 0):
		if e["id"] == "home_station":
			has_station = true
	check(has_station, "home station is generated near the origin")
	var start_blocked := false
	for e in home["entities"]:
		var d := Vector2(float(e["wx"]), float(e["wy"])).length()
		if d < float(e.get("radius", 0)) + 500.0:
			start_blocked = true
	check(not start_blocked, "start position is clear of bodies")


func _test_naming() -> void:
	check(Naming.roman(4) == "IV" and Naming.roman(9) == "IX" and Naming.roman(14) == "XIV", "roman numerals")
	check(Naming.star_name(12) == Naming.star_name(12), "star names deterministic")
	check(Naming.planet_name("Tau Ceti", 0) == "Tau Ceti b", "planet suffix")
	check(Naming.moon_name("Tau Ceti b", 1) == "Tau Ceti b II", "moon suffix")


func _test_stats_and_modules() -> void:
	Game.new_game(1, "standard")
	var base := Game.stat("thrust")
	Game.researched["eng_thrusters_1"] = true
	Game.recalc_stats()
	check(is_equal_approx(Game.stat("thrust"), base * 1.15), "tech effect multiplies thrust")
	Game.researched["eng_ion_drive"] = true
	Game.recalc_stats()
	check(Game.engine_mode == "energy", "ion drive switches engine to energy")
	Game.new_game(1, "standard")
	check(Game.lab_ready(), "lab installed and enabled at start")
	Game.modules_unlocked["aux_fuel_tank"] = true
	var cap := Game.stat("fuel_capacity")
	check(Game.install_module("aux_fuel_tank"), "install module into free slot")
	check(Game.stat("fuel_capacity") > cap, "module effect applied")
	Game.modules_unlocked["cargo_expander"] = true
	check(not Game.install_module("cargo_expander"), "cannot exceed module slots")
	Game.set_module_enabled("aux_fuel_tank", false)
	check(is_equal_approx(Game.stat("fuel_capacity"), cap), "disabled module has no effect")


func _test_cargo_limits() -> void:
	Game.new_game(2, "standard")
	Game.cargo = {}
	var fit_iron := Game.space_for("iron")
	var expected := mini(floori(Game.stat("cargo_max_weight") / 2.0), floori(Game.stat("cargo_max_volume") / 1.0))
	check(fit_iron == expected, "space_for respects both weight and volume (%d vs %d)" % [fit_iron, expected])
	var added := Game.add_item("iron", 100000)
	check(added == fit_iron, "add_item clamps to capacity")
	check(Game.cargo_weight() <= Game.stat("cargo_max_weight") + 0.01, "weight limit holds")
	check(Game.cargo_volume() <= Game.stat("cargo_max_volume") + 0.01, "volume limit holds")
	Game.cargo = {}
	Game.cargo_changed.emit()


func _test_crafting() -> void:
	Game.new_game(3, "standard")
	Game.cargo = {"iron": 6, "scrap_alloy": 2}
	check(Game.recipe_block_reason("alloy_plate") == "", "alloy recipe available")
	check(Game.craft("alloy_plate"), "craft alloy plate")
	check(Game.count("alloy_plate") == 1 and Game.count("iron") == 3, "crafting consumes inputs and adds output")
	check(Game.recipe_block_reason("fuel_from_ice") != "", "locked recipe blocked until researched")


func _test_research() -> void:
	Game.new_game(4, "standard")
	Game.cargo = {"iron": 20, "electronics": 5}
	check(Game.start_research("pow_combustion"), "start research")
	check(Game.count("iron") == 12, "research cost paid up front")
	Game.set_module_enabled("lab", false)
	Game.process_research(1000.0)
	check(not Game.researched.has("pow_combustion"), "research paused while lab disabled")
	Game.set_module_enabled("lab", true)
	Game.process_research(1000.0)
	check(Game.researched.has("pow_combustion"), "research completes after its time")
	check(Game.research_block_reason("pow_converter").begins_with("Requires"), "prerequisites enforced")
	Game.uninstall_module("lab")
	Game.cargo = {"iron": 20, "scrap_alloy": 20}
	check(Game.research_block_reason("pow_tanks").contains("Lab"), "lab required to start research")


func _test_save_roundtrip() -> void:
	Game.new_game(5, "relaxed")
	Game.cargo = {"rare_ore": 3}
	Game.researched["sal_laser_1"] = true
	Game.removed["c1_1_a3"] = true
	Game.add_discovery({"id": "s0_0", "kind": "star", "name": "Test Star", "wx": 1.0, "wy": 2.0, "radius": 300.0})
	Game.set_name_for("s0_0", "Helios")
	Game.origin_x = 123456789.25
	Game.ship_state = {"wx": 1.0e9, "wy": -2.5e8, "vx": 10.0, "vy": 0.0, "rot": 1.0}
	var d := Game.to_dict()
	var text := JSON.stringify(d)
	var parsed: Dictionary = JSON.parse_string(text)
	Game.new_game(99, "standard")
	Game.from_dict(parsed)
	check(Game.world_seed == 5 and Game.difficulty == "relaxed", "seed & difficulty restored")
	check(Game.count("rare_ore") == 3, "cargo restored")
	check(Game.researched.has("sal_laser_1"), "research restored")
	check(Game.removed.has("c1_1_a3"), "delta removals restored")
	check(Game.name_of("s0_0", "") == "Helios", "names restored")
	check(is_equal_approx(float(Game.ship_state["wx"]), 1.0e9), "large world coordinates survive")


func _test_tech_tree_integrity() -> void:
	for id in Config.tech_nodes.keys():
		var n: Dictionary = Config.tech_nodes[id]
		for r in n.get("requires", []):
			check(Config.tech_nodes.has(r), "%s requires existing node %s" % [id, r])
		for k in n.get("cost", {}).keys():
			check(not Config.item(k).is_empty(), "%s cost item %s exists" % [id, k])
		for m in n.get("unlocks", {}).get("modules", []):
			check(not Config.dict("modules." + m).is_empty(), "%s unlocks existing module %s" % [id, m])
		for r in n.get("unlocks", {}).get("recipes", []):
			check(not Config.dict("recipes." + r).is_empty(), "%s unlocks existing recipe %s" % [id, r])
		for e in n.get("effects", []):
			check(Config.dict("ship").has(e["stat"]), "%s effect stat %s exists in ship config" % [id, e["stat"]])
	for rid in Config.dict("recipes").keys():
		var r := Config.dict("recipes." + rid)
		for k in r.get("inputs", {}).keys() + r.get("outputs", {}).keys():
			check(not Config.item(k).is_empty(), "recipe %s item %s exists" % [rid, k])
	for table in Config.dict("loot").keys():
		for e in Config.get_v("loot." + table, []):
			check(not Config.item(e["item"]).is_empty(), "loot %s item %s exists" % [table, e["item"]])
