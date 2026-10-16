extends SpaceEntity
## Derelict satellite, vessel, station wreck or ghost ship. Cut it apart with the
## salvage laser to drop fuel cells, electronics and alloys; leaves a log entry.

var subtype := "vessel"
var parts: Array = []      # [Rect2, Color]
var spin := 0.0
var blink := 0.0


func _setup() -> void:
	subtype = str(data.get("subtype", "vessel"))
	collidable = true
	minable = true
	discoverable = subtype == "ghost_ship"
	max_hp = float(Config.dict("derelicts." + subtype).get("hp", 100))
	hp = max_hp
	rotation = float(data.get("rot", 0.0))
	spin = float(data.get("spin", 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.get("shape_seed", 1))
	var base := Color(0.5, 0.5, 0.55) if subtype != "ghost_ship" else Color(0.35, 0.6, 0.5)
	match subtype:
		"satellite":
			parts.append([Rect2(-radius * 0.3, -radius * 0.3, radius * 0.6, radius * 0.6), base.lightened(0.2)])
			parts.append([Rect2(-radius, -radius * 0.12, radius * 0.65, radius * 0.24), Color(0.25, 0.35, 0.7)])
			parts.append([Rect2(radius * 0.35, -radius * 0.12, radius * 0.65, radius * 0.24), Color(0.25, 0.35, 0.7)])
		"station_wreck":
			for i in rng.randi_range(5, 8):
				var w := rng.randf_range(0.3, 0.9) * radius
				var h := rng.randf_range(0.15, 0.4) * radius
				var c := Vector2(rng.randf_range(-0.55, 0.55), rng.randf_range(-0.55, 0.55)) * radius
				parts.append([Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h)), base.darkened(rng.randf_range(0, 0.3))])
		_:
			parts.append([Rect2(-radius, -radius * 0.25, radius * 1.6, radius * 0.5), base])
			parts.append([Rect2(radius * 0.4, -radius * 0.18, radius * 0.6, radius * 0.36), base.lightened(0.15)])
			parts.append([Rect2(-radius * 0.9, -radius * 0.55, radius * 0.6, radius * 0.3), base.darkened(0.2)])
			parts.append([Rect2(-radius * 0.9, radius * 0.25, radius * 0.6, radius * 0.3), base.darkened(0.2)])
			if rng.randf() < 0.6:
				parts.append([Rect2(-radius * 0.2, -radius * 0.8, radius * 0.25, radius * 0.6), base.darkened(0.35)])


func default_name() -> String:
	if subtype == "ghost_ship":
		return Naming.lore_entry(int(data.get("lore_seed", 0)), subtype)["title"]
	return "Derelict " + subtype.replace("_", " ")


func _process(delta: float) -> void:
	rotation += spin * delta
	blink += delta
	if _hit_flash > 0.0 or fmod(blink, 1.5) < delta * 2.0:
		_hit_flash = maxf(_hit_flash - delta, 0.0)
		queue_redraw()


func scan_info() -> Dictionary:
	var info := super.scan_info()
	var parts_text: PackedStringArray = []
	for e in Config.get_v("loot." + str(Config.dict("derelicts." + subtype).get("loot", "")), []):
		parts_text.append("%s%s" % [Config.item_name(e["item"]), "" if float(e.get("chance", 1)) >= 1.0 else " (maybe)"])
	var entry := Naming.lore_entry(int(data.get("lore_seed", 0)), subtype)
	info["lines"] = ["Salvage: " + ", ".join(parts_text), "Hull integrity %d/%d" % [int(hp), int(max_hp)], "Log recovered: \"%s\"" % entry["title"]]
	return info


func _destroyed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var table := str(Config.dict("derelicts." + subtype).get("loot", "derelict_vessel"))
	var mult := float(data.get("richness", 1.0)) * Game.stat("salvage_yield")
	universe.drop_loot(Generator.roll_loot(table, rng, mult), position, radius)
	var entry := Naming.lore_entry(int(data.get("lore_seed", 0)), subtype)
	Game.add_log(entry["title"], entry["text"])
	Game.notify("Recovered log: " + entry["title"])
	Game.stat_add("derelicts_salvaged")
	universe.remove_entity(self, true)


func _draw() -> void:
	var flash := _hit_flash > 0.0
	for p in parts:
		var c: Color = p[1]
		draw_rect(p[0], c.lightened(0.4) if flash else c)
		draw_rect(p[0], c.darkened(0.45), false, 2.0)
	# Hull damage scars and a blinking beacon light.
	draw_line(Vector2(-radius * 0.5, -radius * 0.1), Vector2(radius * 0.1, radius * 0.15), Color(0.15, 0.12, 0.1), 3.0)
	if fmod(blink, 1.5) < 0.25:
		draw_circle(Vector2(radius * 0.7, 0), 4.0, Color(1, 0.3, 0.2) if subtype != "ghost_ship" else Color(0.4, 1, 0.7))
	if subtype == "ghost_ship":
		draw_circle(Vector2.ZERO, radius * 1.3, Color(0.3, 1.0, 0.6, 0.06))
	if hp < max_hp:
		draw_arc(Vector2.ZERO, radius + 8, -PI / 2, -PI / 2 + TAU * hp / max_hp, 40, Color(1, 0.8, 0.3, 0.7), 2.0)
