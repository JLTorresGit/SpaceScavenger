extends Control
## In-flight HUD: resource gauges with consumption rates, speedometer and
## velocity-vs-heading indicator, radar, cargo quick view, target panel,
## low-resource warnings with suggestions, status flags, toasts, scan results
## and an off-screen target marker.

const RadarScript := preload("res://scripts/ui/radar.gd")

var ship
var universe
var camera: Camera2D

var gauges := {}
var vector_view
var radar
var cargo_weight: Gauge
var cargo_volume: Gauge
var credits_label: Label
var target_label: Label
var status_label: Label
var warning_panel: PanelContainer
var warning_label: Label
var hint_label: Label
var research_label: Label
var research_bar: ProgressBar
var rescue_label: Label
var toasts: VBoxContainer
var scan_panel: PanelContainer
var scan_label: Label
var overlay
var ui_scale := 1.0
var suggestion := {}
var _scan_t := 0.0
var _slow_t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay = TargetOverlay.new()
	overlay.hud = self
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_build_left()
	_build_right()
	_build_center()
	_build_bottom()
	Game.toast.connect(_on_toast)


func _hud_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "HudPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _place(c: Control, preset: int, margin := 12) -> void:
	add_child(c)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, margin)
	match preset:
		Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT:
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	match preset:
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM:
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _build_left() -> void:
	var p := _hud_panel()
	var v := UiKit.vbox(4)
	p.add_child(v)
	for key in ["fuel", "energy", "shield", "hull"]:
		var g := Gauge.new()
		g.title = key.capitalize()
		g.key = key
		v.add_child(g)
		gauges[key] = g
	vector_view = VectorView.new()
	vector_view.hud = self
	v.add_child(vector_view)
	_place(p, Control.PRESET_TOP_LEFT)


func _build_right() -> void:
	var p := _hud_panel()
	var v := UiKit.vbox(4)
	p.add_child(v)
	radar = RadarScript.new()
	v.add_child(radar)
	cargo_weight = Gauge.new()
	cargo_weight.title = "Weight"
	cargo_weight.key = "cargo_weight"
	cargo_weight.custom_minimum_size.x = 248
	cargo_volume = Gauge.new()
	cargo_volume.title = "Volume"
	cargo_volume.key = "cargo_volume"
	cargo_volume.custom_minimum_size.x = 248
	v.add_child(cargo_weight)
	v.add_child(cargo_volume)
	credits_label = UiKit.label("", 14)
	v.add_child(credits_label)
	_place(p, Control.PRESET_TOP_RIGHT)


func _build_center() -> void:
	var p := _hud_panel()
	var v := UiKit.vbox(2)
	p.add_child(v)
	target_label = UiKit.label("", 15)
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label = UiKit.label("", 14, Color(0.7, 0.85, 1.0))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(target_label)
	v.add_child(status_label)
	p.custom_minimum_size.x = 520
	_place(p, Control.PRESET_CENTER_TOP)
	warning_panel = PanelContainer.new()
	warning_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.04, 0.03, 0.85)
	sb.border_color = Color(1, 0.35, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	warning_panel.add_theme_stylebox_override("panel", sb)
	warning_label = UiKit.label("", 17, Color(1, 0.85, 0.75))
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_panel.add_child(warning_label)
	_place(warning_panel, Control.PRESET_CENTER_TOP, 84)
	warning_panel.visible = false
	toasts = UiKit.vbox(4)
	toasts.custom_minimum_size.x = 380
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(toasts, Control.PRESET_CENTER_RIGHT)
	toasts.offset_top = -40


func _build_bottom() -> void:
	var p := _hud_panel()
	var v := UiKit.vbox(3)
	p.add_child(v)
	research_label = UiKit.label("", 14)
	research_bar = UiKit.bar(0, 1, Color(0.6, 0.5, 1.0), 300)
	rescue_label = UiKit.label("", 14, Color(1, 0.6, 0.5))
	v.add_child(research_label)
	v.add_child(research_bar)
	v.add_child(rescue_label)
	_place(p, Control.PRESET_BOTTOM_LEFT)
	var hp := _hud_panel()
	hint_label = UiKit.label("", 16)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.add_child(hint_label)
	_place(hp, Control.PRESET_CENTER_BOTTOM)
	scan_panel = _hud_panel()
	scan_label = UiKit.label("", 14)
	scan_panel.add_child(scan_label)
	scan_panel.custom_minimum_size.x = 380
	_place(scan_panel, Control.PRESET_BOTTOM_RIGHT)
	scan_panel.visible = false


func show_scan(info: Dictionary) -> void:
	var lines: PackedStringArray = ["SCAN: " + str(info.get("title", "?"))]
	for l in info.get("lines", []):
		lines.append("  " + str(l))
	if info.get("new", false):
		lines.append("  +%d discovery data" % int(info.get("data", 0)))
	scan_label.text = "\n".join(lines)
	scan_panel.visible = true
	_scan_t = 9.0


func _on_toast(text: String, kind: String) -> void:
	var p := PanelContainer.new()
	p.theme_type_variation = "HudPanel"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := Game.pal("text")
	match kind:
		"good": col = Game.pal("good")
		"warning": col = Game.pal("warning")
		"danger": col = Game.pal("danger")
		"achievement": col = Color(1.0, 0.85, 0.3)
	var l := UiKit.wrap_label(text, 15, col)
	l.custom_minimum_size.x = 360
	p.add_child(l)
	p.set_meta("t", 5.0)
	toasts.add_child(p)
	while toasts.get_child_count() > 6:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()


func _process(delta: float) -> void:
	if ship == null:
		return
	radar.ship = ship
	radar.universe = universe
	for k in gauges.keys():
		gauges[k].queue_redraw()
	vector_view.queue_redraw()
	overlay.queue_redraw()
	cargo_weight.queue_redraw()
	cargo_volume.queue_redraw()
	for t in toasts.get_children():
		var left: float = float(t.get_meta("t", 0.0)) - delta
		t.set_meta("t", left)
		t.modulate.a = clampf(left, 0.0, 1.0)
		if left <= 0.0:
			t.queue_free()
	if _scan_t > 0.0:
		_scan_t -= delta
		if _scan_t <= 0.0:
			scan_panel.visible = false
	_slow_t -= delta
	if _slow_t <= 0.0:
		_slow_t = 0.2
		_update_texts()


func _update_texts() -> void:
	credits_label.text = "Credits %d   ·   Data %d pts" % [Game.credits, Game.data_points]
	# Target panel
	if Game.target.is_empty():
		target_label.text = "No target — click the map to set a waypoint"
	else:
		var d: float = ship.target_distance()
		var closing: float = ship.velocity.dot((ship.target_local_pos() - ship.position).normalized()) if d > 0 else 0.0
		var eta := d / closing if closing > 5.0 else -1.0
		target_label.text = "Target: %s   %s   ETA %s   ~%.0f fuel%s" % [Game.target.get("name", "?"), UiKit.fmt_dist(d),
			UiKit.fmt_time(eta), ship.estimate_trip_fuel(d), "   [AUTOPILOT]" if ship.autopilot else ""]
	# Status flags
	var flags: PackedStringArray = []
	if ship.warp: flags.append("WARP")
	if ship.autopilot: flags.append("AUTOPILOT")
	if Game.engine_mode == "energy": flags.append("ION DRIVE")
	if Game.engine_mode == "fuel" and Game.fuel <= 0.0: flags.append("NO FUEL — RCS ONLY")
	if ship.in_nebula: flags.append("NEBULA: sensors reduced")
	if ship.in_storm: flags.append("ION STORM: energy drain")
	if ship.heat_level > 0.05: flags.append("HEAT %d%%" % int(ship.heat_level * 100))
	if ship.scoop_level > 0.05: flags.append("SCOOPING")
	if universe.last_well_depth > 0.3 and Game.stat("gravity_assist_efficiency") > 0: flags.append("GRAVITY ASSIST")
	if not ship.sensors_online: flags.append("SENSORS OFFLINE")
	if ship.life_support_failing: flags.append("LIFE SUPPORT FAILING")
	if ship.scanning > 0.0: flags.append("SCANNING…")
	status_label.text = "   ·   ".join(flags)
	# Bottom hint
	var hint: String = ship.hint
	if hint == "" and Game.settings.get("show_hints", true):
		hint = "%s help  ·  WASD fly  ·  Click waypoint  ·  Space laser  ·  F tractor  ·  Shift warp" % Config.binding_text("help")
	hint_label.text = hint
	# Research
	if Game.research.is_empty():
		research_label.text = "Research: idle (%s)" % Config.binding_text("tech")
		research_bar.visible = false
	else:
		var node: Dictionary = Config.tech_nodes.get(Game.research["id"], {})
		var total := float(Game.research["total"])
		var remaining := float(Game.research["remaining"])
		var why := ""
		if not Game.lab_ready():
			why = "  (PAUSED: Lab disabled)"
		elif Game.energy <= 0.0:
			why = "  (PAUSED: no energy)"
		research_label.text = "Research: %s — %s left%s" % [node.get("name", "?"), UiKit.fmt_time(remaining), why]
		research_bar.visible = true
		research_bar.max_value = total
		research_bar.value = total - remaining
	if Game.active_rescue.is_empty():
		rescue_label.text = ""
	else:
		rescue_label.text = "RESCUE: reach %s in %s" % [Game.active_rescue.get("name", "pod"), UiKit.fmt_time(float(Game.active_rescue["remaining"]))]
	_update_warnings()


## Low fuel / energy / hull warnings with the nearest helpful place.
func _update_warnings() -> void:
	var w := Config.dict("warnings")
	var checks := [
		["hull", Game.hull / maxf(Game.stat("hull_max"), 1.0), float(w.get("hull_low", 0.35))],
		["fuel", Game.fuel / maxf(Game.stat("fuel_capacity"), 1.0), float(w.get("fuel_low", 0.25))],
		["energy", Game.energy / maxf(Game.stat("energy_capacity"), 1.0), float(w.get("energy_low", 0.2))],
	]
	if Game.engine_mode == "energy":
		checks.remove_at(1)
	var worst: Array = []
	for c in checks:
		if c[1] < c[2] and (worst.is_empty() or c[1] / c[2] < worst[1] / worst[2]):
			worst = c
	if worst.is_empty() or ship.dead:
		warning_panel.visible = false
		suggestion = {}
		return
	var res: String = worst[0]
	var critical: bool = worst[1] < float(w.get("critical", 0.1))
	suggestion = _nearest_help(res)
	var text := "%s %s %d%%" % ["CRITICAL" if critical else "LOW", res.to_upper(), int(worst[1] * 100)]
	var item_hint := ""
	var restore_key: String = {"fuel": "refuel", "energy": "recharge", "hull": "repair"}[res]
	for k in Game.cargo.keys():
		if str(Config.item(k).get("use", {}).get("restore", "")) == res:
			item_hint = " — press %s to use %s" % [Config.binding_text(restore_key), Config.item_name(k)]
			break
	text += item_hint
	if not suggestion.is_empty():
		text += "\nNearest help: %s (%s) — press %s to set course" % [suggestion["name"], UiKit.fmt_dist(suggestion["distance"]), Config.binding_text("accept_suggestion")]
	else:
		text += "\nNo known help nearby — explore, scan derelicts, or mine asteroids."
	warning_label.text = text
	warning_panel.visible = true
	warning_panel.modulate.a = 1.0 if critical else 0.9


func _nearest_help(res: String) -> Dictionary:
	var kinds: Array = Config.dict("warnings.suggest_kinds").get(res, [])
	var best := {}
	var best_d := INF
	var candidates: Array = []
	for e in universe.entities.values():
		if is_instance_valid(e) and kinds.has(e.kind):
			candidates.append({"id": e.id, "name": e.display_name(), "kind": e.kind, "wx": e.wx(), "wy": e.wy(), "radius": e.radius})
	for e in Game.discoveries.values():
		if kinds.has(e["kind"]):
			candidates.append(e)
	for c in candidates:
		if c["kind"] == "star" and Game.stat("scoop_rate") <= 0.0:
			continue
		var d: float = universe.to_local_pos(float(c["wx"]), float(c["wy"])).distance_to(ship.position)
		if d < best_d:
			best_d = d
			best = {"id": c["id"], "name": c.get("name", "?"), "kind": c["kind"], "wx": c["wx"], "wy": c["wy"], "radius": c.get("radius", 0.0), "distance": d}
	return best


# --- Inner widgets ----------------------------------------------------------------

class Gauge extends Control:
	var title := ""
	var key := ""

	func _init() -> void:
		custom_minimum_size = Vector2(300, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _values() -> Array:
		var hud = get_parent()
		while hud and not hud.has_method("show_scan"):
			hud = hud.get_parent()
		var rate := 0.0
		match key:
			"fuel":
				if hud and hud.ship: rate = hud.ship.rate_fuel
				return [Game.fuel, Game.stat("fuel_capacity"), Game.pal("fuel"), rate]
			"energy":
				if hud and hud.ship: rate = hud.ship.rate_energy
				return [Game.energy, Game.stat("energy_capacity"), Game.pal("energy"), rate]
			"shield":
				return [Game.shield, Game.stat("shield_max"), Game.pal("shield"), 0.0]
			"hull":
				return [Game.hull, Game.stat("hull_max"), Game.pal("hull"), 0.0]
			"cargo_weight":
				return [Game.cargo_weight(), Game.stat("cargo_max_weight"), Color(0.8, 0.7, 0.5), 0.0]
			"cargo_volume":
				return [Game.cargo_volume(), Game.stat("cargo_max_volume"), Color(0.7, 0.6, 0.9), 0.0]
		return [0.0, 1.0, Color.WHITE, 0.0]

	func _draw() -> void:
		var v := _values()
		var value: float = v[0]
		var max_v: float = maxf(v[1], 0.001)
		var col: Color = v[2]
		var font := get_theme_default_font()
		var label_w := 64.0
		draw_string(font, Vector2(0, 17), title, HORIZONTAL_ALIGNMENT_LEFT, label_w, 14, Color(0.75, 0.85, 1.0))
		var bar := Rect2(label_w, 4, size.x - label_w, 16)
		draw_rect(bar, Color(0.05, 0.08, 0.14))
		var frac := clampf(value / max_v, 0.0, 1.0)
		var fill := col
		if key in ["fuel", "energy", "hull"] and frac < 0.25:
			fill = col.lerp(Game.pal("danger"), 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), fill)
		draw_rect(bar, Color(0.3, 0.5, 0.75, 0.6), false, 1.0)
		var txt := "%d / %d" % [int(round(value)), int(round(max_v))]
		var rate: float = v[3]
		if absf(rate) > 0.01:
			txt += "  (%+.2f/s)" % rate
		draw_string(font, bar.position + Vector2(6, 13), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.95))


class VectorView extends Control:
	var hud

	func _init() -> void:
		custom_minimum_size = Vector2(300, 96)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if hud == null or hud.ship == null:
			return
		var ship = hud.ship
		var c := Vector2(46, 48)
		var r := 40.0
		draw_circle(c, r, Color(0.03, 0.07, 0.12))
		draw_arc(c, r, 0, TAU, 32, Color(0.3, 0.6, 0.9, 0.5), 1.0, true)
		var f := Vector2.from_angle(ship.heading)
		draw_line(c, c + f * r * 0.9, Color(1, 1, 1, 0.9), 2.0)
		var v: Vector2 = ship.velocity
		var max_v: float = Game.stat("warp_max_speed") if ship.warp else Game.stat("max_speed")
		if v.length() > 1.0:
			var tip := c + v.normalized() * r * clampf(v.length() / maxf(max_v, 1.0), 0.15, 1.0)
			draw_line(c, tip, Game.pal("good"), 3.0)
			draw_circle(tip, 3.5, Game.pal("good"))
		var font := get_theme_default_font()
		var speed := v.length()
		draw_string(font, Vector2(100, 24), "%d u/s" % int(speed), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1))
		var drift := rad_to_deg(absf(wrapf(v.angle() - ship.heading, -PI, PI))) if speed > 1.0 else 0.0
		draw_string(font, Vector2(100, 46), "Drift %d°   Max %d" % [int(drift), int(max_v)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.8, 0.95))
		draw_string(font, Vector2(100, 66), "White: heading  ·  Green: velocity", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.55, 0.65, 0.8))
		var pos_txt := "X %s  Y %s" % [UiKit.fmt_dist(hud.universe.world_x(ship.position)), UiKit.fmt_dist(hud.universe.world_y(ship.position))]
		draw_string(font, Vector2(100, 86), pos_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.65, 0.8))


class TargetOverlay extends Control:
	var hud

	func _draw() -> void:
		if hud == null or hud.ship == null or hud.camera == null:
			return
		var tp: Variant = hud.ship.target_local_pos()
		if tp == null:
			return
		var xf: Transform2D = hud.get_viewport().get_canvas_transform()
		var scale_: float = hud.ui_scale
		var screen: Vector2 = (xf * (tp as Vector2)) / scale_
		var rect := Rect2(Vector2(40, 40), size - Vector2(80, 80))
		var col := Game.pal("accent")
		if rect.has_point(screen):
			draw_arc(screen, 16, 0, TAU, 24, col, 2.0, true)
			draw_line(screen + Vector2(-24, 0), screen + Vector2(-12, 0), col, 2.0)
			draw_line(screen + Vector2(24, 0), screen + Vector2(12, 0), col, 2.0)
			draw_string(get_theme_default_font(), screen + Vector2(20, -18), str(Game.target.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		else:
			var center := size * 0.5
			var dir := (screen - center).normalized()
			var t := INF
			if absf(dir.x) > 0.001:
				t = minf(t, (rect.size.x * 0.5) / absf(dir.x))
			if absf(dir.y) > 0.001:
				t = minf(t, (rect.size.y * 0.5) / absf(dir.y))
			var p := center + dir * t
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([p + dir * 14, p - dir * 6 + side * 9, p - dir * 6 - side * 9]), col)
			var d: float = hud.ship.target_distance()
			draw_string(get_theme_default_font(), p - dir * 34 - Vector2(30, 0), UiKit.fmt_dist(d), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
