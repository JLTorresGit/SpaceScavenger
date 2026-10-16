extends SpaceEntity
## Drifting ion storm: drains ship energy while inside.

var bolts: Array = []
var redraw_t := 0.0
var rng := RandomNumberGenerator.new()


func _setup() -> void:
	layer = "back"
	is_hazard = true
	discoverable = false
	rng.seed = int(data.get("shape_seed", 1))


func default_name() -> String:
	return "Ion storm"


func scan_info() -> Dictionary:
	var info := super.scan_info()
	info["lines"] = ["Charged plasma, drains %.1f energy/s inside." % Config.fval("hazards.ion_storm.energy_drain_per_sec", 4)]
	return info


func _process(delta: float) -> void:
	position += velocity * delta
	redraw_t -= delta
	if redraw_t <= 0.0:
		redraw_t = 0.15
		bolts.clear()
		for i in 6:
			var a := rng.randf() * TAU
			var p := Vector2(cos(a), sin(a)) * rng.randf() * radius * 0.8
			var pts := PackedVector2Array([p])
			for s in 5:
				p += Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
				pts.append(p)
			bolts.append(pts)
		queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(0.35, 0.45, 1.0, 0.08))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(0.5, 0.6, 1.0, 0.3), 3.0, true)
	for b in bolts:
		draw_polyline(b, Color(0.7, 0.85, 1.0, 0.7), 2.0, true)
