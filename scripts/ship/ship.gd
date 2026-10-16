class_name Ship
extends Node2D
## Player vessel: Newtonian-lite flight, warp, autopilot, salvage laser,
## tractor beam, proximity collection, scanning, drones, docking, environmental
## damage and resource consumption. Persistent values live in the Game autoload.

signal destroyed
signal docked(station: Node2D)
signal scan_finished(info: Dictionary)

const DRONE_SCRIPT := preload("res://scripts/ship/drone.gd")

var universe: Universe
var heading := -PI / 2.0
var velocity := Vector2.ZERO
var radius := 18.0

var warp := false
var autopilot := false
var main_thrust := 0.0      # 0..1 for the flame
var retro_thrust := 0.0
var strafe := 0.0
var laser_on := false
var laser_end := Vector2.ZERO
var tractor_on := false
var tractored: Array = []
var in_nebula := false
var in_storm := false
var heat_level := 0.0
var scoop_level := 0.0
var sensors_online := true
var life_support_failing := false
var near_station: Node2D = null
var hint := ""

var scanning := 0.0
var scan_target: Node2D = null
var drones: Array = []
var dead := false
var death_t := 0.0
var shield_delay := 0.0
var since_damage := 99.0
var hit_flash := 0.0
var wormhole_cooldown := 0.0
var rate_fuel := 0.0
var rate_energy := 0.0
var _discover_t := 0.0
var _cargo_msg_t := 0.0
var invulnerable := false     # test/debug only (autotest)


func _ready() -> void:
	add_to_group("save_hooks")
	radius = Game.stat("radius") if Game.stat("radius") > 0 else 18.0


func _before_save() -> void:
	Game.ship_state = {"wx": universe.world_x(position), "wy": universe.world_y(position),
		"vx": velocity.x, "vy": velocity.y, "rot": heading}


func restore_from_state() -> void:
	var s := Game.ship_state
	heading = float(s.get("rot", -PI / 2.0))
	velocity = Vector2(float(s.get("vx", 0.0)), float(s.get("vy", 0.0)))


func s(key: String) -> float:
	return Game.stat(key)


# --- Main loop ------------------------------------------------------------------

func _process(delta: float) -> void:
	if dead:
		death_t += delta
		queue_redraw()
		return
	var dt := minf(delta, 0.05)
	var fuel_before := Game.fuel
	var energy_before := Game.energy
	Game.play_time += dt
	Game.stat_add("play_time", dt)
	_flight(dt)
	_collisions()
	_environment(dt)
	_systems(dt)
	_tools(dt)
	_collect(dt)
	_actions()
	_timers(dt)
	Game.process_research(dt)
	_clamp_resources()
	rate_fuel = lerpf(rate_fuel, (Game.fuel - fuel_before) / dt, 0.1)
	rate_energy = lerpf(rate_energy, (Game.energy - energy_before) / dt, 0.1)
	if Game.hull <= 0.0:
		die()
	queue_redraw()


# --- Flight ---------------------------------------------------------------------

func propellant() -> float:
	return Game.energy if Game.engine_mode == "energy" else Game.fuel


func _consume_propellant(amount: float) -> void:
	if Game.engine_mode == "energy":
		Game.energy -= amount * s("ion_cost_factor")
	else:
		Game.fuel -= amount
		Game.stat_add("fuel_burned", amount)


func _flight(dt: float) -> void:
	var rot_in := Input.get_axis("rotate_left", "rotate_right")
	var thr := Input.get_action_strength("thrust")
	var retro := Input.get_action_strength("retro")
	strafe = Input.get_axis("strafe_left", "strafe_right")
	if absf(rot_in) > 0.1 or thr > 0.1 or retro > 0.1 or absf(strafe) > 0.1:
		if autopilot:
			Game.notify("Autopilot disengaged (manual control).")
		autopilot = false
	if autopilot:
		var ap := _autopilot_input()
		rot_in = ap.x
		thr = ap.y
	heading = wrapf(heading + rot_in * s("rotation_speed") * dt, -PI, PI)

	var has_prop := propellant() > 0.0
	warp = Input.is_action_pressed("warp") and has_prop
	var forward := Vector2.from_angle(heading)
	var right := Vector2(-forward.y, forward.x)
	var accel := Vector2.ZERO
	var cmult := Game.consumption_mult()
	if has_prop:
		var mult := s("warp_thrust_multiplier") if warp else 1.0
		accel += forward * s("thrust") * mult * thr
		accel -= forward * s("thrust") * s("retro_factor") * retro
		accel += right * s("rcs_thrust") * strafe
		var efficiency := 1.0 - s("gravity_assist_efficiency") * universe.last_well_depth
		var burn := (thr + retro * s("retro_factor")) * s("fuel_burn_per_sec") * efficiency
		if warp:
			burn += s("warp_fuel_burn_per_sec")
		_consume_propellant(burn * cmult * dt)
		Game.energy -= absf(strafe) * s("rcs_energy_per_sec") * cmult * dt
		main_thrust = thr
		retro_thrust = retro
	else:
		# Out of propellant: weak RCS thrusters only (emergency drift control).
		accel += (forward * (thr - retro) + right * strafe) * s("rcs_thrust")
		Game.energy -= (thr + retro + absf(strafe)) * s("rcs_energy_per_sec") * cmult * dt
		main_thrust = 0.0
		retro_thrust = 0.0
	accel += universe.gravity_at(position)
	velocity += accel * dt
	var cap := s("warp_max_speed") if warp else s("max_speed")
	var speed := velocity.length()
	if speed > cap:
		velocity = velocity / speed * lerpf(speed, cap, 1.0 - exp(-s("overspeed_decay") * dt))
	var step := velocity * dt
	position += step
	Game.stat_add("distance_traveled", step.length())


## Returns Vector2(rotation input, thrust input) steering toward the target.
func _autopilot_input() -> Vector2:
	var tpos: Variant = target_local_pos()
	if tpos == null:
		autopilot = false
		return Vector2.ZERO
	var to: Vector2 = tpos - position
	var dist := to.length()
	var arrive := float(Game.target.get("radius", 0.0)) + s("autopilot_arrive_margin")
	if dist < arrive and velocity.length() < 60.0:
		autopilot = false
		Game.notify("Arrived: " + str(Game.target.get("name", "waypoint")), "good")
		return Vector2.ZERO
	var dir := to / maxf(dist, 1.0)
	dir = _avoid_bodies(dir, dist)
	var brake_accel := s("thrust") * 0.45
	var desired_speed := minf(s("warp_max_speed") if warp else s("max_speed"), sqrt(2.0 * brake_accel * maxf(dist - arrive * 0.6, 0.0)))
	var dv := dir * desired_speed - velocity
	if dv.length() < 12.0:
		return Vector2.ZERO
	var diff := wrapf(dv.angle() - heading, -PI, PI)
	var rot := clampf(diff * 3.0, -1.0, 1.0)
	var thr := 1.0 if absf(diff) < 0.3 else 0.0
	return Vector2(rot, thr * clampf(dv.length() / 80.0, 0.3, 1.0))


## Steers around stars and planets that sit on the straight path to the target.
func _avoid_bodies(dir: Vector2, dist: float) -> Vector2:
	for b in universe.gravity_sources.values():
		if b.id == Game.target.get("id", ""):
			continue
		var keep: float = b.heat_radius * 1.15 if b.kind == "star" else b.radius * 1.8
		if b.kind == "black_hole":
			keep = b.influence * 0.35
		var to_b: Vector2 = b.position - position
		var t := to_b.dot(dir)
		if t < 0.0 or t > dist:
			continue
		var perp := to_b - dir * t
		if perp.length() < keep:
			var side := -perp.normalized() if perp.length() > 1.0 else Vector2(-dir.y, dir.x)
			var waypoint: Vector2 = b.position + side * keep * 1.3
			return (waypoint - position).normalized()
	return dir


func target_local_pos() -> Variant:
	if Game.target.is_empty():
		return null
	var tid := str(Game.target.get("id", ""))
	if tid != "" and universe.entities.has(tid):
		return universe.entities[tid].position
	return universe.to_local_pos(float(Game.target["wx"]), float(Game.target["wy"]))


func target_distance() -> float:
	var p: Variant = target_local_pos()
	return -1.0 if p == null else position.distance_to(p)


## Rough fuel needed to reach the target: accelerate, coast, brake.
func estimate_trip_fuel(dist: float) -> float:
	var v := minf(s("max_speed"), sqrt(dist * s("thrust") * 0.45))
	var t_burn := 2.0 * v / maxf(s("thrust"), 1.0)
	return t_burn * s("fuel_burn_per_sec") * Game.consumption_mult()


func engage_autopilot() -> void:
	if not Game.target.is_empty():
		autopilot = true


# --- Collisions -----------------------------------------------------------------

func _collisions() -> void:
	for e in universe.solids.values():
		var d: Vector2 = position - e.position
		var min_d: float = e.radius + radius
		var dl := d.length()
		if dl >= min_d or dl < 0.001:
			continue
		var n := d / dl
		position = e.position + n * min_d
		var rel: Vector2 = velocity - e.velocity
		var vn := rel.dot(n)
		if vn < 0.0:
			var impact := -vn
			if impact > s("collision_safe_speed"):
				apply_damage(minf((impact - s("collision_safe_speed")) * s("collision_damage_factor"), s("collision_max_damage")), "impact")
			velocity -= n * vn * (1.0 + s("collision_restitution"))
			if e.kind == "asteroid" or e.kind == "comet":
				e.velocity += n * vn * clampf(20.0 / e.radius, 0.05, 0.6)


# --- Environment: heat, gravity hazards, nebulae, storms, contacts -------------

func _environment(dt: float) -> void:
	heat_level = 0.0
	scoop_level = 0.0
	for src in universe.gravity_sources.values():
		var d: float = position.distance_to(src.position)
		if src.kind == "star":
			if d < src.heat_radius:
				var intensity := clampf((src.heat_radius - d) / maxf(src.heat_radius - src.radius, 1.0), 0.0, 1.0)
				intensity *= intensity
				heat_level = maxf(heat_level, intensity * src.heat_multiplier())
				var resist := clampf(s("heat_resistance"), 0.0, 0.95)
				apply_damage(Config.fval("heat.max_damage_per_sec", 45) * intensity * src.heat_multiplier() * (1.0 - resist) * dt, "heat")
			var scoop_r: float = src.heat_radius * Config.fval("heat.scoop_radius_factor", 1.5)
			if d < scoop_r and s("scoop_rate") > 0.0:
				scoop_level = maxf(scoop_level, clampf((scoop_r - d) / maxf(scoop_r - src.radius, 1.0), 0.0, 1.0))
			if d < src.heat_radius * 1.6 and src.flare_incoming() and not src.flare_warned:
				src.flare_warned = true
				Game.notify("Solar flare imminent! Move away from " + src.display_name(), "danger")
		elif src.kind == "black_hole" and d < src.damage_radius():
			apply_damage(Config.fval("hazards.black_hole.damage_per_sec", 80) * dt, "gravity")
	in_nebula = false
	in_storm = false
	for h in universe.hazards.values():
		var d: float = position.distance_to(h.position)
		if d > h.radius:
			continue
		if h.kind == "nebula":
			in_nebula = true
		elif h.kind == "ion_storm":
			in_storm = true
			Game.energy -= Config.fval("hazards.ion_storm.energy_drain_per_sec", 4) * Game.consumption_mult() * dt
	# Contact triggers (wormholes, signals, pods) and docking range.
	near_station = null
	for e in universe.entities.values():
		if not is_instance_valid(e):
			continue
		var d: float = position.distance_to(e.position)
		if e.kind == "station" and d < Config.fval("ship.dock_range", 260):
			near_station = e
		elif (e.kind == "wormhole" or e.kind == "signal" or e.kind == "rescue_pod") and d < e.radius + radius:
			e.on_ship_contact(self)
			break


# --- Ship systems: energy, shields, converter, scoop, regen ---------------------

func _systems(dt: float) -> void:
	var cmult := Game.consumption_mult()
	Game.energy -= (s("life_support_drain") + s("sensor_drain") + Game.module_energy_drain()) * cmult * dt
	if s("scoop_rate") > 0.0 and scoop_level > 0.0:
		Game.energy += s("scoop_rate") * scoop_level * dt
	if s("converter_rate") > 0.0 and Game.energy < s("energy_capacity") * 0.9 and Game.fuel > 0.0:
		var c := minf(s("converter_rate") * dt, Game.fuel)
		Game.fuel -= c
		Game.energy += c * s("converter_ratio")
	if shield_delay > 0.0:
		shield_delay -= dt
	elif Game.shield < s("shield_max") and Game.energy > 0.0:
		var regen := s("shield_regen_per_sec") * dt
		if in_nebula:
			regen *= Config.fval("hazards.nebula.shield_regen_multiplier", 2.5)
		regen = minf(regen, s("shield_max") - Game.shield)
		Game.shield += regen
		Game.energy -= regen * s("shield_regen_energy_per_point") * cmult
	if s("hull_regen_per_sec") > 0.0:
		Game.hull = minf(s("hull_max"), Game.hull + s("hull_regen_per_sec") * dt)
	sensors_online = Game.energy > 0.0
	life_support_failing = Game.energy <= 0.0
	if life_support_failing and not invulnerable:
		Game.hull -= s("life_support_failure_damage") * Game.damage_mult() * dt


func _clamp_resources() -> void:
	Game.fuel = clampf(Game.fuel, 0.0, s("fuel_capacity"))
	Game.energy = clampf(Game.energy, 0.0, s("energy_capacity"))
	Game.shield = clampf(Game.shield, 0.0, s("shield_max"))
	Game.hull = clampf(Game.hull, 0.0, s("hull_max"))


func radar_range_now() -> float:
	if not sensors_online:
		return 0.0
	return s("radar_range") * (Config.fval("hazards.nebula.radar_multiplier", 0.35) if in_nebula else 1.0)


func apply_damage(amount: float, _source: String) -> void:
	if amount <= 0.0 or dead or invulnerable:
		return
	amount *= Game.damage_mult()
	if Game.shield > 0.0:
		var absorbed := minf(Game.shield, amount)
		Game.shield -= absorbed
		amount -= absorbed
	Game.hull -= amount
	shield_delay = s("shield_regen_delay")
	since_damage = 0.0
	hit_flash = 0.15


# --- Tools: laser, tractor, scanner, drones --------------------------------------

func tools_allowed() -> bool:
	return not warp and Game.energy > 0.0


func _tools(dt: float) -> void:
	var cmult := Game.consumption_mult()
	laser_on = Input.is_action_pressed("laser") and tools_allowed()
	if laser_on:
		var aim := get_global_mouse_position() - position
		var dir := aim.normalized() if aim.length() > 1.0 else Vector2.from_angle(heading)
		var hit := universe.raycast(position, dir, s("laser_range"))
		if hit.is_empty():
			laser_end = position + dir * s("laser_range")
		else:
			laser_end = position + dir * float(hit[1])
			hit[0].take_damage(s("laser_dps") * dt)
		Game.energy -= s("laser_energy_per_sec") * cmult * dt
	tractor_on = Input.is_action_pressed("tractor") and tools_allowed()
	tractored.clear()
	if tractor_on:
		Game.energy -= s("tractor_energy_per_sec") * cmult * dt
		var rng_t := s("tractor_range")
		for p in universe.pickups.values():
			var to_ship: Vector2 = position - p.position
			var d := to_ship.length()
			if d > rng_t or d < 0.01:
				continue
			var desired := velocity + to_ship / d * minf(380.0, d * 3.0)
			p.velocity = p.velocity.move_toward(desired, s("tractor_strength") * dt)
			tractored.append(p)
	if scanning > 0.0:
		scanning -= dt
		if not is_instance_valid(scan_target):
			scanning = 0.0
		elif scanning <= 0.0:
			_finish_scan()


func start_scan() -> void:
	if scanning > 0.0:
		return
	var t := _pick_scan_target()
	if t == null:
		Game.notify("Nothing to scan within %d u." % int(s("scan_range")))
		return
	if Game.energy < s("scan_energy"):
		Game.notify("Not enough energy to scan.", "warning")
		return
	Game.energy -= s("scan_energy")
	scan_target = t
	scanning = s("scan_time")


func _pick_scan_target() -> Node2D:
	var range_ := s("scan_range")
	var tid := str(Game.target.get("id", ""))
	if tid != "" and universe.entities.has(tid):
		var t: Node2D = universe.entities[tid]
		if t.position.distance_to(position) - t.radius <= range_:
			return t
	var under := universe.entity_at(get_global_mouse_position(), 30.0)
	if under and under.kind != "pickup" and under.position.distance_to(position) - under.radius <= range_:
		return under
	var best: Node2D = null
	var best_d := INF
	for e in universe.entities.values():
		if e.kind == "pickup" or not e.selectable:
			continue
		var d: float = e.position.distance_to(position) - e.radius
		if d <= range_ and d < best_d:
			best = e
			best_d = d
	return best


func _finish_scan() -> void:
	var info: Dictionary = scan_target.scan_info()
	if not Game.scanned.has(scan_target.id):
		Game.scanned[scan_target.id] = true
		Game.data_points += int(info.get("data", 0))
		Game.stat_add("scans")
		if Game.discoveries.has(scan_target.id):
			Game.discoveries[scan_target.id]["notes"] = info.get("lines", [])
		info["new"] = true
	scan_finished.emit(info)


func launch_drones() -> void:
	var n := int(s("drone_count"))
	if n <= 0:
		Game.notify("No drone bay installed.", "warning")
		return
	if not drones.is_empty():
		Game.notify("Drones already deployed.")
		return
	for i in n:
		var drone: Node2D = DRONE_SCRIPT.new()
		drone.ship = self
		drone.universe = universe
		drone.position = position + Vector2.from_angle(TAU * i / n) * 30.0
		universe.layer_items.add_child(drone)
		drones.append(drone)
	Game.notify("%d collector drones launched." % n)


# --- Collection ---------------------------------------------------------------

func _collect(dt: float) -> void:
	_cargo_msg_t -= dt
	var prox := s("proximity_range")
	var grab := s("collect_radius")
	for p in universe.pickups.values():
		if p.cooldown > 0.0:
			continue
		var d: float = position.distance_to(p.position)
		var ok: bool = (not p.large and d < prox) or (d < grab and (not p.large or tractor_on))
		if ok:
			collect_pickup(p)


func collect_pickup(p: Node2D) -> bool:
	var added := Game.add_item(p.item, p.amount)
	if added > 0:
		Game.stat_add("items_collected", added)
	if added >= p.amount:
		universe.remove_entity(p, true)
		return true
	p.amount -= added
	p.queue_redraw()
	if _cargo_msg_t <= 0.0:
		_cargo_msg_t = 3.0
		var reason := Game.cargo_limit_reason(p.item)
		Game.notify("Cargo full (%s limit). Jettison or craft to free space." % (reason if reason != "" else "capacity"), "warning")
	return false


# --- Actions (single key presses) --------------------------------------------------

func _actions() -> void:
	hint = ""
	if near_station:
		if velocity.length() <= s("dock_max_speed"):
			hint = "Press %s to dock at %s" % [Config.binding_text("interact"), near_station.display_name()]
			if Input.is_action_just_pressed("interact"):
				velocity = Vector2.ZERO
				autopilot = false
				docked.emit(near_station)
		else:
			hint = "Slow down below %d u/s to dock" % int(s("dock_max_speed"))
	if Input.is_action_just_pressed("scan"):
		start_scan()
	if Input.is_action_just_pressed("drones"):
		launch_drones()
	if Input.is_action_just_pressed("refuel"):
		Game.use_best("fuel")
	if Input.is_action_just_pressed("recharge"):
		Game.use_best("energy")
	if Input.is_action_just_pressed("repair"):
		Game.use_best("hull")


func _timers(dt: float) -> void:
	since_damage += dt
	hit_flash = maxf(hit_flash - dt, 0.0)
	wormhole_cooldown = maxf(wormhole_cooldown - dt, 0.0)
	var dist_origin := Vector2(universe.world_x(position), universe.world_y(position)).length()
	Game.stat_max("max_distance", dist_origin)
	_discover_t -= dt
	if _discover_t <= 0.0:
		_discover_t = 0.25
		_check_discoveries()
	if not Game.active_rescue.is_empty():
		Game.active_rescue["remaining"] = float(Game.active_rescue["remaining"]) - dt
		if Game.active_rescue["remaining"] <= 0.0:
			var pid := str(Game.active_rescue["id"])
			Game.removed[pid] = true
			if universe.entities.has(pid):
				universe.remove_entity(universe.entities[pid], true)
			Game.active_rescue = {}
			Game.notify("Lost contact with the escape pod.", "danger")


func _check_discoveries() -> void:
	for e in universe.entities.values():
		if not e.discoverable or Game.is_discovered(e.id):
			continue
		if position.distance_to(e.position) <= e.discovery_range():
			Game.add_discovery(e.discovery_entry())
			if e.has_method("on_discovered"):
				e.on_discovered()


# --- Travel ---------------------------------------------------------------------

func enter_wormhole(w: Node2D) -> void:
	if wormhole_cooldown > 0.0:
		return
	wormhole_cooldown = 3.0
	var dx := float(w.data["dest_wx"])
	var dy := float(w.data["dest_wy"])
	Game.stat_add("wormholes_used")
	Game.notify("Wormhole transit complete. %d k u from the entry point." % int(Vector2(dx - w.wx(), dy - w.wy()).length() / 1000.0), "good")
	velocity *= 0.3
	autopilot = false
	universe.call_deferred("teleport", dx, dy)


func quick_travel_cost(wx: float, wy: float) -> Dictionary:
	var d := Vector2(wx - universe.world_x(position), wy - universe.world_y(position)).length()
	return {"distance": d, "fuel": d / 1000.0 * s("quick_travel_fuel_per_1000") * Game.consumption_mult(),
		"energy": s("quick_travel_energy"), "max": s("quick_travel_max_distance")}


## Returns "" on success or the reason it is not possible.
func quick_travel_block_reason(entry: Dictionary) -> String:
	var c := quick_travel_cost(float(entry["wx"]), float(entry["wy"]))
	if c["distance"] > c["max"]:
		return "Out of range (%d k / max %d k)" % [int(c["distance"] / 1000.0), int(c["max"] / 1000.0)]
	if Game.fuel < c["fuel"]:
		return "Needs %.1f fuel" % c["fuel"]
	if Game.energy < c["energy"]:
		return "Needs %d energy" % int(c["energy"])
	return ""


func quick_travel(entry: Dictionary) -> bool:
	var reason := quick_travel_block_reason(entry)
	if reason != "":
		Game.notify("Quick travel: " + reason, "warning")
		return false
	var c := quick_travel_cost(float(entry["wx"]), float(entry["wy"]))
	Game.fuel -= c["fuel"]
	Game.energy -= c["energy"]
	Game.stat_add("quick_travels")
	var offset := float(entry.get("radius", 50.0)) + 450.0
	if str(entry.get("kind", "")) == "star":
		offset = float(entry.get("radius", 400)) * 4.5
	velocity = Vector2.ZERO
	autopilot = false
	universe.teleport(float(entry["wx"]) + offset, float(entry["wy"]))
	Game.notify("Quick travel to %s (−%.1f fuel)." % [entry.get("name", "target"), c["fuel"]], "good")
	return true


# --- Death ------------------------------------------------------------------------

func die() -> void:
	if dead:
		return
	dead = true
	death_t = 0.0
	velocity = Vector2.ZERO
	autopilot = false
	for d in drones:
		if is_instance_valid(d):
			d.queue_free()
	drones.clear()
	Game.stat_add("deaths")
	destroyed.emit()


# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
	if dead:
		var t := death_t
		for i in 4:
			var r := (t * 260.0) * (1.0 - i * 0.18)
			draw_circle(Vector2.ZERO, r, Color(1.0, 0.6 - i * 0.1, 0.2, maxf(0.0, 0.5 - t * 0.25)))
		return
	if tractor_on:
		draw_arc(Vector2.ZERO, s("tractor_range"), 0, TAU, 48, Color(0.5, 0.9, 1.0, 0.25), 1.5, true)
		for p in tractored:
			if is_instance_valid(p):
				draw_line(Vector2.ZERO, p.position - position, Color(0.5, 0.9, 1.0, 0.5), 2.0, true)
	if laser_on:
		var end := laser_end - position
		draw_line(Vector2.ZERO, end, Color(1.0, 0.3, 0.25, 0.35), 7.0, true)
		draw_line(Vector2.ZERO, end, Color(1.0, 0.85, 0.7), 2.0, true)
		draw_circle(end, 6.0, Color(1.0, 0.7, 0.4, 0.8))
	if scanning > 0.0 and is_instance_valid(scan_target):
		var frac := 1.0 - scanning / maxf(s("scan_time"), 0.01)
		var tp: Vector2 = scan_target.position - position
		draw_arc(tp, scan_target.radius + 20.0, 0, TAU * frac, 48, Color(0.4, 1.0, 0.8, 0.9), 3.0, true)
		draw_line(Vector2.ZERO, tp, Color(0.4, 1.0, 0.8, 0.25), 1.0)
	if warp:
		var back := -velocity.normalized() if velocity.length() > 1.0 else -Vector2.from_angle(heading)
		var side := Vector2(-back.y, back.x)
		for i in 7:
			var o := side * (i - 3) * 9.0
			draw_line(o + back * 20.0, o + back * (90.0 + (i % 3) * 40.0), Color(0.6, 0.8, 1.0, 0.45), 2.0)
	if Game.shield > 0.0:
		var a := 0.08 + 0.12 * Game.shield / maxf(s("shield_max"), 1.0) + hit_flash * 2.0
		draw_circle(Vector2.ZERO, radius * 1.7, Color(Game.pal("shield"), a * 0.5))
		draw_arc(Vector2.ZERO, radius * 1.7, 0, TAU, 32, Color(Game.pal("shield"), a + 0.1), 1.5, true)
	draw_set_transform(Vector2.ZERO, heading, Vector2.ONE)
	if main_thrust > 0.05:
		var l := 14.0 + 22.0 * main_thrust * (2.0 if warp else 1.0) + randf() * 6.0
		draw_colored_polygon(PackedVector2Array([Vector2(-10, -6), Vector2(-10 - l, 0), Vector2(-10, 6)]), Color(1.0, 0.6, 0.2, 0.9))
		draw_colored_polygon(PackedVector2Array([Vector2(-10, -3), Vector2(-10 - l * 0.6, 0), Vector2(-10, 3)]), Color(1.0, 0.95, 0.7))
	if retro_thrust > 0.05:
		draw_line(Vector2(16, -7), Vector2(26, -11), Color(1, 0.8, 0.5), 2.0)
		draw_line(Vector2(16, 7), Vector2(26, 11), Color(1, 0.8, 0.5), 2.0)
	if absf(strafe) > 0.05:
		var sy := -1.0 if strafe > 0 else 1.0
		draw_line(Vector2(0, 10 * sy), Vector2(0, 18 * sy), Color(1, 0.9, 0.7), 2.0)
	var hull_pts := PackedVector2Array([Vector2(22, 0), Vector2(-12, -13), Vector2(-7, 0), Vector2(-12, 13)])
	var body := Color(0.82, 0.9, 1.0) if hit_flash <= 0.0 else Color(1, 0.6, 0.5)
	draw_colored_polygon(hull_pts, body)
	draw_polyline(SpaceEntity.closed(hull_pts), Color(0.35, 0.75, 1.0), 2.0, true)
	draw_circle(Vector2(6, 0), 4.0, Color(0.3, 0.7, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
