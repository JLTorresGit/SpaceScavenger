extends SpaceEntity
## Nebula: blinds sensors (shorter radar) but recharges shields faster.

var blobs: Array = []
var tint := Color(0.6, 0.4, 1.0)


func _setup() -> void:
	layer = "back"
	is_hazard = true
	discoverable = true
	selectable = true
	tint = Color.from_hsv(float(data.get("hue", 0.7)), 0.55, 0.9)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.get("shape_seed", 1))
	for i in 14:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * radius * 0.7
		blobs.append([Vector2(cos(a), sin(a)) * d, radius * rng.randf_range(0.25, 0.5)])


func default_name() -> String:
	return Naming.catalogue_name("NGC", int(data.get("name_seed", 0)))


func scan_info() -> Dictionary:
	var info := super.scan_info()
	info["lines"] = ["Dense gas cloud, radius %d u." % int(radius), "Radar range reduced inside; shields regenerate faster."]
	return info


func _draw() -> void:
	for b in blobs:
		draw_circle(b[0], b[1], Color(tint, 0.07))
		draw_circle(b[0], b[1] * 0.6, Color(tint, 0.05))
