class_name Generator
extends RefCounted
## Deterministic, thread-safe universe generation. Produces plain dictionaries
## (no nodes) so it can run on worker threads. The same seed and coordinates
## always produce the same content; only player changes are saved (deltas).

const SALT_SYSTEM := 1
const SALT_CHUNK := 2
const SALT_NAME := 3


## 64-bit mixing function (splitmix/murmur finalizer). Wraps on overflow.
static func mix(h: int) -> int:
	h ^= h >> 33
	h *= -49064778989728563
	h ^= h >> 33
	h *= -4265267296055464877
	h ^= h >> 33
	return h


static func hash3(world_seed: int, a: int, b: int, salt: int) -> int:
	return mix(mix(mix(world_seed ^ (a * 73856093)) ^ (b * 19349663)) ^ (salt * 83492791))


static func rng_for(world_seed: int, a: int, b: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash3(world_seed, a, b, salt)
	return rng


static func chunk_key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]


static func biome(world_seed: int, cx: int, cy: int) -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.seed = world_seed & 0x7fffffff
	noise.frequency = Config.fval("world.biome.noise_frequency", 0.06)
	var v := noise.get_noise_2d(cx, cy)
	var name := "normal"
	if v > Config.fval("world.biome.core_threshold", 0.25):
		name = "core"
	elif v < Config.fval("world.biome.rim_threshold", -0.25):
		name = "rim"
	return {"name": name, "density": float(Config.dict("world.biome.density").get(name, 1.0))}


static func richness(wx: float, wy: float) -> float:
	var d := sqrt(wx * wx + wy * wy)
	return minf(1.0 + d / 100000.0 * Config.fval("world.richness_per_100k", 0.25), Config.fval("world.richness_max", 3.0))


# --- Star systems -------------------------------------------------------------

static func system_key(sx: int, sy: int) -> String:
	return "%d,%d" % [sx, sy]


## Returns {} when the cell has no system, otherwise
## {id, wx, wy, bounds, entities: [...]} with star, planets, moons and debris.
static func system_at(world_seed: int, sx: int, sy: int) -> Dictionary:
	var rng := rng_for(world_seed, sx, sy, SALT_SYSTEM)
	var cell := Config.fval("world.system_cell_size", 50000)
	var is_home := sx == 0 and sy == 0
	if not is_home and rng.randf() > Config.fval("world.system_chance", 0.6):
		return {}
	var jitter := Config.fval("world.system_jitter", 0.15)
	var wx := (sx + 0.5 + rng.randf_range(-jitter, jitter)) * cell
	var wy := (sy + 0.5 + rng.randf_range(-jitter, jitter)) * cell
	var star_types := Config.dict("bodies.star_types")
	var star_class := Config.weighted_pick(rng, star_types)
	var planet_count := Config.rand_int(rng, Config.get_v("world.star_system.planets", [1, 6]))
	if is_home:
		var home := Config.dict("world.home_system")
		var c: Array = home.get("center", [14000, 6000])
		wx = float(c[0])
		wy = float(c[1])
		star_class = str(home.get("star_class", "G"))
		planet_count = int(home.get("planets", 3))
	var st: Dictionary = star_types[star_class]
	var sid := "s%d_%d" % [sx, sy]
	var star_radius := Config.rand_range(rng, st["radius"])
	var heat_radius := star_radius * float(st.get("heat_factor", 3.0))
	var name_seed := hash3(world_seed, sx, sy, SALT_NAME)
	var star := {
		"id": sid, "kind": "star", "class": star_class, "wx": wx, "wy": wy,
		"radius": star_radius, "heat_radius": heat_radius, "color": st["color"],
		"surface_gravity": float(st.get("surface_gravity", 150)),
		"influence": star_radius * Config.fval("bodies.star_influence_factor", 9.0),
		"temperature": int(st.get("temperature", 5800)), "name_seed": name_seed,
	}
	var entities: Array = [star]
	var orbit := heat_radius + Config.fval("world.star_system.planet_orbit_offset", 1200)
	var planet_types := Config.dict("bodies.planet_types")
	var ss := Config.dict("world.star_system")
	var station_placed := false
	for p in planet_count:
		orbit += Config.rand_range(rng, ss.get("planet_orbit_gap", [1400, 2400]))
		var angle := rng.randf() * TAU
		var ptype := Config.weighted_pick(rng, planet_types)
		var pt: Dictionary = planet_types[ptype]
		var pr := Config.rand_range(rng, pt["radius"])
		var px := wx + cos(angle) * orbit
		var py := wy + sin(angle) * orbit
		var pid := "%s_p%d" % [sid, p]
		entities.append({
			"id": pid, "kind": "planet", "ptype": ptype, "wx": px, "wy": py, "radius": pr,
			"color": pt["color"], "surface_gravity": float(pt.get("surface_gravity", 60)),
			"influence": pr * Config.fval("bodies.planet_influence_factor", 7.0),
			"rings": rng.randf() < float(pt.get("ring_chance", 0.0)),
			"star_id": sid, "star_name_seed": name_seed, "index": p, "orbit": orbit,
			"shade_seed": rng.randi(),
		})
		# Moons
		var moon_cfg := Config.dict("bodies.moon")
		var moon_count := Config.rand_int(rng, ss.get("moons", [0, 3]))
		var moon_orbit := pr * Config.rand_range(rng, ss.get("moon_orbit_factor", [2.2, 4.5]))
		for m in moon_count:
			var ma := rng.randf() * TAU
			var mr := Config.rand_range(rng, moon_cfg.get("radius", [30, 60]))
			var colors: Array = moon_cfg.get("colors", [[0.6, 0.6, 0.6]])
			entities.append({
				"id": "%s_m%d" % [pid, m], "kind": "moon", "wx": px + cos(ma) * moon_orbit, "wy": py + sin(ma) * moon_orbit,
				"radius": mr, "color": colors[rng.randi() % colors.size()],
				"surface_gravity": float(moon_cfg.get("surface_gravity", 25)),
				"influence": mr * float(moon_cfg.get("influence_factor", 5.0)),
				"planet_id": pid, "star_id": sid, "star_name_seed": name_seed, "planet_index": p, "index": m,
				"shade_seed": rng.randi(),
			})
			moon_orbit += mr * 2.0 + rng.randf_range(90, 200)
		# Low-orbit debris: high concentration of derelicts and scrap.
		var debris_count := Config.rand_int(rng, ss.get("orbit_debris", [3, 9]))
		var band: Array = ss.get("orbit_debris_band", [1.4, 2.4])
		for d in debris_count:
			var da := rng.randf() * TAU
			var dd := pr * rng.randf_range(float(band[0]), float(band[1]))
			var dx := px + cos(da) * dd
			var dy := py + sin(da) * dd
			var did := "%s_d%d" % [pid, d]
			match Config.weighted_pick(rng, ss.get("orbit_debris_weights", {"scrap": 1.0})):
				"derelict":
					entities.append(_derelict(rng, did, dx, dy, Config.weighted_pick(rng, {"satellite": 0.7, "vessel": 0.3})))
				"asteroid":
					entities.append(_asteroid(rng, did, dx, dy, Config.rand_range(rng, [20, 45])))
				_:
					entities.append(_pickup(did, dx, dy, "scrap_alloy" if rng.randf() < 0.8 else "electronics", rng.randi_range(1, 2), true))
		if not station_placed and rng.randf() < float(ss.get("station_chance", 0.4)):
			station_placed = true
			var sa := rng.randf() * TAU
			var sd := pr * 3.2 + 300.0
			entities.append(_station(rng, "%s_st" % pid, px + cos(sa) * sd, py + sin(sa) * sd))
	return {"id": sid, "wx": wx, "wy": wy, "bounds": orbit + 2500.0, "entities": entities}


## Lightweight summary used for streaming decisions and chunk exclusion.
static func system_summary(world_seed: int, sx: int, sy: int) -> Dictionary:
	var sys := system_at(world_seed, sx, sy)
	if sys.is_empty():
		return {}
	var blockers: Array = []
	for e in sys["entities"]:
		if e["kind"] == "star":
			blockers.append([e["wx"], e["wy"], e["heat_radius"] + 400.0])
		elif e["kind"] == "planet" or e["kind"] == "moon":
			blockers.append([e["wx"], e["wy"], e["radius"] * 2.0 + 150.0])
	return {"id": sys["id"], "wx": sys["wx"], "wy": sys["wy"], "bounds": sys["bounds"], "blockers": blockers}


# --- Chunks -----------------------------------------------------------------

## Free-space content of one chunk (asteroid fields, derelicts, scrap, hazards,
## anomalies, stations). Avoids star systems' stars and planets.
static func chunk_at(world_seed: int, cx: int, cy: int) -> Array:
	var rng := rng_for(world_seed, cx, cy, SALT_CHUNK)
	var size := Config.fval("world.chunk_size", 4000)
	var x0 := cx * size
	var y0 := cy * size
	var sp := Config.dict("world.spawn")
	var b := biome(world_seed, cx, cy)
	var density: float = b["density"]
	var rich := richness(x0 + size * 0.5, y0 + size * 0.5)
	var blockers := _blockers_near(world_seed, x0 + size * 0.5, y0 + size * 0.5)
	var safe_r := Config.fval("world.start_safe_radius", 1400)
	var out: Array = []
	var n := 0
	var free_spot := func(margin: float) -> Vector2:
		# Returns a random point in the chunk that avoids bodies; (NAN) when none found.
		for attempt in 8:
			var px := x0 + rng.randf() * size
			var py := y0 + rng.randf() * size
			if px * px + py * py < safe_r * safe_r:
				continue
			var ok := true
			for bl in blockers:
				var ddx: float = px - bl[0]
				var ddy: float = py - bl[1]
				if ddx * ddx + ddy * ddy < pow(bl[2] + margin, 2):
					ok = false
					break
			if ok:
				return Vector2(px - x0, py - y0)
		return Vector2(NAN, NAN)

	# Asteroid field (with a marker entity so fields show on radar and codex).
	if rng.randf() < float(sp.get("asteroid_field_chance", 0.2)) * density:
		var field_r := Config.rand_range(rng, sp.get("asteroid_field_radius", [600, 1400]))
		var c: Vector2 = free_spot.call(field_r)
		if not is_nan(c.x):
			var fx := x0 + c.x
			var fy := y0 + c.y
			out.append({"id": "c%d_%d_f" % [cx, cy], "kind": "field", "wx": fx, "wy": fy, "radius": field_r,
				"name_seed": hash3(world_seed, cx, cy, 7)})
			var count := int(Config.rand_int(rng, sp.get("asteroids_per_field", [8, 20])) * clampf(density, 0.6, 1.6))
			for a in count:
				var ang := rng.randf() * TAU
				var dist := sqrt(rng.randf()) * field_r
				var ar := Config.rand_range(rng, Config.get_v("asteroids.radius", [20, 90]))
				out.append(_asteroid(rng, "c%d_%d_a%d" % [cx, cy, a], fx + cos(ang) * dist, fy + sin(ang) * dist, ar, rich))
	# Derelicts
	if rng.randf() < float(sp.get("derelict_chance", 0.3)) * density:
		for d in Config.rand_int(rng, sp.get("derelicts_per_chunk", [1, 2])):
			var p: Vector2 = free_spot.call(200.0)
			if not is_nan(p.x):
				var sub := Config.weighted_pick(rng, sp.get("derelict_weights", {"vessel": 1.0}))
				out.append(_derelict(rng, "c%d_%d_d%d" % [cx, cy, d], x0 + p.x, y0 + p.y, sub, rich))
	# Floating scrap clusters
	if rng.randf() < float(sp.get("scrap_cluster_chance", 0.3)) * density:
		var p: Vector2 = free_spot.call(100.0)
		if not is_nan(p.x):
			for s in Config.rand_int(rng, sp.get("scrap_per_cluster", [3, 7])):
				var item := "electronics" if rng.randf() < 0.15 else "scrap_alloy"
				out.append(_pickup("c%d_%d_s%d" % [cx, cy, s], x0 + p.x + rng.randf_range(-160, 160), y0 + p.y + rng.randf_range(-160, 160), item, rng.randi_range(1, 2), true))
	# Hazards
	if rng.randf() < float(sp.get("nebula_chance", 0.04)):
		var p: Vector2 = free_spot.call(0.0)
		if not is_nan(p.x):
			out.append({"id": "c%d_%d_neb" % [cx, cy], "kind": "nebula", "wx": x0 + p.x, "wy": y0 + p.y,
				"radius": Config.rand_range(rng, Config.get_v("hazards.nebula.radius", [1500, 3500])),
				"hue": rng.randf(), "shape_seed": rng.randi(), "name_seed": hash3(world_seed, cx, cy, 8)})
	if rng.randf() < float(sp.get("ion_storm_chance", 0.03)):
		var p: Vector2 = free_spot.call(300.0)
		if not is_nan(p.x):
			var ang := rng.randf() * TAU
			var spd := Config.rand_range(rng, Config.get_v("hazards.ion_storm.drift_speed", [15, 45]))
			out.append({"id": "c%d_%d_ion" % [cx, cy], "kind": "ion_storm", "wx": x0 + p.x, "wy": y0 + p.y,
				"radius": Config.rand_range(rng, Config.get_v("hazards.ion_storm.radius", [800, 1800])),
				"vx": cos(ang) * spd, "vy": sin(ang) * spd, "shape_seed": rng.randi()})
	if blockers.is_empty() and rng.randf() < float(sp.get("black_hole_chance", 0.004)):
		var bh := Config.dict("hazards.black_hole")
		var p: Vector2 = free_spot.call(float(bh.get("influence", 3500)))
		if not is_nan(p.x):
			out.append({"id": "c%d_%d_bh" % [cx, cy], "kind": "black_hole", "wx": x0 + p.x, "wy": y0 + p.y,
				"radius": float(bh.get("horizon", 140)), "influence": float(bh.get("influence", 3500)),
				"surface_gravity": float(bh.get("surface_gravity", 1800)), "name_seed": hash3(world_seed, cx, cy, 9)})
	if rng.randf() < float(sp.get("comet_chance", 0.04)):
		var p: Vector2 = free_spot.call(200.0)
		if not is_nan(p.x):
			var comet := _asteroid(rng, "c%d_%d_comet" % [cx, cy], x0 + p.x, y0 + p.y, Config.rand_range(rng, Config.get_v("hazards.comet.radius", [22, 36])), rich)
			var ang := rng.randf() * TAU
			var spd := Config.rand_range(rng, Config.get_v("hazards.comet.speed", [60, 140]))
			comet["kind"] = "comet"
			comet["ore"] = "ice"
			comet["vx"] = cos(ang) * spd
			comet["vy"] = sin(ang) * spd
			comet["spin"] = 0.0
			out.append(comet)
	# Stations and anomalies
	if rng.randf() < float(sp.get("station_chance", 0.025)):
		var p: Vector2 = free_spot.call(400.0)
		if not is_nan(p.x):
			out.append(_station(rng, "c%d_%d_st" % [cx, cy], x0 + p.x, y0 + p.y))
	if rng.randf() < float(sp.get("wormhole_chance", 0.006)):
		var p: Vector2 = free_spot.call(300.0)
		if not is_nan(p.x):
			var ang := rng.randf() * TAU
			var jump := Config.rand_range(rng, Config.get_v("anomalies.wormhole.jump_distance", [60000, 150000]))
			out.append({"id": "c%d_%d_wh" % [cx, cy], "kind": "wormhole", "wx": x0 + p.x, "wy": y0 + p.y,
				"radius": Config.fval("anomalies.wormhole.radius", 90),
				"dest_wx": x0 + p.x + cos(ang) * jump, "dest_wy": y0 + p.y + sin(ang) * jump,
				"name_seed": hash3(world_seed, cx, cy, 10)})
	if rng.randf() < float(sp.get("signal_chance", 0.02)):
		var p: Vector2 = free_spot.call(100.0)
		if not is_nan(p.x):
			out.append({"id": "c%d_%d_sig" % [cx, cy], "kind": "signal", "wx": x0 + p.x, "wy": y0 + p.y,
				"radius": Config.fval("anomalies.signal.radius", 40), "reward_seed": rng.randi()})
	if rng.randf() < float(sp.get("ghost_ship_chance", 0.006)):
		var p: Vector2 = free_spot.call(200.0)
		if not is_nan(p.x):
			out.append(_derelict(rng, "c%d_%d_ghost" % [cx, cy], x0 + p.x, y0 + p.y, "ghost_ship", rich))
	if rng.randf() < float(sp.get("rescue_chance", 0.01)):
		var p: Vector2 = free_spot.call(100.0)
		if not is_nan(p.x):
			out.append({"id": "c%d_%d_pod" % [cx, cy], "kind": "rescue_pod", "wx": x0 + p.x, "wy": y0 + p.y,
				"radius": Config.fval("anomalies.rescue.radius", 30), "reward_seed": rng.randi()})
	# Guaranteed starter content near the origin.
	if cx == 0 and cy == 0:
		var hs: Array = Config.get_v("world.home_station", [2600, 1800])
		out.append(_station(rng, "home_station", float(hs[0]), float(hs[1])))
	if cx == 0 and cy == -1:
		var hd: Array = Config.get_v("world.home_derelict", [900, -700])
		out.append(_derelict(rng, "home_derelict", float(hd[0]), float(hd[1]), "vessel", 1.0))
	n = out.size()
	return out


static func _blockers_near(world_seed: int, wx: float, wy: float) -> Array:
	var cell := Config.fval("world.system_cell_size", 50000)
	var sx := floori(wx / cell)
	var sy := floori(wy / cell)
	var out: Array = []
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			var s := system_summary(world_seed, sx + ox, sy + oy)
			if s.is_empty():
				continue
			var dx: float = wx - s["wx"]
			var dy: float = wy - s["wy"]
			if sqrt(dx * dx + dy * dy) < s["bounds"] + 6000.0:
				out.append_array(s["blockers"])
	return out


# --- Entity builders --------------------------------------------------------

static func _asteroid(rng: RandomNumberGenerator, id: String, x: float, y: float, r: float, rich := 1.0) -> Dictionary:
	var ang := rng.randf() * TAU
	var spd := Config.rand_range(rng, Config.get_v("asteroids.drift_speed", [0, 20]))
	return {"id": id, "kind": "asteroid", "wx": x, "wy": y, "radius": r,
		"ore": Config.weighted_pick(rng, Config.dict("asteroids.ore_weights")),
		"vx": cos(ang) * spd, "vy": sin(ang) * spd,
		"spin": Config.rand_range(rng, Config.get_v("asteroids.spin", [-0.5, 0.5])),
		"shape_seed": rng.randi(), "richness": rich}


static func _derelict(rng: RandomNumberGenerator, id: String, x: float, y: float, subtype: String, rich := 1.0) -> Dictionary:
	var def := Config.dict("derelicts." + subtype)
	return {"id": id, "kind": "derelict", "subtype": subtype, "wx": x, "wy": y,
		"radius": Config.rand_range(rng, def.get("radius", [40, 80])), "rot": rng.randf() * TAU,
		"spin": rng.randf_range(-0.05, 0.05), "shape_seed": rng.randi(), "lore_seed": rng.randi(), "richness": rich}


static func _pickup(id: String, x: float, y: float, item: String, n: int, persistent: bool) -> Dictionary:
	return {"id": id, "kind": "pickup", "wx": x, "wy": y, "item": item, "count": n, "persistent": persistent}


static func _station(rng: RandomNumberGenerator, id: String, x: float, y: float) -> Dictionary:
	return {"id": id, "kind": "station", "wx": x, "wy": y, "radius": 110.0, "name_seed": rng.randi(), "spin": rng.randf_range(0.05, 0.15)}


## Simple loot roll: {item: count}.
static func roll_loot(table: String, rng: RandomNumberGenerator, mult := 1.0) -> Dictionary:
	var out := {}
	for entry in Config.get_v("loot." + table, []):
		if rng.randf() > float(entry.get("chance", 1.0)):
			continue
		var n := int(round(rng.randi_range(int(entry.get("min", 1)), int(entry.get("max", 1))) * mult))
		if n > 0:
			out[entry["item"]] = int(out.get(entry["item"], 0)) + n
	return out
