class_name SimpleWindows
extends RefCounted
## Small windows: pause menu, save/load, settings, help, naming dialog,
## message dialog, statistics & achievements.


class PauseMenu extends WindowPanel:
	var seed_label: Label

	func _init() -> void:
		window_title = "Paused"
		window_size = Vector2(420, 0)

	func _build() -> void:
		seed_label = UiKit.label("", 14, Color(0.6, 0.75, 0.9))
		body.add_child(seed_label)
		body.add_child(UiKit.button("Resume", close))
		body.add_child(UiKit.button("Save Game", func(): main.open_window("save")))
		body.add_child(UiKit.button("Load Game", func(): main.open_window("load")))
		body.add_child(UiKit.button("Statistics & Achievements", func(): main.open_window("stats")))
		body.add_child(UiKit.button("Settings", func(): main.open_window("settings")))
		body.add_child(UiKit.button("Help / Controls", func(): main.open_window("help")))
		body.add_child(UiKit.button("Save & Main Menu", func(): main.to_main_menu(true)))
		body.add_child(UiKit.button("Save & Quit", func(): main.quit_game()))

	func refresh() -> void:
		seed_label.text = "Seed %d · %s · Played %s" % [Game.world_seed, Config.dict("difficulty." + Game.difficulty).get("name", Game.difficulty), UiKit.fmt_time(Game.play_time)]


class SaveLoadWindow extends WindowPanel:
	var mode := "load"
	var list: VBoxContainer

	func _init() -> void:
		window_title = "Load Game"
		window_size = Vector2(640, 420)

	func _build() -> void:
		list = UiKit.vbox(6)
		body.add_child(UiKit.scroll(list, 340))

	func refresh() -> void:
		title_label.text = "Save Game" if mode == "save" else "Load Game"
		UiKit.clear(list)
		var saves := {}
		for s in Game.list_saves():
			saves[s["slot"]] = s
		if mode == "save":
			if Game.is_permadeath():
				list.add_child(UiKit.wrap_label("Ironman runs keep a single save that is written automatically.", 15, Game.pal("warning")))
				list.add_child(UiKit.button("Save now (Ironman slot)", func(): _save(Game.autosave_slot())))
				return
			for i in range(1, 6):
				var slot := Game.manual_slot_name(i)
				var info: String = _describe(saves.get(slot, {}))
				list.add_child(_row("Slot %d   %s" % [i, info], "Save", func(): _save(slot)))
		else:
			if saves.is_empty():
				list.add_child(UiKit.label("No saves yet."))
			for s in Game.list_saves():
				var slot: String = s["slot"]
				var r := _row("%s   %s" % [slot, _describe(s)], "Load", func(): main.load_slot(slot))
				r.add_child(UiKit.button("Delete", func(): _delete(slot)))
				list.add_child(r)

	func _save(slot: String) -> void:
		main.save_slot(slot)
		refresh()

	func _delete(slot: String) -> void:
		Game.delete_save(slot)
		refresh()

	func _describe(s: Dictionary) -> String:
		if s.is_empty():
			return "(empty)"
		return "%s · seed %d · %s · %s" % [s["saved_at"].replace("T", " "), s["seed"], s["difficulty"], UiKit.fmt_time(s["play_time"])]

	func _row(text: String, action: String, cb: Callable) -> HBoxContainer:
		var h := UiKit.hbox()
		var l := UiKit.label(text, 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		h.add_child(l)
		h.add_child(UiKit.button(action, cb, 80))
		return h


class SettingsWindow extends WindowPanel:
	var ui_scale: HSlider
	var speed: HSlider
	var speed_label: Label
	var scale_label: Label
	var colorblind: CheckBox
	var ask_names: CheckBox
	var hints: CheckBox
	var fullscreen: CheckBox

	func _init() -> void:
		window_title = "Settings"
		window_size = Vector2(520, 0)

	func _build() -> void:
		scale_label = UiKit.label("")
		body.add_child(scale_label)
		ui_scale = HSlider.new()
		ui_scale.min_value = 0.75
		ui_scale.max_value = 1.75
		ui_scale.step = 0.05
		ui_scale.value_changed.connect(func(v): _set_setting("ui_scale", v))
		body.add_child(ui_scale)
		speed_label = UiKit.label("")
		body.add_child(speed_label)
		speed = HSlider.new()
		speed.min_value = 0.5
		speed.max_value = 1.5
		speed.step = 0.05
		speed.value_changed.connect(func(v): _set_setting("game_speed", v))
		body.add_child(speed)
		colorblind = _check("Colour-blind safe palette", "colorblind")
		ask_names = _check("Ask to name new stars, planets and moons", "ask_names")
		hints = _check("Show control hints", "show_hints")
		fullscreen = _check("Fullscreen", "fullscreen")
		body.add_child(UiKit.wrap_label("Key bindings are defined in config/game_config.json (input_bindings).", 13, Color(0.55, 0.65, 0.8)))

	func _check(text: String, key: String) -> CheckBox:
		var c := CheckBox.new()
		c.text = text
		c.focus_mode = Control.FOCUS_NONE
		c.toggled.connect(func(on): _set_setting(key, on))
		body.add_child(c)
		return c

	func refresh() -> void:
		ui_scale.set_value_no_signal(float(Game.settings["ui_scale"]))
		speed.set_value_no_signal(float(Game.settings["game_speed"]))
		colorblind.set_pressed_no_signal(bool(Game.settings["colorblind"]))
		ask_names.set_pressed_no_signal(bool(Game.settings["ask_names"]))
		hints.set_pressed_no_signal(bool(Game.settings["show_hints"]))
		fullscreen.set_pressed_no_signal(bool(Game.settings["fullscreen"]))
		_labels()

	func _labels() -> void:
		scale_label.text = "UI scale: %.2f" % float(Game.settings["ui_scale"])
		speed_label.text = "Game speed: %.2f×" % float(Game.settings["game_speed"])

	func _set_setting(key: String, value: Variant) -> void:
		Game.settings[key] = value
		_apply()

	func _apply() -> void:
		Game.save_settings()
		_labels()
		main.apply_ui_scale()


class HelpWindow extends WindowPanel:
	func _init() -> void:
		window_title = "Help & Controls"
		window_size = Vector2(760, 560)

	func _build() -> void:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		var rows := [
			["thrust", "Main thrust"], ["retro", "Retro thrust"], ["rotate_left", "Rotate left"], ["rotate_right", "Rotate right"],
			["strafe_left", "RCS strafe left"], ["strafe_right", "RCS strafe right"], ["warp", "Warp (hold)"],
			["set_waypoint", "Set waypoint / target + autopilot"], ["clear_waypoint", "Clear target"],
			["laser", "Salvage laser (aim with mouse)"], ["tractor", "Tractor beam (short range)"], ["scan", "Deep scan"],
			["drones", "Launch drones"], ["interact", "Dock at station"], ["accept_suggestion", "Set course to suggested help"],
			["refuel", "Use fuel cell"], ["recharge", "Use battery unit"], ["repair", "Repair hull"],
			["zoom_in", "Zoom in"], ["zoom_out", "Zoom out"], ["map", "Galaxy map"], ["codex", "Codex / discoveries"],
			["tech", "Technology tree"], ["cargo", "Cargo & crafting"], ["modules", "Ship modules"], ["stats", "Statistics"],
			["photo_mode", "Photo mode"], ["quicksave", "Quick save"], ["quickload", "Quick load"], ["reload_config", "Reload config files"],
			["pause", "Pause menu / close window"],
		]
		for r in rows:
			grid.add_child(UiKit.label(Config.binding_text(r[0]), 15, Color(0.6, 0.85, 1.0)))
			grid.add_child(UiKit.label(r[1], 15))
		var v := UiKit.vbox(10)
		v.add_child(grid)
		v.add_child(UiKit.wrap_label("Tips: fuel drives the engines, energy runs everything else. Small drops are collected by flying close; large drops need the tractor beam. Research needs the Lab module enabled. Warp disables the laser and tractor. Stars burn — watch the dashed thermal boundary.", 14, Color(0.7, 0.8, 0.95)))
		body.add_child(UiKit.scroll(v, 470))


class NamingDialog extends WindowPanel:
	var entry: Dictionary = {}
	var edit: LineEdit
	var info: Label
	var queue: Array = []

	func _init() -> void:
		window_title = "New Discovery"
		window_size = Vector2(520, 0)
		closable = false

	func _build() -> void:
		info = UiKit.wrap_label("", 16)
		body.add_child(info)
		edit = LineEdit.new()
		edit.max_length = 40
		edit.text_submitted.connect(func(_t): _accept())
		body.add_child(edit)
		var row := UiKit.hbox()
		row.add_child(UiKit.button("Random name", func(): edit.text = _random_name()))
		row.add_child(UiKit.spacer())
		row.add_child(UiKit.button("Keep catalogue name", func(): _finish(false)))
		row.add_child(UiKit.button("Accept", _accept))
		body.add_child(row)

	func refresh() -> void:
		info.text = "You discovered a %s.\nName it, or keep its catalogue designation." % str(entry.get("kind", "body"))
		edit.text = str(entry.get("name", ""))
		edit.grab_focus()
		edit.select_all()

	func _random_name() -> String:
		match str(entry.get("kind", "")):
			"star":
				return Naming.random_star_name()
			"planet":
				return Naming.planet_name(Naming.random_star_name(), randi() % 6)
			_:
				return Naming.moon_name(Naming.planet_name(Naming.random_star_name(), randi() % 6), randi() % 4)

	func _accept() -> void:
		_finish(edit.text.strip_edges() != "" and edit.text.strip_edges() != str(entry.get("name", "")))

	func _finish(renamed: bool) -> void:
		if renamed:
			Game.set_name_for(entry["id"], edit.text)
			Game.notify("Named: " + edit.text.strip_edges(), "good")
		close()


class MessageDialog extends WindowPanel:
	var message: Label
	var buttons: HBoxContainer

	func _init() -> void:
		window_title = "Message"
		window_size = Vector2(520, 0)
		closable = false

	func _build() -> void:
		message = UiKit.wrap_label("", 17)
		body.add_child(message)
		buttons = UiKit.hbox()
		body.add_child(buttons)

	func _run(cb: Callable) -> void:
		close()
		cb.call()

	func show_message(title: String, text: String, actions: Array) -> void:
		open()
		title_label.text = title
		message.text = text
		UiKit.clear(buttons)
		buttons.add_child(UiKit.spacer())
		for a in actions:
			var cb: Callable = a[1]
			buttons.add_child(UiKit.button(a[0], func(): _run(cb)))


class StatsWindow extends WindowPanel:
	var content: VBoxContainer

	func _init() -> void:
		window_title = "Statistics & Achievements"
		window_size = Vector2(720, 560)

	func _build() -> void:
		content = UiKit.vbox(4)
		body.add_child(UiKit.scroll(content, 480))

	func refresh() -> void:
		UiKit.clear(content)
		content.add_child(UiKit.label("Statistics", 20, Color(0.6, 0.85, 1.0)))
		var names := {
			"distance_traveled": "Distance travelled", "max_distance": "Farthest from origin", "play_time": "Time played",
			"systems_discovered": "Star systems discovered", "planets_discovered": "Planets discovered", "moons_discovered": "Moons discovered",
			"discoveries": "Objects discovered", "asteroids_mined": "Asteroids mined", "derelicts_salvaged": "Derelicts salvaged",
			"items_collected": "Items collected", "items_crafted": "Items crafted", "techs_researched": "Technologies researched",
			"credits_earned": "Credits earned", "scans": "Scans", "wormholes_used": "Wormholes used", "rescues": "Rescues",
			"bodies_named": "Bodies named", "quick_travels": "Quick travels", "fuel_burned": "Fuel burned", "deaths": "Ships lost",
		}
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 40)
		for k in names.keys():
			var v := float(Game.stats.get(k, 0.0))
			var txt := str(int(v))
			if k in ["distance_traveled", "max_distance"]:
				txt = UiKit.fmt_dist(v)
			elif k == "play_time":
				txt = UiKit.fmt_time(v)
			grid.add_child(UiKit.label(names[k], 15))
			grid.add_child(UiKit.label(txt, 15, Color(1, 1, 1)))
		content.add_child(grid)
		content.add_child(HSeparator.new())
		content.add_child(UiKit.label("Achievements (%d/%d)" % [Game.achievements.size(), Config.get_v("achievements", []).size()], 20, Color(0.6, 0.85, 1.0)))
		for a in Config.get_v("achievements", []):
			var got := Game.achievements.has(a["id"])
			var progress := float(Game.stats.get(a["stat"], 0.0))
			var text := "%s %s — %s" % ["★" if got else "☆", a["name"], a["description"]]
			if not got:
				text += "  (%d / %d)" % [int(progress), int(a["threshold"])]
			content.add_child(UiKit.label(text, 15, Color(1, 0.85, 0.35) if got else Color(0.6, 0.65, 0.75)))
