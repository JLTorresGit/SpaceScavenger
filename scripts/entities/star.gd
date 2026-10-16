extends SpaceEntity
## Star: thermal danger zone, solar-scoop band, gravity and random solar flares.

var heat_radius := 1000.0
var core_color := Color.WHITE
var flare_timer := 60.0
var flare_left := 0.0
var flare_warned := false


func _setup() -> void:
	heat_radius = float(data["heat_radius"])
	core_color = Config.color(data["color"])
	collidable = true
	discoverable = true
	has_gravity = true
	surface_g = float(data["surface_gravity"])
	influence = float(data["influence"])
	flare_timer = Config.rand_range(_runtime_rng(), Config.get_v("heat.flare_interval", [40, 90]))


func _runtime_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng


func default_name() -> String:
	return Naming.default_body_name(data)


func is_flaring() -> bool:
	return flare_left > 0.0


func flare_incoming() -> bool:
	return flare_left <= 0.0 and flare_timer < Config.fval("heat.flare_warning", 4)


func heat_multiplier() -> float:
	return Config.fval("heat.flare_heat_multiplier", 3.0) if is_flaring() else 1.0


func _process(delta: float) -> void:
	if flare_left > 0.0:
		flare_left -= delta
		if flare_left <= 0.0:
			flare_timer = Config.rand_range(_runtime_rng(), Config.get_v("heat.flare_interval", [40, 90]))
			flare_warned = false
		queue_redraw()
	else:
		flare_timer -= delta
		if flare_timer <= 0.0:
			flare_left = Config.fval("heat.flare_duration", 6)
			queue_redraw()


func scan_info() -> Dictionary:
	var info := super.scan_info()
	info["lines"] = [
		"Spectral class %s, %d K" % [data["class"], int(data["temperature"])],
		"Radius %d u, thermal zone %d u" % [int(radius), int(heat_radius)],
		"Surface gravity %.0f u/s²" % surface_g,
	]
	return info


func _draw() -> void:
	var glow := 1.4 if is_flaring() else 1.0
	for layer_i in 6:
		var k := 1.0 + layer_i * 0.35
		draw_circle(Vector2.ZERO, radius * k, Color(core_color, 0.08 * glow / k))
	draw_circle(Vector2.ZERO, radius, core_color.lightened(0.15))
	draw_circle(Vector2.ZERO, radius * 0.8, core_color.lightened(0.45))
	draw_circle(Vector2.ZERO, radius * 0.5, Color(1, 1, 1, 0.9))
	# Thermal danger boundary (dashed) and scoop band.
	var hc := Color(1.0, 0.35, 0.2, 0.35 if not is_flaring() else 0.7)
	var segments := 72
	for s in segments:
		if s % 2 == 0:
			var a0 := TAU * s / segments
			draw_arc(Vector2.ZERO, heat_radius, a0, a0 + TAU / segments, 4, hc, 3.0, true)
