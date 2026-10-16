class_name Naming
extends RefCounted
## Names that follow astronomical conventions:
## stars use catalogue ("HD 40307"), Bayer ("Tau Ceti") or Flamsteed ("61 Cygni")
## designations; planets append b, c, d...; moons append Roman numerals.

static func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


static func star_name(seed_value: int) -> String:
	var rng := _rng(seed_value)
	var n := Config.dict("naming")
	var style := Config.weighted_pick(rng, n.get("style_weights", {"catalogue": 1.0}))
	var constellations: Array = n.get("constellations", ["Ceti"])
	match style:
		"bayer":
			var greek: Array = n.get("greek", ["Alpha"])
			return "%s %s" % [greek[rng.randi() % greek.size()], constellations[rng.randi() % constellations.size()]]
		"flamsteed":
			return "%d %s" % [rng.randi_range(1, 120), constellations[rng.randi() % constellations.size()]]
		_:
			var cats: Array = n.get("catalogues", ["HD"])
			return "%s %d" % [cats[rng.randi() % cats.size()], Config.rand_int(rng, n.get("catalogue_number", [10, 99999]))]


static func random_star_name() -> String:
	return star_name(randi())


static func planet_name(star: String, index: int) -> String:
	var letters := str(Config.get_v("naming.planet_letters", "bcdefghijk"))
	return "%s %s" % [star, letters[index % letters.length()]]


static func moon_name(planet: String, index: int) -> String:
	return "%s %s" % [planet, roman(index + 1)]


static func roman(n: int) -> String:
	var values := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var symbols := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var out := ""
	for i in values.size():
		while n >= values[i]:
			out += symbols[i]
			n -= values[i]
	return out


static func station_name(seed_value: int) -> String:
	var rng := _rng(seed_value)
	var prefixes: Array = Config.get_v("naming.station_prefixes", ["Outpost"])
	var greek: Array = Config.get_v("naming.greek", ["Alpha"])
	return "%s %s-%d" % [prefixes[rng.randi() % prefixes.size()], greek[rng.randi() % greek.size()], rng.randi_range(1, 99)]


static func catalogue_name(prefix: String, seed_value: int) -> String:
	var rng := _rng(seed_value)
	return "%s-%04d" % [prefix, rng.randi_range(1, 9999)]


## Default (unrenamed) name for a body from its generation data, resolving the
## parent star and planet names so renaming a star renames its default planets.
static func default_body_name(d: Dictionary) -> String:
	match str(d.get("kind", "")):
		"star":
			return star_name(int(d.get("name_seed", 0)))
		"planet":
			var star := Game.name_of(str(d["star_id"]), star_name(int(d["star_name_seed"])))
			return planet_name(star, int(d["index"]))
		"moon":
			var star := Game.name_of(str(d["star_id"]), star_name(int(d["star_name_seed"])))
			var planet := Game.name_of(str(d["planet_id"]), planet_name(star, int(d["planet_index"])))
			return moon_name(planet, int(d["index"]))
	return str(d.get("kind", "Object")).capitalize()


## Procedural derelict log entry.
static func lore_entry(seed_value: int, subtype: String) -> Dictionary:
	var rng := _rng(seed_value)
	var l := Config.dict("lore")
	var prefixes: Array = l.get("ship_prefixes", ["ISV"])
	var names: Array = l.get("ship_names", ["Unknown"])
	var crew: Array = l.get("crew", ["The captain"])
	var systems: Array = l.get("systems", ["reactor"])
	var templates: Array = l.get("templates", ["Day {day}. Nothing to report."])
	var ship := "%s %s" % [prefixes[rng.randi() % prefixes.size()], names[rng.randi() % names.size()]]
	var text := str(templates[rng.randi() % templates.size()]).format({
		"day": rng.randi_range(3, 900), "crew": crew[rng.randi() % crew.size()], "system": systems[rng.randi() % systems.size()]})
	var title := ship if subtype != "station_wreck" else "Station log (%s)" % ship
	if subtype == "ghost_ship":
		title = "Ghost ship " + ship
	return {"title": title, "text": text}
