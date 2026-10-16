extends SpaceEntity
## Wormhole: flying into it jumps the ship to a far, deterministic destination.

var swirl := 0.0


func _setup() -> void:
	discoverable = true


func default_name() -> String:
	return Naming.catalogue_name("WH", int(data.get("name_seed", 0)))


func scan_info() -> Dictionary:
	var info := super.scan_info()
	var d := Vector2(float(data["dest_wx"]) - wx(), float(data["dest_wy"]) - wy()).length()
	info["lines"] = ["Stable fold. Exit about %d k u away." % int(d / 1000.0)]
	return info


func on_ship_contact(ship) -> void:
	if ship.has_method("enter_wormhole"):
		ship.enter_wormhole(self)


func _process(delta: float) -> void:
	swirl += delta * 2.0
	queue_redraw()


func _draw() -> void:
	for i in 6:
		var a := swirl + i * TAU / 6.0
		draw_arc(Vector2.ZERO, radius * (0.4 + i * 0.12), a, a + PI, 24, Color(0.8, 0.5, 1.0, 0.6 - i * 0.07), 4.0, true)
	draw_circle(Vector2.ZERO, radius * 0.3, Color(0.1, 0.0, 0.2))
	draw_arc(Vector2.ZERO, radius * 1.3, 0, TAU, 48, Color(0.9, 0.6, 1.0, 0.25), 2.0, true)
