extends Control
## Circular radar / mini-map, north-up, centred on the ship. Shows points of
## interest inside the current radar range with colour + shape coding.

const R := 120.0

var ship
var universe


func _ready() -> void:
	custom_minimum_size = Vector2(R * 2 + 8, R * 2 + 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, R, Color(0.02, 0.06, 0.1, 0.85))
	for k in [0.33, 0.66, 1.0]:
		draw_arc(c, R * k, 0, TAU, 48, Color(0.3, 0.6, 0.9, 0.35), 1.0, true)
	draw_line(c - Vector2(R, 0), c + Vector2(R, 0), Color(0.3, 0.6, 0.9, 0.15))
	draw_line(c - Vector2(0, R), c + Vector2(0, R), Color(0.3, 0.6, 0.9, 0.15))
	if ship == null or universe == null:
		return
	var font := get_theme_default_font()
	var range_ := float(ship.radar_range_now())
	if range_ <= 0.0:
		draw_string(font, c + Vector2(-62, 5), "SENSORS OFFLINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.pal("danger"))
		return
	var scale_ := R / range_
	# Discovered far objects that are not currently loaded (stations, stars...).
	for e in Game.discoveries.values():
		if universe.entities.has(e["id"]):
			continue
		var rel: Vector2 = universe.to_local_pos(float(e["wx"]), float(e["wy"])) - ship.position
		if rel.length() < range_:
			_mark(c + rel * scale_, str(e["kind"]), 0.0, Config.color(Config.dict("radar_colors").get(e["kind"], [0.7, 0.7, 0.7]), 0.6))
	for e in universe.entities.values():
		if not is_instance_valid(e):
			continue
		var rel: Vector2 = e.position - ship.position
		if rel.length() - e.radius > range_:
			continue
		var p: Vector2 = c + rel * scale_
		if p.distance_to(c) > R + 2:
			p = c + (p - c).normalized() * R
		_mark(p, e.kind, e.radius * scale_, e.radar_color())
	# Target
	var tp: Variant = ship.target_local_pos()
	if tp != null:
		var rel: Vector2 = tp - ship.position
		var p := c + rel * scale_
		if rel.length() > range_:
			p = c + rel.normalized() * (R - 4)
		draw_arc(p, 6, 0, TAU, 16, Game.pal("accent"), 2.0, true)
	# Ship
	var f := Vector2.from_angle(ship.heading)
	var r := Vector2(-f.y, f.x)
	draw_colored_polygon(PackedVector2Array([c + f * 8, c - f * 5 + r * 5, c - f * 5 - r * 5]), Color(1, 1, 1))
	draw_line(c, c + ship.velocity.limit_length(400) * 0.05, Game.pal("good"), 1.5)
	draw_string(font, c + Vector2(-R, R + 2), "Range " + UiKit.fmt_dist(range_), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.75, 0.9))


## Shape per kind so the radar is readable without colour.
func _mark(p: Vector2, kind: String, scaled_r: float, col: Color) -> void:
	match kind:
		"star":
			draw_circle(p, maxf(5.0, scaled_r), col)
		"planet":
			draw_circle(p, maxf(3.5, scaled_r), col)
		"moon":
			draw_circle(p, 2.5, col)
		"station":
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), col)
		"derelict":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(4, 3), p + Vector2(-4, 3)]), col)
		"asteroid", "comet":
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), col)
		"pickup":
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color(col, 0.8))
		"nebula", "ion_storm", "field":
			draw_arc(p, maxf(4.0, scaled_r), 0, TAU, 24, Color(col, 0.6), 1.0, true)
		"black_hole":
			draw_circle(p, 4, Color(0, 0, 0))
			draw_arc(p, 6, 0, TAU, 16, col, 2.0, true)
		_:
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(4, 0), p + Vector2(0, 5), p + Vector2(-4, 0)]), col)
