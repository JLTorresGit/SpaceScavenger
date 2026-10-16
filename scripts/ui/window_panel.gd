class_name WindowPanel
extends Control
## Modal window: dims the game, centres a titled panel and exposes `body` for
## content. Subclasses override _build() once and refresh() on every open.

signal closed

var main              # scenes/main.gd, gives access to ship/universe
var body: VBoxContainer
var panel: PanelContainer
var title_label: Label
var _built := false
var window_title := "Window"
var window_size := Vector2(760, 520)
var closable := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = window_size
	center.add_child(panel)
	var v := UiKit.vbox(10)
	panel.add_child(v)
	var top := UiKit.hbox()
	title_label = UiKit.label(window_title, 24, Color(0.6, 0.85, 1.0))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title_label)
	if closable:
		top.add_child(UiKit.button("Close  ✕", close))
	v.add_child(top)
	v.add_child(HSeparator.new())
	body = UiKit.vbox(8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)


func open() -> void:
	if not _built:
		_built = true
		_build()
	visible = true
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _build() -> void:
	pass


func refresh() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if visible and closable and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()
