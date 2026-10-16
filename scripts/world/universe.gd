class_name Universe
extends Node2D
## Streams chunks and star systems around the ship, keeps a floating origin so
## coordinates stay small, owns all entity nodes and answers spatial queries.
## World coordinates (wx, wy) are 64-bit floats; node positions are relative to
## Game.origin_x/origin_y.

signal origin_shifted(delta: Vector2)
signal entity_spawned(node: Node2D)
signal teleported

const SCRIPTS := {
	"star": preload("res://scripts/entities/star.gd"),
	"planet": preload("res://scripts/entities/planet.gd"),
	"moon": preload("res://scripts/entities/planet.gd"),
	"asteroid": preload("res://scripts/entities/asteroid.gd"),
	"comet": preload("res://scripts/entities/asteroid.gd"),
	"derelict": preload("res://scripts/entities/derelict.gd"),
	"pickup": preload("res://scripts/entities/pickup.gd"),
	"station": preload("res://scripts/entities/station.gd"),
	"nebula": preload("res://scripts/entities/nebula.gd"),
	"ion_storm": preload("res://scripts/entities/ion_storm.gd"),
	"black_hole": preload("res://scripts/entities/black_hole.gd"),
	"wormhole": preload("res://scripts/entities/wormhole.gd"),
	"signal": preload("res://scripts/entities/beacon.gd"),
	"rescue_pod": preload("res://scripts/entities/beacon.gd"),
	"field": preload("res://scripts/entities/field_marker.gd"),
}

var ship: Node2D
var layer_back: Node2D      # nebulae, storms, fields
var layer_bodies: Node2D    # stars, planets, stations, debris
var layer_items: Node2D     # pickups, drones, effects

var entities := {}          # id -> node
var pickups := {}           # id -> node
var solids := {}            # id -> node (collidable)
var gravity_sources := {}   # id -> node
var hazards := {}           # id -> node (nebula, ion storm, black hole)
var groups := {}            # "c:x,y" / "s:x,y" -> Array of ids
var system_cache := {}      # "x,y" -> summary or {}
var _pending := {}          # group key -> true
var _results: Array = []    # [group key, Array of entity dicts]
var _mutex := Mutex.new()
var _tasks: Array = []
var _spawn_queue: Array = []
var _transient_counter := 0
var _transient_check := 0.0
var last_well_depth := 0.0  # 0..1 how deep the ship is in a gravity well


func _ready() -> void:
	layer_back = Node2D.new()
	layer_back.name = "Back"
	layer_bodies = Node2D.new()
	layer_bodies.name = "Bodies"
	layer_items = Node2D.new()
	layer_items.name = "Items"
	add_child(layer_back)
	add_child(layer_bodies)
	add_child(layer_items)


func _exit_tree() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


# --- Coordinates --------------------------------------------------------------

func to_local_pos(wx: float, wy: float) -> Vector2:
	return Vector2(wx - Game.origin_x, wy - Game.origin_y)


func world_x(p: Vector2) -> float:
	return Game.origin_x + p.x


func world_y(p: Vector2) -> float:
	return Game.origin_y + p.y


func shift_origin(delta: Vector2) -> void:
	Game.origin_x += delta.x
	Game.origin_y += delta.y
	for l in [layer_back, layer_bodies, layer_items]:
		for c in l.get_children():
			c.position -= delta
	ship.position -= delta
	origin_shifted.emit(delta)


## Jumps to world coordinates: clears everything and streams around the target.
func teleport(wx: float, wy: float) -> void:
	for id in entities.keys():
		entities[id].queue_free()
	for c in layer_items.get_children():
		c.queue_free()
	entities.clear()
	pickups.clear()
	solids.clear()
	gravity_sources.clear()
	hazards.clear()
	groups.clear()
	_pending.clear()
	_spawn_queue.clear()
	_mutex.lock()
	_results.clear()
	_mutex.unlock()
	Game.origin_x = wx
	Game.origin_y = wy
	ship.position = Vector2.ZERO
	_update_streaming(true)
	teleported.emit()


# --- Streaming ----------------------------------------------------------------

func _process(delta: float) -> void:
	if ship == null:
		return
	if ship.position.length() > Config.fval("world.origin_shift_threshold", 20000):
		shift_origin(ship.position)
	_reap_tasks()
	_collect_results()
	_update_streaming(false)
	_spawn_from_queue(Config.ival("world.max_spawns_per_frame", 60))
	_transient_check -= delta
	if _transient_check <= 0.0:
		_transient_check = 1.0
		_unload_far_transients()


func _update_streaming(immediate: bool) -> void:
	var size := Config.fval("world.chunk_size", 4000)
	var swx := world_x(ship.position)
	var swy := world_y(ship.position)
	var cx := floori(swx / size)
	var cy := floori(swy / size)
	var lr := Config.ival("world.load_radius_chunks", 2)
	var ur := Config.ival("world.unload_radius_chunks", 3)
	Game.visited[Generator.chunk_key(cx, cy)] = true
	for ox in range(-lr, lr + 1):
		for oy in range(-lr, lr + 1):
			_request("c:" + Generator.chunk_key(cx + ox, cy + oy), immediate)
	for key in groups.keys():
		if not key.begins_with("c:"):
			continue
		var parts: PackedStringArray = key.substr(2).split(",")
		if absi(int(parts[0]) - cx) > ur or absi(int(parts[1]) - cy) > ur:
			_unload_group(key)
	# Star systems
	var cell := Config.fval("world.system_cell_size", 50000)
	var sx := floori(swx / cell)
	var sy := floori(swy / cell)
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			var skey := Generator.system_key(sx + ox, sy + oy)
			if not system_cache.has(skey):
				system_cache[skey] = Generator.system_summary(Game.world_seed, sx + ox, sy + oy)
			var s: Dictionary = system_cache[skey]
			if s.is_empty():
				continue
			var d := Vector2(swx - s["wx"], swy - s["wy"]).length()
			if d < float(s["bounds"]) + Config.fval("world.system_load_margin", 9000):
				_request("s:" + skey, immediate)
	for key in groups.keys():
		if not key.begins_with("s:"):
			continue
		var s: Dictionary = system_cache.get(key.substr(2), {})
		if s.is_empty():
			continue
		var d := Vector2(swx - s["wx"], swy - s["wy"]).length()
		if d > float(s["bounds"]) + Config.fval("world.system_unload_margin", 14000):
			_unload_group(key)


func _request(key: String, immediate: bool) -> void:
	if groups.has(key) or _pending.has(key):
		return
	_pending[key] = true
	if immediate:
		_accept_result(key, _generate(key, Game.world_seed))
	else:
		_tasks.append(WorkerThreadPool.add_task(_generate_task.bind(key, Game.world_seed), false, "chunk " + key))


func _generate_task(key: String, world_seed: int) -> void:
	var data := _generate(key, world_seed)
	_mutex.lock()
	_results.append([key, data, world_seed])
	_mutex.unlock()


static func _generate(key: String, world_seed: int) -> Array:
	var parts: PackedStringArray = key.substr(2).split(",")
	var a := int(parts[0])
	var b := int(parts[1])
	if key.begins_with("c:"):
		return Generator.chunk_at(world_seed, a, b)
	var sys := Generator.system_at(world_seed, a, b)
	return sys.get("entities", [])


func _reap_tasks() -> void:
	var still: Array = []
	for t in _tasks:
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
		else:
			still.append(t)
	_tasks = still


func _collect_results() -> void:
	_mutex.lock()
	var batch := _results
	_results = []
	_mutex.unlock()
	for r in batch:
		if int(r[2]) != Game.world_seed:
			continue
		_accept_result(r[0], r[1])


func _accept_result(key: String, data: Array) -> void:
	if not _pending.has(key):
		return   # unloaded or teleported away meanwhile
	_pending.erase(key)
	groups[key] = []
	for d in data:
		if Game.removed.has(d["id"]):
			continue
		_spawn_queue.append([key, d])


func _spawn_from_queue(budget: int) -> void:
	while budget > 0 and not _spawn_queue.is_empty():
		var item: Array = _spawn_queue.pop_front()
		var key: String = item[0]
		var d: Dictionary = item[1]
		if not groups.has(key) or entities.has(d["id"]):
			continue
		spawn(d, key)
		budget -= 1


## Flushes the whole spawn queue (used after loading or teleporting).
func flush_spawns() -> void:
	_collect_results()
	_spawn_from_queue(1 << 30)


func _unload_group(key: String) -> void:
	for id in groups[key]:
		if entities.has(id):
			var node: Node2D = entities[id]
			# Persistent pickups that drifted far are dropped with the chunk;
			# anything currently held by the tractor stays with its group.
			_forget(id)
			node.queue_free()
	groups.erase(key)


func _unload_far_transients() -> void:
	var limit := Config.fval("world.transient_unload_distance", 16000)
	for id in entities.keys():
		var node = entities[id]
		if node.group_key == "transient" and node.position.distance_to(ship.position) > limit:
			_forget(id)
			node.queue_free()


# --- Spawning / removal -------------------------------------------------------

func spawn(d: Dictionary, group_key: String) -> Node2D:
	var script: Script = SCRIPTS.get(str(d["kind"]))
	if script == null:
		push_warning("Unknown entity kind " + str(d["kind"]))
		return null
	var node: Node2D = script.new()
	node.universe = self
	node.group_key = group_key
	node.setup(d)
	node.position = to_local_pos(float(d["wx"]), float(d["wy"]))
	match node.layer:
		"back": layer_back.add_child(node)
		"items": layer_items.add_child(node)
		_: layer_bodies.add_child(node)
	entities[node.id] = node
	if groups.has(group_key):
		groups[group_key].append(node.id)
	if node.kind == "pickup":
		pickups[node.id] = node
	if node.collidable:
		solids[node.id] = node
	if node.has_gravity:
		gravity_sources[node.id] = node
	if node.is_hazard:
		hazards[node.id] = node
	entity_spawned.emit(node)
	return node


## Spawns a non-persistent entity at a local position (fragments, loot, jettison).
func spawn_transient(d: Dictionary, local_pos: Vector2) -> Node2D:
	_transient_counter += 1
	d["id"] = "t%d" % _transient_counter
	d["wx"] = world_x(local_pos)
	d["wy"] = world_y(local_pos)
	d["persistent"] = false
	return spawn(d, "transient")


func spawn_pickup(item_id: String, n: int, local_pos: Vector2, vel := Vector2.ZERO) -> Node2D:
	var p := spawn_transient({"kind": "pickup", "item": item_id, "count": n}, local_pos)
	if p:
		p.velocity = vel
	return p


## Scatters loot as pickups around a position, in stacks of up to 3.
func drop_loot(loot: Dictionary, local_pos: Vector2, spread: float) -> void:
	for item_id in loot.keys():
		var left: int = loot[item_id]
		while left > 0:
			var n := mini(3, left)
			left -= n
			var ang := randf() * TAU
			var off := Vector2(cos(ang), sin(ang)) * randf() * spread
			spawn_pickup(item_id, n, local_pos + off, off.normalized() * randf_range(10, 45))


func remove_entity(node: Node2D, persistent: bool) -> void:
	if persistent and node.persistent:
		Game.removed[node.id] = true
	_forget(node.id)
	node.queue_free()


func _forget(id: String) -> void:
	entities.erase(id)
	pickups.erase(id)
	solids.erase(id)
	gravity_sources.erase(id)
	hazards.erase(id)


# --- Queries ------------------------------------------------------------------

## Sum of gravitational accelerations at a local position. Also updates
## last_well_depth (0..1) for the gravity-assist bonus.
func gravity_at(p: Vector2) -> Vector2:
	var acc := Vector2.ZERO
	var depth := 0.0
	for src in gravity_sources.values():
		var d: Vector2 = src.position - p
		var r := d.length()
		if r >= src.influence or r < 1.0:
			continue
		var r_eff := maxf(r, src.radius)
		acc += d / r * src.surface_g * pow(src.radius / r_eff, 2)
		depth = maxf(depth, 1.0 - (r - src.radius) / maxf(src.influence - src.radius, 1.0))
	last_well_depth = clampf(depth, 0.0, 1.0)
	return acc


## Entity under a local point, preferring the smallest one (clicks, scans).
func entity_at(p: Vector2, extra := 20.0) -> Node2D:
	var best: Node2D = null
	for e in entities.values():
		if not e.selectable:
			continue
		if e.position.distance_to(p) <= e.radius + extra and (best == null or e.radius < best.radius):
			best = e
	return best


func entities_within(p: Vector2, r: float) -> Array:
	var out: Array = []
	for e in entities.values():
		if e.position.distance_to(p) <= r + e.radius:
			out.append(e)
	return out


## First solid/minable entity hit by a ray. Returns [node, distance] or [].
func raycast(from: Vector2, dir: Vector2, max_len: float) -> Array:
	var best: Array = []
	for e in solids.values():
		if not e.minable:
			continue
		var to: Vector2 = e.position - from
		var t := to.dot(dir)
		if t < 0 or t > max_len + e.radius:
			continue
		var perp := (to - dir * t).length()
		if perp > e.radius:
			continue
		var hit := t - sqrt(maxf(e.radius * e.radius - perp * perp, 0.0))
		if hit <= max_len and (best.is_empty() or hit < best[1]):
			best = [e, maxf(hit, 0.0)]
	return best
