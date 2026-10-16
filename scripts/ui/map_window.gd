extends WindowPanel
## Galaxy map: zoomable / pannable view of explored chunks and every discovered
## object, with filters, target selection and quick travel.

var view: MapView
var info: VBoxContainer
var filters := {}
var selected := {}


func _init() -> void:
	window_title = "Galaxy Map"
	window_size = Vector2(1400, 780)


func _build() -> void:
	var h := UiKit.hbox(10)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view = MapView.new()
	view.window = self
	view.custom_minimum_size = Vector2(1060, 690)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(view)
	var side := UiKit.vbox(6)
	side.custom_minimum_size.x = 290
	side.add_child(UiKit.label("Show", 16, Color(0.6, 0.85, 1.0)))
	for k in GameWindows.KIND_FILTERS.keys():
		if k == "All":
			continue
		var c := CheckBox.new()
		c.text = k
		c.button_pressed = true
		c.focus_mode = Control.FOCUS_NONE
		c.toggled.connect(func(_on): view.queue_redraw())
		filters[k] = c
		side.add_child(c)
	side.add_child(UiKit.button("Centre on ship", func(): view.center_on_ship()))
	side.add_child(HSeparator.new())
	info = UiKit.vbox(6)
	side.add_child(info)
	side.add_child(UiKit.spacer())
	side.add_child(UiKit.wrap_label("Drag to pan · wheel to zoom · click an object to select it. Dashed circle: quick-travel range.", 13, Color(0.55, 0.65, 0.8)))
	h.add_child(side)
	body.add_child(h)


func refresh() -> void:
	view.rebuild_cache()
	view.center_on_ship()
	_show_info()


func kind_visible(kind: String, subtype: String) -> bool:
	if kind == "derelict" and subtype == "ghost_ship":
		kind = "ghost_ship"
	for k in filters.keys():
		if GameWindows.KIND_FILTERS[k].has(kind):
			return filters[k].button_pressed
	return true


func select(e: Dictionary) -> void:
	selected = e
	_show_info()
	view.queue_redraw()


func _show_info() -> void:
	UiKit.clear(info)
	if selected.is_empty():
		info.add_child(UiKit.label("%d discoveries" % Game.discoveries.size(), 15))
		info.add_child(UiKit.label("%d sectors explored" % Game.visited.size(), 15))
		return
	info.add_child(UiKit.wrap_label(str(selected["name"]), 18, Color(0.6, 0.85, 1.0)))
	info.add_child(UiKit.label(str(selected["kind"]).replace("_", " ").capitalize(), 14))
	var cost: Dictionary = main.ship.quick_travel_cost(float(selected["wx"]), float(selected["wy"]))
	info.add_child(UiKit.label("Distance " + UiKit.fmt_dist(cost["distance"]), 14))
	info.add_child(UiKit.button("Set as target", func(): main.set_target_entry(selected)))
	var reason: String = main.ship.quick_travel_block_reason(selected)
	var b := UiKit.button("Quick travel (%.1f fuel)" % cost["fuel"], func(): main.quick_travel(selected))
	b.disabled = reason != ""
	info.add_child(b)
	if reason != "":
		info.add_child(UiKit.wrap_label(reason, 13, Game.pal("warning")))


class MapView extends Control:
	var window
	var center_wx := 0.0
	var center_wy := 0.0
	var units_per_px := 120.0
	var visited_cells: Array = []
	var dragging := false
	var drag_moved := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true

	func rebuild_cache() -> void:
		visited_cells.clear()
		for k in Game.visited.keys():
			var p: PackedStringArray = str(k).split(",")
			visited_cells.append(Vector2i(int(p[0]), int(p[1])))

	func center_on_ship() -> void:
		var u = window.main.universe
		var s = window.main.ship
		center_wx = u.world_x(s.position)
		center_wy = u.world_y(s.position)
		queue_redraw()

	func to_screen(wx: float, wy: float) -> Vector2:
		return size * 0.5 + Vector2(wx - center_wx, wy - center_wy) / units_per_px

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				_zoom_at(mb.position, 1.0 / 1.2)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				_zoom_at(mb.position, 1.2)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					dragging = true
					drag_moved = 0.0
				else:
					dragging = false
					if drag_moved < 6.0:
						_click(mb.position)
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			var mm := event as InputEventMouseMotion
			center_wx -= mm.relative.x * units_per_px
			center_wy -= mm.relative.y * units_per_px
			drag_moved += mm.relative.length()
			queue_redraw()
			accept_event()

	func _zoom_at(p: Vector2, factor: float) -> void:
		var before_x := center_wx + (p.x - size.x * 0.5) * units_per_px
		var before_y := center_wy + (p.y - size.y * 0.5) * units_per_px
		units_per_px = clampf(units_per_px * factor, 2.0, 20000.0)
		center_wx = before_x - (p.x - size.x * 0.5) * units_per_px
		center_wy = before_y - (p.y - size.y * 0.5) * units_per_px
		queue_redraw()

	func _click(p: Vector2) -> void:
		var best := {}
		var best_d := 14.0
		for e in Game.discoveries.values():
			if not window.kind_visible(str(e["kind"]), str(e.get("subtype", ""))):
				continue
			var d := to_screen(float(e["wx"]), float(e["wy"])).distance_to(p)
			if d < best_d:
				best_d = d
				best = e
		window.select(best)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.04))
		var font := get_theme_default_font()
		var chunk := Config.fval("world.chunk_size", 4000)
		var cell_px := chunk / units_per_px
		if cell_px >= 1.0:
			for c in visited_cells:
				var p := to_screen(c.x * chunk, c.y * chunk)
				if p.x > -cell_px and p.y > -cell_px and p.x < size.x and p.y < size.y:
					draw_rect(Rect2(p, Vector2(cell_px, cell_px)), Color(0.15, 0.3, 0.5, 0.25))
		# Grid every 100k units
		var step := 100000.0
		var x0 := floorf((center_wx - size.x * 0.5 * units_per_px) / step) * step
		var y0 := floorf((center_wy - size.y * 0.5 * units_per_px) / step) * step
		var gx := x0
		while gx < center_wx + size.x * 0.5 * units_per_px:
			var sx := to_screen(gx, 0).x
			draw_line(Vector2(sx, 0), Vector2(sx, size.y), Color(0.3, 0.5, 0.8, 0.12))
			gx += step
		var gy := y0
		while gy < center_wy + size.y * 0.5 * units_per_px:
			var sy := to_screen(0, gy).y
			draw_line(Vector2(0, sy), Vector2(size.x, sy), Color(0.3, 0.5, 0.8, 0.12))
			gy += step
		var origin := to_screen(0, 0)
		draw_string(font, origin + Vector2(6, -6), "Origin", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.6, 0.8))
		draw_circle(origin, 3, Color(0.5, 0.6, 0.8))
		# Discoveries
		for e in Game.discoveries.values():
			if not window.kind_visible(str(e["kind"]), str(e.get("subtype", ""))):
				continue
			var p := to_screen(float(e["wx"]), float(e["wy"]))
			if p.x < -20 or p.y < -20 or p.x > size.x + 20 or p.y > size.y + 20:
				continue
			var col := Config.color(Config.dict("radar_colors").get(e["kind"], [0.8, 0.8, 0.8]))
			var r := 3.0
			match str(e["kind"]):
				"star": r = 6.0
				"planet": r = 4.0
				"moon": r = 2.0
			if e["kind"] == "station":
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col)
			elif e["kind"] in ["nebula", "field", "black_hole"]:
				draw_arc(p, maxf(4.0, float(e.get("radius", 0)) / units_per_px), 0, TAU, 24, col, 1.5, true)
			else:
				draw_circle(p, r, col)
			if units_per_px < 60.0 or e["kind"] == "star" or e["kind"] == "station":
				draw_string(font, p + Vector2(8, 4), str(e["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col, 0.85))
		# Ship, target, quick-travel range
		var u = window.main.universe
		var s = window.main.ship
		var sp := to_screen(u.world_x(s.position), u.world_y(s.position))
		var qr := Game.stat("quick_travel_max_distance") / units_per_px
		for i in 64:
			if i % 2 == 0:
				draw_arc(sp, qr, TAU * i / 64.0, TAU * (i + 1) / 64.0, 4, Color(0.4, 1.0, 0.7, 0.35), 1.5)
		if not Game.target.is_empty():
			var tp := to_screen(float(Game.target["wx"]), float(Game.target["wy"]))
			draw_line(sp, tp, Color(Game.pal("accent"), 0.6), 1.5)
			draw_arc(tp, 9, 0, TAU, 16, Game.pal("accent"), 2.0)
		var f := Vector2.from_angle(s.heading)
		var side := Vector2(-f.y, f.x)
		draw_colored_polygon(PackedVector2Array([sp + f * 10, sp - f * 6 + side * 6, sp - f * 6 - side * 6]), Color(1, 1, 1))
		if not window.selected.is_empty():
			var p := to_screen(float(window.selected["wx"]), float(window.selected["wy"]))
			draw_arc(p, 12, 0, TAU, 24, Color(1, 1, 0.5), 2.0)
		draw_string(font, Vector2(10, size.y - 10), "Scale: %s per 100 px" % UiKit.fmt_dist(units_per_px * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.7, 0.85))
