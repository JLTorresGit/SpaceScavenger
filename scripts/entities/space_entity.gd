class_name SpaceEntity
extends Node2D
## Base class for everything that lives in the universe. Entities are built
## from generator dictionaries and draw themselves with vector shapes.

var universe
var group_key := ""
var data: Dictionary = {}
var id := ""
var kind := ""
var radius := 10.0
var layer := "bodies"         # back | bodies | items
var persistent := true
var collidable := false       # ship bounces off it
var minable := false          # salvage laser can damage it
var selectable := true        # can be clicked / targeted
var discoverable := false     # appears in the codex when found
var is_hazard := false
var has_gravity := false
var surface_g := 0.0
var influence := 0.0
var hp := 0.0
var max_hp := 0.0
var velocity := Vector2.ZERO
var _hit_flash := 0.0


func setup(d: Dictionary) -> void:
	data = d
	id = str(d["id"])
	kind = str(d["kind"])
	radius = float(d.get("radius", 10.0))
	persistent = bool(d.get("persistent", true))
	velocity = Vector2(float(d.get("vx", 0.0)), float(d.get("vy", 0.0)))
	_setup()


func _setup() -> void:
	pass


func wx() -> float:
	return Game.origin_x + position.x


func wy() -> float:
	return Game.origin_y + position.y


func default_name() -> String:
	return kind.capitalize()


func display_name() -> String:
	return Game.name_of(id, default_name())


## Range at which flying close adds this entity to the codex.
func discovery_range() -> float:
	var ranges := Config.dict("discovery.range")
	return radius + float(ranges.get(kind, ranges.get("default", 1000)))


func discovery_entry() -> Dictionary:
	return {"id": id, "kind": kind, "name": display_name(), "wx": wx(), "wy": wy(), "radius": radius,
		"subtype": str(data.get("subtype", data.get("ptype", data.get("class", ""))))}


## Called by the ship scanner. Returns {"title", "lines": [...], "data": points}.
func scan_info() -> Dictionary:
	return {"title": display_name(), "lines": [], "data": int(Config.dict("discovery.data_value").get(kind, 2))}


func take_damage(amount: float) -> void:
	if not minable:
		return
	hp -= amount
	_hit_flash = 0.12
	if hp <= 0.0:
		_destroyed()


func _destroyed() -> void:
	universe.remove_entity(self, true)


## Called every frame while the ship overlaps (distance < radius + ship radius).
func on_ship_contact(_ship) -> void:
	pass


func radar_color() -> Color:
	return Config.color(Config.dict("radar_colors").get(kind, [0.8, 0.8, 0.8]))


## Polygon of n points around the origin with deterministic roughness.
static func rough_polygon(seed_value: int, r: float, n: int, roughness: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.15, 0.15)
		pts.append(Vector2(cos(a), sin(a)) * r * rng.randf_range(1.0 - roughness, 1.0 + roughness * 0.3))
	return pts


static func closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out
