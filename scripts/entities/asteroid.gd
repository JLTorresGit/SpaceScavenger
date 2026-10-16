extends SpaceEntity
## Asteroid (iron / titanium / rare) or comet (ice, fast, with a tail).
## Breaks into ore drops and, when large, into smaller transient fragments.

var ore := "iron"
var spin := 0.0
var shape := PackedVector2Array()
var tint := Color.GRAY
var is_comet := false


func _setup() -> void:
	ore = str(data.get("ore", "iron"))
	is_comet = kind == "comet"
	spin = float(data.get("spin", 0.0))
	collidable = true
	minable = true
	discoverable = is_comet
	max_hp = radius * Config.fval("asteroids.hp_per_radius", 2.0)
	hp = max_hp
	shape = rough_polygon(int(data.get("shape_seed", 1)), radius, 9 + int(radius / 12), 0.3)
	tint = Config.color(Config.dict("asteroids.colors").get(ore, [0.5, 0.5, 0.5]))
	if not is_comet:
		rotation = float(data.get("shape_seed", 0) % 628) / 100.0


func default_name() -> String:
	return "Comet" if is_comet else "%s asteroid" % ore.capitalize()


func _process(delta: float) -> void:
	position += velocity * delta
	rotation += spin * delta
	if _hit_flash > 0.0:
		_hit_flash -= delta
		queue_redraw()


func scan_info() -> Dictionary:
	var info := super.scan_info()
	var table := "asteroid_" + ore
	var parts: PackedStringArray = []
	for e in Config.get_v("loot." + table, []):
		parts.append("%s %d-%d" % [Config.item_name(e["item"]), int(e["min"]), int(e["max"])])
	info["lines"] = ["Composition: %s" % ore.capitalize(), "Expected yield: " + ", ".join(parts), "Integrity %d/%d" % [int(hp), int(max_hp)]]
	return info


func _destroyed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var mult := float(data.get("richness", 1.0)) * Game.stat("salvage_yield") * clampf(radius / 50.0, 0.5, 1.8)
	universe.drop_loot(Generator.roll_loot("asteroid_" + ore, rng, mult), position, radius * 0.8)
	if radius >= Config.fval("asteroids.split_min_radius", 45) and not is_comet:
		for i in 2:
			var ang := rng.randf() * TAU
			var off := Vector2(cos(ang), sin(ang)) * radius * 0.5
			var frag := {"kind": "asteroid", "ore": ore, "radius": radius * 0.48, "spin": rng.randf_range(-1, 1),
				"shape_seed": rng.randi(), "richness": data.get("richness", 1.0),
				"vx": velocity.x + off.x * 0.3, "vy": velocity.y + off.y * 0.3}
			universe.spawn_transient(frag, position + off)
	Game.stat_add("asteroids_mined")
	universe.remove_entity(self, true)


func _draw() -> void:
	if is_comet and velocity.length() > 1.0:
		# Tail points away from the direction of travel (rotation is fixed for comets).
		var back := -velocity.normalized()
		var side := Vector2(-back.y, back.x)
		for i in 5:
			var w := radius * (1.0 - i * 0.18)
			var l := radius * (4.0 + i * 2.5)
			draw_colored_polygon(PackedVector2Array([side * w, back * l, -side * w]), Color(0.7, 0.9, 1.0, 0.09))
	var c := tint.lightened(0.5) if _hit_flash > 0.0 else tint
	draw_colored_polygon(shape, c)
	draw_polyline(closed(shape), c.darkened(0.4), 2.0, true)
	# A couple of crater marks for texture.
	draw_circle(Vector2(radius * 0.25, -radius * 0.2), radius * 0.18, c.darkened(0.15))
	draw_circle(Vector2(-radius * 0.3, radius * 0.25), radius * 0.12, c.darkened(0.2))
	if ore == "rare":
		draw_circle(Vector2(-radius * 0.1, -radius * 0.35), radius * 0.1, Color(0.85, 0.5, 1.0))
		draw_circle(Vector2(radius * 0.35, radius * 0.3), radius * 0.08, Color(0.85, 0.5, 1.0))
	if hp < max_hp:
		draw_arc(Vector2.ZERO, radius + 6, -PI / 2, -PI / 2 + TAU * hp / max_hp, 32, Color(1, 0.8, 0.3, 0.7), 2.0)
