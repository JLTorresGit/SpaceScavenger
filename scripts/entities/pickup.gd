extends SpaceEntity
## Floating resource drop. Small drops are picked up by proximity collection;
## large drops need the (short-range) tractor beam.

var item := "scrap_alloy"
var amount := 1
var large := false
var tint := Color.WHITE
var bob := 0.0
var cooldown := 0.0          # seconds before it can be collected (jettisoned cargo)


func _setup() -> void:
	item = str(data.get("item", "scrap_alloy"))
	amount = int(data.get("count", 1))
	var def := Config.item(item)
	large = str(def.get("size", "small")) == "large"
	radius = 12.0 if large else 7.0
	tint = Config.color(def.get("color", [1, 1, 1]))
	layer = "items"
	bob = randf() * TAU


func default_name() -> String:
	return "%d × %s" % [amount, Config.item_name(item)]


func _process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)
	position += velocity * delta
	velocity = velocity.move_toward(Vector2.ZERO, 6.0 * delta)
	bob += delta * 2.0
	rotation = sin(bob) * 0.4


func _draw() -> void:
	var r := radius
	if large:
		draw_rect(Rect2(-r, -r, r * 2, r * 2), Color(tint, 0.9))
		draw_rect(Rect2(-r, -r, r * 2, r * 2), tint.lightened(0.5), false, 2.0)
		draw_line(Vector2(-r * 0.5, 0), Vector2(r * 0.5, 0), tint.darkened(0.5), 2.0)
	else:
		var pts := PackedVector2Array([Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)])
		draw_colored_polygon(pts, tint)
	draw_circle(Vector2.ZERO, r * 1.8, Color(tint, 0.12))
