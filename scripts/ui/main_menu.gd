extends Control
## Title screen: continue, new game (seed + difficulty), load, settings, quit.

var main
var new_game_box: VBoxContainer
var seed_edit: LineEdit
var diff_option: OptionButton
var diff_desc: Label
var continue_btn: Button
var t := 0.0
var stars: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 260:
		stars.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.5, 2.2), rng.randf_range(0.02, 0.2)])
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := UiKit.vbox(12)
	v.custom_minimum_size.x = 440
	center.add_child(v)
	var title := UiKit.label("SPACE SCAVENGER", 54, Color(0.65, 0.88, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UiKit.label("Explore. Salvage. Survive the infinite dark.", 18, Color(0.6, 0.7, 0.85))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(Control.new())
	continue_btn = UiKit.button("Continue", _on_continue)
	v.add_child(continue_btn)
	v.add_child(UiKit.button("New Game", func(): new_game_box.visible = not new_game_box.visible))
	new_game_box = _build_new_game()
	new_game_box.visible = false
	v.add_child(new_game_box)
	v.add_child(UiKit.button("Load Game", func(): main.open_window("load")))
	v.add_child(UiKit.button("Settings", func(): main.open_window("settings")))
	v.add_child(UiKit.button("Quit", func(): get_tree().quit()))
	if not Config.load_errors.is_empty():
		var err := UiKit.wrap_label("Config errors:\n" + "\n".join(Config.load_errors), 14, Color(1, 0.5, 0.4))
		v.add_child(err)
	var foot := UiKit.label("Tuning: config/game_config.json · Tech tree: config/tech_tree.json", 13, Color(0.45, 0.55, 0.7))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(foot)


func _build_new_game() -> VBoxContainer:
	var box := UiKit.vbox(8)
	var panel := PanelContainer.new()
	var inner := UiKit.vbox(8)
	panel.add_child(inner)
	box.add_child(panel)
	var row := UiKit.hbox()
	row.add_child(UiKit.label("Seed"))
	seed_edit = LineEdit.new()
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.text = str(randi() % 1000000)
	row.add_child(seed_edit)
	row.add_child(UiKit.button("Random", func(): seed_edit.text = str(randi() % 1000000)))
	inner.add_child(row)
	var drow := UiKit.hbox()
	drow.add_child(UiKit.label("Difficulty"))
	diff_option = OptionButton.new()
	diff_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var keys := Config.dict("difficulty").keys()
	for k in keys:
		diff_option.add_item(str(Config.dict("difficulty." + k).get("name", k)))
		diff_option.set_item_metadata(diff_option.item_count - 1, k)
	diff_option.select(maxi(keys.find("standard"), 0))
	diff_option.item_selected.connect(func(_i): _update_desc())
	drow.add_child(diff_option)
	inner.add_child(drow)
	diff_desc = UiKit.wrap_label("", 14, Color(0.65, 0.75, 0.9))
	inner.add_child(diff_desc)
	inner.add_child(UiKit.button("Launch", _on_start))
	_update_desc()
	return box


func _update_desc() -> void:
	var k := str(diff_option.get_item_metadata(diff_option.selected))
	diff_desc.text = str(Config.dict("difficulty." + k).get("description", ""))


## Seeds may be numbers or any text (text is hashed), so they are easy to share.
static func parse_seed(text: String) -> int:
	text = text.strip_edges()
	if text.is_valid_int():
		return int(text)
	return text.hash() if text != "" else randi()


func _on_start() -> void:
	main.start_new_game(parse_seed(seed_edit.text), str(diff_option.get_item_metadata(diff_option.selected)))


func _on_continue() -> void:
	var saves := Game.list_saves()
	if saves.is_empty():
		return
	main.load_slot(saves[0]["slot"])


func refresh() -> void:
	continue_btn.disabled = Game.list_saves().is_empty()


func _process(delta: float) -> void:
	if visible:
		t += delta
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.012, 0.03))
	for s in stars:
		var p := Vector2(fposmod(s[0].x * size.x - t * s[2] * 200.0, size.x), s[0].y * size.y)
		draw_rect(Rect2(p, Vector2(s[1], s[1])), Color(0.8, 0.88, 1.0, 0.4 + s[2] * 2.5))
	draw_circle(Vector2(size.x * 0.82, size.y * 0.22), 90, Color(1.0, 0.85, 0.5, 0.06))
	draw_circle(Vector2(size.x * 0.82, size.y * 0.22), 40, Color(1.0, 0.85, 0.5, 0.5))
