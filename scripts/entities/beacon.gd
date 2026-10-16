extends SpaceEntity
## Unknown signal (a cache to collect) or rescue pod (timed rescue mission).

var pulse := 0.0


func _setup() -> void:
	discoverable = true


func default_name() -> String:
	return "Unknown signal" if kind == "signal" else "Escape pod"


func scan_info() -> Dictionary:
	var info := super.scan_info()
	if kind == "signal":
		info["lines"] = ["Repeating signal of unknown origin.", "Fly into it to recover the source."]
	else:
		info["lines"] = ["Escape pod with survivors.", "Reach it before life support runs out (%d s)." % Config.ival("anomalies.rescue.time_limit")]
	return info


func on_discovered() -> void:
	if kind == "rescue_pod" and Game.active_rescue.is_empty():
		Game.active_rescue = {"id": id, "remaining": Config.fval("anomalies.rescue.time_limit", 120), "name": display_name(), "wx": wx(), "wy": wy()}
		Game.notify("Distress call: escape pod nearby! Reach it within %d s." % Config.ival("anomalies.rescue.time_limit"), "warning")


func on_ship_contact(_ship) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.get("reward_seed", 1))
	if kind == "signal":
		var cfg := Config.dict("anomalies.signal")
		var credits := Config.rand_int(rng, cfg.get("credits", [100, 300]))
		Game.add_credits(credits)
		universe.drop_loot(Generator.roll_loot(str(cfg.get("loot", "signal_cache")), rng), position, 60)
		Game.add_log("Signal source", "The signal came from an automated cache. Recovered %d credits and supplies." % credits)
		Game.notify("Signal source recovered: %d credits and a supply cache." % credits, "good")
	else:
		if Game.active_rescue.get("id", "") == id:
			var cfg := Config.dict("anomalies.rescue")
			Game.add_credits(int(cfg.get("credits", 400)))
			universe.drop_loot(Generator.roll_loot(str(cfg.get("loot", "rescue_reward")), rng), position, 60)
			Game.stat_add("rescues")
			Game.notify("Survivors rescued! Reward: %d credits." % int(cfg.get("credits", 400)), "good")
		else:
			Game.notify("The pod is silent. Nobody survived.", "warning")
		Game.active_rescue = {}
	universe.remove_entity(self, true)


func _process(delta: float) -> void:
	pulse = fmod(pulse + delta, 2.0)
	queue_redraw()


func _draw() -> void:
	var c := Color(1.0, 1.0, 0.6) if kind == "signal" else Color(1.0, 0.45, 0.4)
	for i in 3:
		var t := fmod(pulse + i * 0.66, 2.0) / 2.0
		draw_arc(Vector2.ZERO, radius + t * 160.0, 0, TAU, 48, Color(c, 0.5 * (1.0 - t)), 2.0, true)
	if kind == "signal":
		draw_colored_polygon(PackedVector2Array([Vector2(0, -radius), Vector2(radius * 0.6, 0), Vector2(0, radius), Vector2(-radius * 0.6, 0)]), c)
	else:
		draw_rect(Rect2(-radius * 0.5, -radius * 0.8, radius, radius * 1.6), Color(0.85, 0.85, 0.9))
		draw_circle(Vector2(0, -radius * 0.3), radius * 0.25, Color(0.4, 0.8, 1.0))
		if pulse < 0.3:
			draw_circle(Vector2(0, radius * 0.5), 4, c)
