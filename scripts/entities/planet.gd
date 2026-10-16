extends SpaceEntity
## Planet or moon: gravity well, solid surface, discoverable and nameable.

var base_color := Color.GRAY
var rings := false
var bands: Array = []


func _setup() -> void:
	base_color = Config.color(data["color"])
	collidable = true
	discoverable = true
	has_gravity = true
	surface_g = float(data["surface_gravity"])
	influence = float(data["influence"])
	rings = bool(data.get("rings", false))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.get("shade_seed", 1))
	base_color = base_color.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.12)
	if str(data.get("ptype", "")) == "gas_giant":
		for i in rng.randi_range(3, 6):
			bands.append([rng.randf_range(-0.8, 0.8), rng.randf_range(0.05, 0.16), rng.randf_range(-0.15, 0.15)])


func default_name() -> String:
	return Naming.default_body_name(data)


func scan_info() -> Dictionary:
	var info := super.scan_info()
	var t := str(data.get("ptype", "moon")).replace("_", " ")
	info["lines"] = [
		"Type: %s" % t.capitalize(),
		"Radius %d u, surface gravity %.0f u/s²" % [int(radius), surface_g],
		"Gravity influence %d u" % int(influence),
	]
	return info


func _draw() -> void:
	# Atmosphere halo
	draw_circle(Vector2.ZERO, radius * 1.08, Color(base_color.lightened(0.3), 0.18))
	draw_circle(Vector2.ZERO, radius, base_color)
	for b in bands:
		var y: float = b[0] * radius
		var h: float = b[1] * radius
		var half_w := sqrt(maxf(radius * radius - y * y, 0.0))
		draw_rect(Rect2(-half_w * 0.98, y - h * 0.5, half_w * 1.96, h), Color(base_color.darkened(0.2 + b[2]), 0.55))
	# Night side shading
	draw_circle(Vector2(radius * 0.22, radius * 0.18), radius * 0.7, Color(0, 0, 0, 0.18))
	draw_circle(Vector2(radius * 0.3, radius * 0.25), radius * 0.6, Color(0, 0, 0, 0.18))
	draw_circle(Vector2(-radius * 0.3, -radius * 0.3), radius * 0.35, Color(1, 1, 1, 0.07))
	if rings:
		draw_set_transform(Vector2.ZERO, 0.35, Vector2(1.0, 0.32))
		draw_arc(Vector2.ZERO, radius * 1.7, 0, TAU, 64, Color(base_color.lightened(0.35), 0.55), radius * 0.18, true)
		draw_arc(Vector2.ZERO, radius * 2.0, 0, TAU, 64, Color(base_color.lightened(0.2), 0.3), radius * 0.1, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_arc(Vector2.ZERO, influence, 0, TAU, 96, Color(0.5, 0.7, 1.0, 0.06), 2.0, true)
