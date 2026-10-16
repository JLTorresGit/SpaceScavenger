class_name UiKit
extends RefCounted
## Theme and small widget helpers so every screen is built in code with a
## consistent look.

static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	var panel := _box(Color(0.035, 0.05, 0.09, 0.97), Color(0.3, 0.6, 0.95, 0.55), 1, 8, 12)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	var hud_panel := _box(Color(0.02, 0.035, 0.07, 0.72), Color(0.3, 0.6, 0.95, 0.35), 1, 6, 8)
	t.set_type_variation("HudPanel", "PanelContainer")
	t.set_stylebox("panel", "HudPanel", hud_panel)
	t.set_stylebox("normal", "Button", _box(Color(0.08, 0.14, 0.24), Color(0.3, 0.55, 0.85, 0.7), 1, 5, 6))
	t.set_stylebox("hover", "Button", _box(Color(0.12, 0.22, 0.36), Color(0.45, 0.75, 1.0), 1, 5, 6))
	t.set_stylebox("pressed", "Button", _box(Color(0.18, 0.32, 0.5), Color(0.6, 0.85, 1.0), 1, 5, 6))
	t.set_stylebox("disabled", "Button", _box(Color(0.06, 0.08, 0.12), Color(0.2, 0.25, 0.35), 1, 5, 6))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), Color(0.6, 0.85, 1.0, 0.8), 1, 5, 6))
	t.set_color("font_color", "Button", Color(0.88, 0.94, 1.0))
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.5, 0.6))
	t.set_color("font_color", "Label", Color(0.86, 0.91, 1.0))
	t.set_stylebox("normal", "LineEdit", _box(Color(0.02, 0.04, 0.08), Color(0.3, 0.55, 0.85, 0.7), 1, 4, 6))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.02, 0.04, 0.08), Color(0.55, 0.85, 1.0), 1, 4, 6))
	t.set_stylebox("panel", "ItemList", _box(Color(0.02, 0.04, 0.08, 0.9), Color(0.25, 0.45, 0.7, 0.6), 1, 4, 4))
	t.set_stylebox("selected", "ItemList", _box(Color(0.15, 0.3, 0.5), Color(0, 0, 0, 0), 0, 3, 2))
	t.set_stylebox("selected_focus", "ItemList", _box(Color(0.18, 0.36, 0.6), Color(0, 0, 0, 0), 0, 3, 2))
	t.set_stylebox("background", "ProgressBar", _box(Color(0.05, 0.08, 0.14), Color(0.25, 0.4, 0.6, 0.6), 1, 3, 0))
	t.set_stylebox("fill", "ProgressBar", _box(Color(0.3, 0.75, 1.0), Color(0, 0, 0, 0), 0, 3, 0))
	t.set_stylebox("normal", "OptionButton", _box(Color(0.08, 0.14, 0.24), Color(0.3, 0.55, 0.85, 0.7), 1, 5, 6))
	t.set_stylebox("hover", "OptionButton", _box(Color(0.12, 0.22, 0.36), Color(0.45, 0.75, 1.0), 1, 5, 6))
	t.set_stylebox("panel", "TooltipPanel", _box(Color(0.03, 0.05, 0.1, 0.96), Color(0.4, 0.7, 1.0), 1, 4, 6))
	return t


static func _box(bg: Color, border: Color, bw: int, radius: int, margin: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(bw)
	b.set_corner_radius_all(radius)
	b.set_content_margin_all(margin)
	return b


static func label(text: String, size := 16, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if size != 16:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0:
		l.add_theme_color_override("font_color", color)
	return l


static func wrap_label(text: String, size := 16, color := Color(0, 0, 0, 0)) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func button(text: String, on_press: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.pressed.connect(on_press)
	return b


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func scroll(child: Control, min_h := 300.0) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.custom_minimum_size.y = min_h
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func bar(value: float, max_value: float, color: Color, min_w := 160.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = maxf(max_value, 0.001)
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(min_w, 12)
	var fill := _box(color, Color(0, 0, 0, 0), 0, 3, 0)
	p.add_theme_stylebox_override("fill", fill)
	return p


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func fmt_dist(d: float) -> String:
	if d >= 1000000.0:
		return "%.2f M u" % (d / 1000000.0)
	if d >= 10000.0:
		return "%.1f k u" % (d / 1000.0)
	return "%d u" % int(d)


static func fmt_time(sec: float) -> String:
	if sec < 0 or is_inf(sec) or is_nan(sec):
		return "--"
	var s := int(sec)
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm %02ds" % [s / 60, s % 60]
	return "%ds" % s
