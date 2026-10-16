extends Node
## Root of the game. Builds the world (universe, ship, camera, starfield), the
## HUD and windows; routes input; handles pausing, saving, death and reloads.
## Run with `-- --autotest=<dir>` to play a scripted session and save screenshots.

const UniverseScript := preload("res://scripts/world/universe.gd")
const ShipScript := preload("res://scripts/ship/ship.gd")
const CameraScript := preload("res://scripts/world/camera_rig.gd")
const StarfieldScript := preload("res://scripts/world/starfield.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const MainMenuScript := preload("res://scripts/ui/main_menu.gd")
const MapWindowScript := preload("res://scripts/ui/map_window.gd")

const WINDOW_KEYS := {"map": "map", "codex": "codex", "tech": "tech", "cargo": "cargo", "modules": "modules", "stats": "stats", "help": "help"}

var world: Node2D
var universe
var ship
var camera
var starfield_layer: CanvasLayer
var starfield
var ui_layer: CanvasLayer
var ui_root: Control
var hud
var main_menu
var windows := {}
var current_window = null
var naming_queue: Array = []
var photo_mode := false
var autosave_t := 0.0
var autotest_dir := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().title = "Space Scavenger"
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	ui_root = Control.new()
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UiKit.build_theme()
	ui_layer.add_child(ui_root)
	hud = HudScript.new()
	hud.visible = false
	ui_root.add_child(hud)
	main_menu = MainMenuScript.new()
	main_menu.main = self
	ui_root.add_child(main_menu)
	main_menu.refresh()
	Game.discovered.connect(_on_discovered)
	Config.reloaded.connect(func(): Game.recalc_stats())
	apply_ui_scale()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autotest"):
			autotest_dir = arg.get_slice("=", 1) if arg.contains("=") else "user://autotest"
			_run_autotest.call_deferred()


func _process(delta: float) -> void:
	var s := float(Game.settings.get("ui_scale", 1.0))
	ui_root.size = get_viewport().get_visible_rect().size / s
	if not Game.active or ship == null:
		return
	if current_window == null and not naming_queue.is_empty() and not ship.dead and not photo_mode:
		var entry: Dictionary = naming_queue.pop_front()
		var dlg = _window("naming")
		dlg.entry = entry
		open_window("naming")
	if not get_tree().paused and not ship.dead:
		autosave_t += delta
		var cfg := Config.dict("autosave")
		if autosave_t >= float(cfg.get("interval_sec", 120)):
			var hull_ok := Game.hull >= Game.stat("hull_max") * float(cfg.get("min_hull_fraction", 0.3))
			if hull_ok and ship.since_damage > float(cfg.get("quiet_time_sec", 5)) and ship.heat_level <= 0.0:
				autosave_t = 0.0
				save_slot(Game.autosave_slot(), true)


func apply_ui_scale() -> void:
	var s := float(Game.settings.get("ui_scale", 1.0))
	ui_layer.scale = Vector2(s, s)
	hud.ui_scale = s


# --- Game lifecycle ------------------------------------------------------------------

func start_new_game(seed_value: int, difficulty: String) -> void:
	Game.new_game(seed_value, difficulty)
	_build_world()
	universe.teleport(0.0, 0.0)
	universe.flush_spawns()
	ship.restore_from_state()
	camera.snap()
	Game.set_target({"id": "home_station", "name": "Haven Prime", "kind": "station", "wx": 2600.0, "wy": 1800.0, "radius": 110.0})
	Game.notify("Welcome aboard. Haven Prime station is nearby — click on the map or press %s for help." % Config.binding_text("help"))
	save_slot(Game.autosave_slot(), true)


func load_slot(slot: String) -> void:
	if not Game.load_game(slot):
		return
	_close_all_windows()
	_build_world()
	universe.teleport(float(Game.ship_state.get("wx", 0.0)), float(Game.ship_state.get("wy", 0.0)))
	universe.flush_spawns()
	ship.restore_from_state()
	camera.snap()
	Game.notify("Loaded " + slot, "good")


func save_slot(slot: String, quiet := false) -> void:
	if ship and ship.dead:
		return
	if Game.save_game(slot) and not quiet:
		Game.notify("Game saved (%s)." % slot, "good")


func to_main_menu(save_first: bool) -> void:
	if save_first and Game.active and ship and not ship.dead:
		save_slot(Game.current_slot if Game.current_slot != "" else Game.autosave_slot(), true)
	_close_all_windows()
	_destroy_world()
	Game.active = false
	get_tree().paused = false
	hud.visible = false
	main_menu.visible = true
	main_menu.refresh()


func quit_game() -> void:
	if Game.active and ship and not ship.dead:
		save_slot(Game.current_slot if Game.current_slot != "" else Game.autosave_slot(), true)
	get_tree().quit()


func _build_world() -> void:
	_destroy_world()
	get_tree().paused = false
	starfield_layer = CanvasLayer.new()
	starfield_layer.layer = -10
	add_child(starfield_layer)
	starfield = StarfieldScript.new()
	starfield_layer.add_child(starfield)
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	universe = UniverseScript.new()
	world.add_child(universe)
	ship = ShipScript.new()
	ship.universe = universe
	universe.ship = ship
	universe.add_child(ship)
	camera = CameraScript.new()
	camera.ship = ship
	world.add_child(camera)
	camera.make_current()
	starfield.camera = camera
	starfield.ship = ship
	universe.origin_shifted.connect(camera.shift)
	universe.teleported.connect(camera.snap)
	ship.destroyed.connect(_on_ship_destroyed)
	ship.docked.connect(_on_docked)
	ship.scan_finished.connect(func(info): hud.show_scan(info))
	hud.ship = ship
	hud.universe = universe
	hud.camera = camera
	hud.visible = true
	main_menu.visible = false
	naming_queue.clear()
	photo_mode = false
	autosave_t = 0.0


func _destroy_world() -> void:
	if world:
		world.queue_free()
		world = null
	if starfield_layer:
		starfield_layer.queue_free()
		starfield_layer = null
	universe = null
	ship = null
	camera = null
	hud.ship = null


# --- Windows -----------------------------------------------------------------------

func _window(name: String):
	if windows.has(name):
		return windows[name]
	var w
	match name:
		"pause": w = SimpleWindows.PauseMenu.new()
		"save":
			w = SimpleWindows.SaveLoadWindow.new()
			w.mode = "save"
		"load":
			w = SimpleWindows.SaveLoadWindow.new()
			w.mode = "load"
		"settings": w = SimpleWindows.SettingsWindow.new()
		"help": w = SimpleWindows.HelpWindow.new()
		"naming": w = SimpleWindows.NamingDialog.new()
		"message": w = SimpleWindows.MessageDialog.new()
		"stats": w = SimpleWindows.StatsWindow.new()
		"codex": w = GameWindows.CodexWindow.new()
		"tech": w = GameWindows.TechWindow.new()
		"cargo": w = GameWindows.CargoWindow.new()
		"modules": w = GameWindows.ModulesWindow.new()
		"station": w = GameWindows.StationWindow.new()
		"map": w = MapWindowScript.new()
	w.main = self
	w.closed.connect(_on_window_closed.bind(w))
	ui_root.add_child(w)
	windows[name] = w
	return w


func open_window(name: String) -> void:
	var w = _window(name)
	if current_window and current_window != w:
		var prev = current_window
		current_window = null
		prev.visible = false
	current_window = w
	if Game.active:
		get_tree().paused = true
	w.open()


func _close_all_windows() -> void:
	for w in windows.values():
		w.visible = false
	current_window = null


func _on_window_closed(w) -> void:
	if current_window == w:
		current_window = null
	get_viewport().gui_release_focus()
	if current_window == null and Game.active and not photo_mode:
		get_tree().paused = false


func _toggle_window(name: String) -> void:
	if current_window and windows.get(name) == current_window:
		current_window.close()
	else:
		open_window(name)


# --- Input ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not Game.active or ship == null:
		return
	if photo_mode:
		if event.is_action_pressed("photo_mode") or event.is_action_pressed("pause"):
			_set_photo_mode(false)
		elif event.is_action_pressed("zoom_in"):
			camera.zoom_by(1)
		elif event.is_action_pressed("zoom_out"):
			camera.zoom_by(-1)
		return
	if current_window != null:
		for action in WINDOW_KEYS.keys():
			if event.is_action_pressed(action) and windows.get(WINDOW_KEYS[action]) == current_window:
				current_window.close()
				get_viewport().set_input_as_handled()
				return
		return
	if ship.dead:
		return
	if event.is_action_pressed("pause"):
		open_window("pause")
	elif event.is_action_pressed("zoom_in"):
		camera.zoom_by(1)
	elif event.is_action_pressed("zoom_out"):
		camera.zoom_by(-1)
	elif event.is_action_pressed("set_waypoint"):
		_set_waypoint_at_mouse()
	elif event.is_action_pressed("clear_waypoint"):
		Game.set_target({})
		ship.autopilot = false
		Game.notify("Target cleared.")
	elif event.is_action_pressed("accept_suggestion"):
		if hud.suggestion.is_empty():
			Game.notify("No suggestion right now.")
		else:
			set_target_entry(hud.suggestion)
	elif event.is_action_pressed("photo_mode"):
		_set_photo_mode(true)
	elif event.is_action_pressed("quicksave"):
		if Game.is_permadeath():
			save_slot(Game.autosave_slot())
		else:
			save_slot("quicksave")
	elif event.is_action_pressed("quickload"):
		if not Game.is_permadeath():
			load_slot("quicksave")
	elif event.is_action_pressed("reload_config"):
		Config.reload()
		Game.notify("Config files reloaded." if Config.load_errors.is_empty() else "Config errors: " + Config.load_errors[0], "good" if Config.load_errors.is_empty() else "danger")
	else:
		for action in WINDOW_KEYS.keys():
			if event.is_action_pressed(action):
				_toggle_window(WINDOW_KEYS[action])
				get_viewport().set_input_as_handled()
				return


func _set_waypoint_at_mouse() -> void:
	var p: Vector2 = universe.get_global_mouse_position()
	var e = universe.entity_at(p, 20.0 / camera.zoom.x)
	if e:
		set_target_entry({"id": e.id, "name": e.display_name(), "kind": e.kind, "wx": e.wx(), "wy": e.wy(), "radius": e.radius})
	else:
		set_target_entry({"id": "", "name": "Waypoint", "kind": "waypoint", "wx": universe.world_x(p), "wy": universe.world_y(p), "radius": 0.0})


func set_target_entry(entry: Dictionary) -> void:
	Game.set_target({"id": str(entry.get("id", "")), "name": str(entry.get("name", "Target")), "kind": str(entry.get("kind", "")),
		"wx": float(entry["wx"]), "wy": float(entry["wy"]), "radius": float(entry.get("radius", 0.0))})
	if ship:
		ship.engage_autopilot()
	Game.notify("Course set: %s — autopilot engaged (WASD to take over)." % entry.get("name", "target"))


func quick_travel(entry: Dictionary) -> void:
	_close_all_windows()
	get_tree().paused = false
	if ship.quick_travel(entry):
		universe.flush_spawns()


func jettison(item_id: String, n: int) -> void:
	if n <= 0 or not Game.remove_item(item_id, n):
		return
	var back: Vector2 = -Vector2.from_angle(ship.heading)
	var p = universe.spawn_pickup(item_id, n, ship.position + back * 40.0, ship.velocity + back * 120.0)
	if p:
		p.cooldown = 4.0
	Game.notify("Jettisoned %d %s." % [n, Config.item_name(item_id)])


func _set_photo_mode(on: bool) -> void:
	photo_mode = on
	camera.photo_mode = on
	hud.visible = not on
	get_tree().paused = on
	if on:
		Game.notify("Photo mode")


# --- Events ---------------------------------------------------------------------------

func _on_discovered(entry: Dictionary) -> void:
	Game.notify("Discovered: %s (%s)" % [entry["name"], str(entry["kind"]).replace("_", " ")], "good")
	if entry["kind"] in ["star", "planet", "moon"] and Game.settings.get("ask_names", true) and autotest_dir == "":
		naming_queue.append(entry)


func _on_docked(station) -> void:
	var w = _window("station")
	w.station = station
	open_window("station")
	save_slot(Game.autosave_slot(), true)
	Game.notify("Docked at %s. Progress saved." % station.display_name(), "good")


func _on_ship_destroyed() -> void:
	Game.notify("HULL BREACH — ship destroyed!", "danger")
	await get_tree().create_timer(2.5).timeout
	if ship == null:
		return
	var dlg = _window("message")
	current_window = dlg
	get_tree().paused = true
	if Game.is_permadeath():
		Game.delete_save(Game.autosave_slot())
		dlg.show_message("Ship Lost", "Your vessel was destroyed. This Ironman run is over.\nDistance travelled: %s · Discoveries: %d" % [
			UiKit.fmt_dist(float(Game.stats.get("distance_traveled", 0))), Game.discoveries.size()], [["Main Menu", func(): to_main_menu(false)]])
	else:
		dlg.show_message("Ship Destroyed", "Your vessel was destroyed. Reload your last save to continue the expedition.", [
			["Reload last save", _reload_after_death], ["Main Menu", func(): to_main_menu(false)]])


func _reload_after_death() -> void:
	var deaths := float(Game.stats.get("deaths", 1))
	var slot := Game.current_slot if Game.current_slot != "" else Game.autosave_slot()
	if Game.read_save(slot).is_empty():
		slot = Game.autosave_slot()
	if Game.read_save(slot).is_empty():
		start_new_game(Game.world_seed, Game.difficulty)
	else:
		load_slot(slot)
	Game.stats["deaths"] = maxf(deaths, float(Game.stats.get("deaths", 0)))


# --- Automated test session (screenshots) ---------------------------------------------

func _run_autotest() -> void:
	print("[autotest] writing screenshots to ", autotest_dir)
	DirAccess.make_dir_recursive_absolute(autotest_dir)
	await _shot("00_menu")
	start_new_game(12345, "standard")
	await _wait(1.0)
	await _shot("01_start")
	Input.action_press("thrust")
	await _wait(1.5)
	Input.action_release("thrust")
	await _shot("02_thrust")
	ship.engage_autopilot()
	await _wait(10.0)
	await _shot("03_autopilot")
	# Mine the nearest asteroid / derelict with the laser logic directly.
	var rock = null
	for e in universe.solids.values():
		if e.minable and (rock == null or e.position.distance_to(ship.position) < rock.position.distance_to(ship.position)):
			rock = e
	ship.autopilot = false
	ship.velocity = Vector2.ZERO
	if rock:
		universe.teleport(rock.wx() + rock.radius + 60.0, rock.wy())
		universe.flush_spawns()
		await _wait(0.3)
		# Aim the real mouse at the nearest minable object and fire the laser.
		var victim = null
		for e in universe.solids.values():
			if e.minable and (victim == null or e.position.distance_to(ship.position) < victim.position.distance_to(ship.position)):
				victim = e
		if victim:
			get_viewport().warp_mouse(get_viewport().get_canvas_transform() * victim.position)
			Input.action_press("laser")
			var t := 0.0
			var shot_taken := false
			while is_instance_valid(victim) and t < 15.0:
				if t > 0.5 and not shot_taken:
					shot_taken = true
					await _shot("04a_laser")
				await _wait(0.1)
				t += 0.1
			Input.action_release("laser")
			print("[autotest] laser destroyed target: ", not is_instance_valid(victim), " in %.1fs" % t)
		await _wait(0.3)
		await _shot("04_salvage_drops")
		Input.action_press("tractor")
		await _wait(2.0)
		Input.action_release("tractor")
		await _shot("05_tractor")
	# Fly near the home star to show heat, planets and gravity.
	# Warp stress test: stream chunks at top speed and watch the frame rate.
	ship.autopilot = false
	ship.heading = 0.0
	ship.invulnerable = true
	Input.action_press("warp")
	Input.action_press("thrust")
	var min_fps := 1000.0
	for i in 50:
		await _wait(0.1)
		if i > 10:
			min_fps = minf(min_fps, Engine.get_frames_per_second())
	await _shot("05b_warp")
	Input.action_release("thrust")
	Input.action_release("warp")
	ship.invulnerable = false
	print("[autotest] warp: speed=%d u/s, x=%d, min fps=%d, entities=%d" % [int(ship.velocity.length()), int(universe.world_x(ship.position)), int(min_fps), universe.entities.size()])
	var star := Generator.system_at(Game.world_seed, 0, 0)
	universe.teleport(float(star["wx"]) + float(star["entities"][0]["heat_radius"]) * 1.3, float(star["wy"]))
	universe.flush_spawns()
	ship.velocity = Vector2.ZERO
	ship.autopilot = false
	camera.target_zoom = 0.2
	await _wait(1.5)
	await _shot("06_star_system")
	camera.target_zoom = 0.8
	for e in universe.entities.values():
		if e.kind == "planet":
			Game.set_target({"id": e.id, "name": e.display_name(), "kind": e.kind, "wx": e.wx(), "wy": e.wy(), "radius": e.radius})
			universe.teleport(e.wx() + e.radius + 400.0, e.wy())
			universe.flush_spawns()
			ship.velocity = Vector2.ZERO
			break
	await _wait(0.5)
	ship.start_scan()
	await _wait(2.0)
	await _shot("07_scan")
	for w in ["cargo", "tech", "modules", "codex", "map", "stats", "help", "pause"]:
		open_window(w)
		await _wait(0.3)
		await _shot("10_window_" + w)
		current_window.close()
	var station = universe.entities.get("home_station")
	if station == null:
		universe.teleport(2600.0 + 300.0, 1800.0)
		universe.flush_spawns()
		station = universe.entities.get("home_station")
	if station:
		_on_docked(station)
		await _wait(0.3)
		await _shot("11_station")
		current_window.close()
	Game.fuel = Game.stat("fuel_capacity") * 0.12
	await _wait(1.0)
	await _shot("12_low_fuel_warning")
	save_slot("autotest")
	var before := Game.to_dict()
	load_slot("autotest")
	await _wait(0.5)
	var after := Game.to_dict()
	var same: bool = before["cargo"] == after["cargo"] and before["discoveries"].size() == after["discoveries"].size()
	print("[autotest] save/load round trip ok: ", same)
	_set_photo_mode(true)
	await _wait(0.3)
	await _shot("13_photo_mode")
	_set_photo_mode(false)
	Game.hull = 0.0
	await _wait(3.2)
	await _shot("14_destroyed_dialog")
	current_window.close()
	_reload_after_death()
	await _wait(0.5)
	await _shot("15_reloaded")
	print("[autotest] after death reload: hull=%.1f deaths=%d dead=%s" % [Game.hull, int(Game.stats.get("deaths", 0)), str(ship.dead)])
	print("[autotest] discoveries=%d entities=%d cargo=%s fuel=%.1f energy=%.1f hull=%.1f" % [
		Game.discoveries.size(), universe.entities.size(), str(Game.cargo), Game.fuel, Game.energy, Game.hull])
	print("[autotest] done")
	get_tree().quit()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := autotest_dir.path_join(name + ".png")
	img.save_png(path)
	print("[autotest] shot ", path)
