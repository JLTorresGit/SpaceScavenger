extends SpaceEntity
## Black hole: extreme gravity, heavy damage close to the event horizon.

var swirl := 0.0


func _setup() -> void:
	is_hazard = true
	has_gravity = true
	discoverable = true
	influence = float(data["influence"])
	surface_g = float(data["surface_gravity"])


func default_name() -> String:
	return Naming.catalogue_name("BH", int(data.get("name_seed", 0)))


func damage_radius() -> float:
	return radius * Config.fval("hazards.black_hole.damage_radius_factor", 1.5)


func scan_info() -> Dictionary:
	var info := super.scan_info()
	info["lines"] = ["Event horizon %d u, gravity influence %d u." % [int(radius), int(influence)], "Do not cross within %d u." % int(damage_radius())]
	return info


func _process(delta: float) -> void:
	swirl += delta * 0.8
	queue_redraw()


func _draw() -> void:
	for i in 10:
		var r := radius * (1.3 + i * 0.35)
		var a0 := swirl * (1.0 + 0.15 * i) + i
		draw_arc(Vector2.ZERO, r, a0, a0 + PI * 1.2, 32, Color(1.0, 0.5 + i * 0.04, 0.3, 0.35 - i * 0.03), 6.0, true)
	draw_circle(Vector2.ZERO, radius * 1.05, Color(1.0, 0.8, 0.5, 0.6))
	draw_circle(Vector2.ZERO, radius, Color(0, 0, 0))
	draw_arc(Vector2.ZERO, influence, 0, TAU, 128, Color(1.0, 0.3, 0.6, 0.08), 3.0, true)
