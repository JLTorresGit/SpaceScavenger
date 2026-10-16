extends SpaceEntity
## Trading outpost: dock (slow down within range and press Interact) to trade,
## refuel, recharge, repair and sell discovery data.

var spin := 0.1


func _setup() -> void:
	collidable = true
	discoverable = true
	spin = float(data.get("spin", 0.1))


func default_name() -> String:
	if id == "home_station":
		return "Haven Prime"
	return Naming.station_name(int(data.get("name_seed", 0)))


func scan_info() -> Dictionary:
	var info := super.scan_info()
	info["lines"] = ["Trading outpost: refuel, recharge, repairs, market.", "Dock: slow below %d u/s within %d u and press %s." % [
		Config.ival("ship.dock_max_speed"), Config.ival("ship.dock_range"), Config.binding_text("interact")]]
	return info


func _process(delta: float) -> void:
	rotation += spin * delta


func _draw() -> void:
	var ring := Color(0.55, 0.85, 0.7)
	draw_circle(Vector2.ZERO, Config.fval("ship.dock_range", 260), Color(0.4, 1.0, 0.6, 0.04))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, ring, 10.0, true)
	draw_arc(Vector2.ZERO, radius * 0.92, 0, TAU, 64, ring.darkened(0.4), 3.0, true)
	for i in 4:
		var a := TAU * i / 4.0
		draw_line(Vector2.ZERO, Vector2(cos(a), sin(a)) * radius, ring.darkened(0.3), 5.0)
	draw_circle(Vector2.ZERO, radius * 0.28, Color(0.75, 0.8, 0.85))
	draw_circle(Vector2.ZERO, radius * 0.16, Color(0.4, 1.0, 0.6))
	for i in 8:
		var a := TAU * i / 8.0
		draw_circle(Vector2(cos(a), sin(a)) * radius, 3.5, Color(1, 1, 0.7))
