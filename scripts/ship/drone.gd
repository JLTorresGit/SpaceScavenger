extends Node2D
## Collector drone: flies to nearby drops, loads them into the ship's cargo,
## and returns to the ship when its battery time is over.

var ship
var universe
var target: Node2D = null
var life := 30.0
var velocity := Vector2.ZERO
var returning := false


func _ready() -> void:
	life = Config.fval("drones.duration", 30)


func _process(delta: float) -> void:
	if not is_instance_valid(ship) or ship.dead:
		queue_free()
		return
	life -= delta
	Game.energy -= Config.fval("drones.energy_per_sec", 0.5) * Game.consumption_mult() * delta
	if life <= 0.0 or Game.energy <= 0.0:
		returning = true
	var speed := Config.fval("drones.speed", 420)
	var goal: Vector2
	if returning:
		goal = ship.position
		if position.distance_to(goal) < 30.0:
			ship.drones.erase(self)
			queue_free()
			return
	else:
		if not is_instance_valid(target) or not universe.pickups.has(target.id):
			target = _find_target()
		goal = target.position if target else ship.position + Vector2(40, 0).rotated(life)
		if target and position.distance_to(target.position) < 16.0:
			ship.collect_pickup(target)
			target = null
	var desired: Vector2 = (goal - position).normalized() * speed + ship.velocity * 0.8
	velocity = velocity.move_toward(desired, speed * 4.0 * delta)
	position += velocity * delta
	queue_redraw()


func _find_target() -> Node2D:
	var best: Node2D = null
	var best_d := Config.fval("drones.range", 900)
	for p in universe.pickups.values():
		var claimed := false
		for d in ship.drones:
			if d != self and is_instance_valid(d) and d.target == p:
				claimed = true
		if claimed or p.cooldown > 0.0 or Game.space_for(p.item) <= 0:
			continue
		var dist: float = p.position.distance_to(ship.position)
		if dist < best_d:
			best = p
			best_d = dist
	return best


func _draw() -> void:
	draw_circle(Vector2.ZERO, 6.0, Color(0.6, 0.95, 0.8))
	draw_arc(Vector2.ZERO, 9.0, life, life + PI, 12, Color(0.3, 1.0, 0.7, 0.8), 2.0)
	if is_instance_valid(target):
		draw_line(Vector2.ZERO, target.position - position, Color(0.3, 1.0, 0.7, 0.25), 1.0)
