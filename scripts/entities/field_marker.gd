extends SpaceEntity
## Invisible marker for an asteroid field, so fields appear on the radar, the
## codex and as suggestions when the ship needs metal for repairs.


func _setup() -> void:
	layer = "back"
	discoverable = true
	selectable = false


func default_name() -> String:
	return "Asteroid field " + Naming.catalogue_name(str(Config.get_v("naming.field_prefix", "AF")), int(data.get("name_seed", 0)))


func scan_info() -> Dictionary:
	var info := super.scan_info()
	info["lines"] = ["Asteroid field, radius %d u." % int(radius)]
	return info


func _draw() -> void:
	draw_arc(Vector2.ZERO, radius, 0, TAU, 64, Color(0.6, 0.55, 0.5, 0.08), 2.0, true)
