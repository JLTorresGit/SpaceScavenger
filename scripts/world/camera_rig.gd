extends Camera2D
## Top-down camera centred on the ship. Smooth zoom, and a smoothed look-ahead
## offset in the direction of velocity for a sense of momentum. Photo mode
## detaches it for free panning while the game is paused.

var ship
var target_zoom := 0.8
var photo_mode := false
var _look := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	target_zoom = Config.fval("camera.zoom_default", 0.8)
	zoom = Vector2.ONE * target_zoom


func zoom_by(steps: float) -> void:
	target_zoom = clampf(target_zoom * pow(Config.fval("camera.zoom_step", 1.15), steps),
		Config.fval("camera.zoom_min", 0.12), Config.fval("camera.zoom_max", 2.5))


func shift(delta: Vector2) -> void:
	position -= delta


func snap() -> void:
	_look = Vector2.ZERO
	if ship:
		position = ship.position


func _process(delta: float) -> void:
	if ship == null:
		return
	var paused := get_tree().paused
	if paused and not photo_mode:
		return
	var real_dt := delta if not paused else get_process_delta_time()
	var z := lerpf(zoom.x, target_zoom, 1.0 - exp(-Config.fval("camera.zoom_smooth", 8.0) * real_dt))
	zoom = Vector2(z, z)
	if photo_mode:
		var pan := Vector2(Input.get_axis("rotate_left", "rotate_right"), Input.get_axis("thrust", "retro"))
		position += pan * Config.fval("camera.photo_pan_speed", 900) / z * real_dt
		return
	var vel: Vector2 = ship.velocity
	var look := (vel * Config.fval("camera.lookahead_factor", 0.35)).limit_length(Config.fval("camera.lookahead_max", 420))
	_look = _look.lerp(look, 1.0 - exp(-Config.fval("camera.follow_smooth", 5.0) * 0.4 * real_dt))
	position = ship.position + _look
