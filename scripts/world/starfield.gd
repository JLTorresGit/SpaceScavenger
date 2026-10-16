extends Node2D
## Screen-space parallax starfield (three depth layers), tiled infinitely and
## driven by the camera's world position. Adds warp streaks while warping.

const TILE := 1024.0

var camera: Camera2D
var ship
var layers: Array = []   # {factor, stars: [[Vector2, size, Color]]}


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	for spec in [[0.03, 150, 1.0], [0.08, 90, 1.6], [0.18, 45, 2.2]]:
		var stars: Array = []
		for i in spec[1]:
			var tint := Color.from_hsv(rng.randf_range(0.55, 0.7) if rng.randf() < 0.7 else rng.randf_range(0.05, 0.15), rng.randf_range(0.0, 0.35), 1.0, rng.randf_range(0.35, 0.95))
			stars.append([Vector2(rng.randf() * TILE, rng.randf() * TILE), spec[2] * rng.randf_range(0.6, 1.3), tint])
		layers.append({"factor": spec[0], "stars": stars})


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if camera == null:
		return
	var vs := get_viewport_rect().size
	var cx := Game.origin_x + camera.position.x
	var cy := Game.origin_y + camera.position.y
	for l in layers:
		var f: float = l["factor"]
		var off := Vector2(fposmod(-cx * f, TILE), fposmod(-cy * f, TILE))
		var nx := int(ceil(vs.x / TILE)) + 1
		var ny := int(ceil(vs.y / TILE)) + 1
		for tx in range(-1, nx):
			for ty in range(-1, ny):
				var base := Vector2(tx * TILE, ty * TILE) + off
				for st in l["stars"]:
					var p: Vector2 = base + st[0]
					if p.x < 0 or p.y < 0 or p.x > vs.x or p.y > vs.y:
						continue
					var sz: float = st[1]
					draw_rect(Rect2(p, Vector2(sz, sz)), st[2])
	if ship and ship.warp and ship.velocity.length() > 10.0:
		var dir: Vector2 = -ship.velocity.normalized()
		var rng := RandomNumberGenerator.new()
		rng.seed = Time.get_ticks_msec() / 50
		for i in 40:
			var p := Vector2(rng.randf() * vs.x, rng.randf() * vs.y)
			draw_line(p, p + dir * rng.randf_range(40, 160), Color(0.7, 0.85, 1.0, 0.35), 1.5)
