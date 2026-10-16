class_name GameWindows
extends RefCounted
## In-game windows: codex, technology tree, cargo & crafting, modules, station.

const KIND_FILTERS := {
	"All": [],
	"Stars": ["star"], "Planets": ["planet"], "Moons": ["moon"], "Stations": ["station"],
	"Asteroid fields": ["field", "comet"],
	"Hazards": ["nebula", "black_hole", "ion_storm"],
	"Anomalies": ["wormhole", "signal", "rescue_pod", "ghost_ship", "derelict"],
}


static func effect_text(e: Dictionary) -> String:
	var stat := str(e.get("stat", "")).replace("_", " ").capitalize()
	var v := float(e.get("value", 0))
	match str(e.get("op", "add")):
		"mul":
			return "%s ×%.2f" % [stat, v]
		"set":
			return "%s = %s" % [stat, str(v)]
	return "%s %+g" % [stat, v]


# --- Codex ----------------------------------------------------------------------

class CodexWindow extends WindowPanel:
	var filter: OptionButton
	var search: LineEdit
	var logs_toggle: CheckButton
	var list: ItemList
	var details: VBoxContainer
	var ids: Array = []
	var selected := ""

	func _init() -> void:
		window_title = "Codex — Discoveries & Logs"
		window_size = Vector2(1080, 640)

	func _build() -> void:
		var top := UiKit.hbox()
		filter = OptionButton.new()
		for k in GameWindows.KIND_FILTERS.keys():
			filter.add_item(k)
		filter.item_selected.connect(func(_i): refresh())
		top.add_child(filter)
		search = LineEdit.new()
		search.placeholder_text = "Search name…"
		search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		search.text_changed.connect(func(_t): refresh())
		top.add_child(search)
		logs_toggle = CheckButton.new()
		logs_toggle.text = "Show recovered logs"
		logs_toggle.focus_mode = Control.FOCUS_NONE
		logs_toggle.toggled.connect(func(_on): _on_logs_toggled())
		top.add_child(logs_toggle)
		body.add_child(top)
		var split := HSplitContainer.new()
		split.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list = ItemList.new()
		list.custom_minimum_size = Vector2(380, 480)
		list.item_selected.connect(_on_select)
		split.add_child(list)
		details = UiKit.vbox(8)
		split.add_child(UiKit.scroll(details, 480))
		body.add_child(split)

	func refresh() -> void:
		list.clear()
		ids.clear()
		if logs_toggle.button_pressed:
			for i in Game.logs.size():
				var l: Dictionary = Game.logs[i]
				list.add_item("%s  ·  %s" % [l["title"], str(l["date"]).replace("T", " ")])
				ids.append(str(i))
		else:
			var kinds: Array = GameWindows.KIND_FILTERS[filter.get_item_text(filter.selected)]
			var entries := Game.discoveries.values()
			entries.sort_custom(func(a, b): return float(a.get("time", 0)) > float(b.get("time", 0)))
			var q := search.text.strip_edges().to_lower()
			for e in entries:
				var k := str(e["kind"])
				if k == "derelict" and str(e.get("subtype", "")) == "ghost_ship":
					k = "ghost_ship"
				if not kinds.is_empty() and not kinds.has(k):
					continue
				if q != "" and not str(e["name"]).to_lower().contains(q):
					continue
				list.add_item("%s   [%s]   %s" % [e["name"], str(e["kind"]).replace("_", " "), UiKit.fmt_dist(_dist(e))])
				ids.append(e["id"])
		var idx := ids.find(selected)
		if idx >= 0:
			list.select(idx)
		_show_details()

	func _on_logs_toggled() -> void:
		selected = ""
		refresh()

	func _dist(e: Dictionary) -> float:
		var u = main.universe
		return u.to_local_pos(float(e["wx"]), float(e["wy"])).distance_to(main.ship.position)

	func _on_select(i: int) -> void:
		selected = ids[i]
		_show_details()

	func _show_details() -> void:
		UiKit.clear(details)
		if selected == "":
			details.add_child(UiKit.wrap_label("Select an entry. Discovered objects can be targeted for the autopilot or reached by quick travel (costs fuel, limited range).", 15, Color(0.6, 0.7, 0.85)))
			details.add_child(UiKit.label("%d discoveries · %d logs" % [Game.discoveries.size(), Game.logs.size()], 15))
			return
		if logs_toggle.button_pressed:
			var l: Dictionary = Game.logs[int(selected)]
			details.add_child(UiKit.label(l["title"], 22, Color(0.6, 0.85, 1.0)))
			details.add_child(UiKit.label("Recovered " + str(l["date"]).replace("T", " "), 13, Color(0.55, 0.65, 0.8)))
			details.add_child(UiKit.wrap_label(l["text"], 16))
			return
		var e: Dictionary = Game.discoveries.get(selected, {})
		if e.is_empty():
			return
		details.add_child(UiKit.label(e["name"], 24, Color(0.6, 0.85, 1.0)))
		var sub := str(e.get("subtype", "")).replace("_", " ")
		details.add_child(UiKit.label("%s%s" % [str(e["kind"]).replace("_", " ").capitalize(), "  ·  " + sub if sub != "" else ""], 15))
		details.add_child(UiKit.label("Coordinates  X %s   Y %s" % [UiKit.fmt_dist(float(e["wx"])), UiKit.fmt_dist(float(e["wy"]))], 14))
		details.add_child(UiKit.label("Distance  " + UiKit.fmt_dist(_dist(e)), 14))
		details.add_child(UiKit.label("Discovered  %s  (after %s of play)" % [str(e.get("date", "")).replace("T", " "), UiKit.fmt_time(float(e.get("time", 0)))], 14))
		var notes: Array = e.get("notes", [])
		if notes.is_empty():
			details.add_child(UiKit.label("Not scanned yet (press %s near it)." % Config.binding_text("scan"), 14, Color(0.6, 0.65, 0.75)))
		else:
			details.add_child(UiKit.label("Scan data:", 15, Color(0.4, 1.0, 0.8)))
			for n in notes:
				details.add_child(UiKit.wrap_label("  " + str(n), 14))
		var row := UiKit.hbox()
		row.add_child(UiKit.button("Set as target", func(): main.set_target_entry(e)))
		var reason: String = main.ship.quick_travel_block_reason(e)
		var cost: Dictionary = main.ship.quick_travel_cost(float(e["wx"]), float(e["wy"]))
		var qt := UiKit.button("Quick travel (%.1f fuel)" % cost["fuel"], func(): main.quick_travel(e))
		qt.disabled = reason != ""
		qt.tooltip_text = reason
		row.add_child(qt)
		details.add_child(row)
		if reason != "":
			details.add_child(UiKit.label(reason, 13, Game.pal("warning")))
		if e["kind"] in ["star", "planet", "moon"]:
			var rrow := UiKit.hbox()
			var edit := LineEdit.new()
			edit.text = e["name"]
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rrow.add_child(edit)
			rrow.add_child(UiKit.button("Rename", func(): _rename(e["id"], edit.text)))
			details.add_child(rrow)

	func _rename(id: String, new_name: String) -> void:
		Game.set_name_for(id, new_name)
		refresh()


# --- Technology tree ----------------------------------------------------------------

class TechWindow extends WindowPanel:
	var columns: HBoxContainer
	var details: VBoxContainer
	var status: Label
	var selected := ""

	func _init() -> void:
		window_title = "Technology Tree"
		window_size = Vector2(1500, 740)

	func _build() -> void:
		status = UiKit.label("", 15)
		body.add_child(status)
		var split := HSplitContainer.new()
		split.size_flags_vertical = Control.SIZE_EXPAND_FILL
		columns = UiKit.hbox(10)
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(1110, 600)
		sc.add_child(columns)
		split.add_child(sc)
		details = UiKit.vbox(6)
		details.custom_minimum_size.x = 330
		split.add_child(UiKit.scroll(details, 600))
		body.add_child(split)

	func refresh() -> void:
		var lab := "Lab ready" if Game.lab_ready() else "Lab NOT ready — install & enable the Research Lab module (%s)" % Config.binding_text("modules")
		if Game.research.is_empty():
			status.text = "%s   ·   No active research." % lab
		else:
			var n: Dictionary = Config.tech_nodes.get(Game.research["id"], {})
			status.text = "%s   ·   Researching %s — %s left" % [lab, n.get("name", "?"), UiKit.fmt_time(float(Game.research["remaining"]))]
		UiKit.clear(columns)
		for br in Config.tech.get("branches", []):
			var col := UiKit.vbox(6)
			col.custom_minimum_size.x = 175
			col.add_child(UiKit.label(br["name"], 18, Config.color(br.get("color", [1, 1, 1]))))
			var nodes: Array = []
			for n in Config.tech.get("nodes", []):
				if n["branch"] == br["id"]:
					nodes.append(n)
			nodes.sort_custom(func(a, b): return int(a.get("tier", 1)) < int(b.get("tier", 1)))
			for n in nodes:
				col.add_child(_node_button(n, Config.color(br.get("color", [1, 1, 1]))))
			columns.add_child(col)
		_show_details()

	func _state(id: String) -> String:
		if Game.researched.has(id):
			return "done"
		if Game.research.get("id", "") == id:
			return "running"
		for r in Config.tech_nodes[id].get("requires", []):
			if not Game.researched.has(r):
				return "locked"
		return "available"

	func _node_button(n: Dictionary, col: Color) -> Button:
		var st := _state(n["id"])
		var mark: String = {"done": "✔ ", "running": "⏳ ", "locked": "🔒 ", "available": ""}[st]
		var b := UiKit.button("%s%s\nTier %d · %s" % [mark, n["name"], int(n.get("tier", 1)), UiKit.fmt_time(float(n.get("time", 60)))], func(): _select(n["id"]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(175, 52)
		b.clip_text = true
		match st:
			"done": b.modulate = Color(0.75, 1.0, 0.8)
			"locked": b.modulate = Color(0.6, 0.6, 0.7)
			"running": b.modulate = Color(1.0, 0.95, 0.6)
			_: b.modulate = col.lightened(0.4)
		if n["id"] == selected:
			b.add_theme_color_override("font_color", Color(1, 1, 0.6))
		return b

	func _select(id: String) -> void:
		selected = id
		refresh()

	func _show_details() -> void:
		UiKit.clear(details)
		if selected == "":
			details.add_child(UiKit.wrap_label("Select a technology. Research consumes the listed resources when it starts and then takes time while the Lab module is enabled and the ship has energy.", 15, Color(0.6, 0.7, 0.85)))
			return
		var n: Dictionary = Config.tech_nodes[selected]
		details.add_child(UiKit.label(n["name"], 22, Color(0.6, 0.85, 1.0)))
		details.add_child(UiKit.wrap_label(str(n.get("description", "")), 15))
		details.add_child(UiKit.label("Time: " + UiKit.fmt_time(float(n.get("time", 60))), 14))
		details.add_child(UiKit.label("Cost:", 15, Color(0.6, 0.85, 1.0)))
		var cost: Dictionary = n.get("cost", {})
		for k in cost.keys():
			var have := Game.count(k)
			var need := int(cost[k])
			details.add_child(UiKit.label("  %s  %d / %d" % [Config.item_name(k), have, need], 14, Game.pal("good") if have >= need else Game.pal("danger")))
		var reqs: Array = n.get("requires", [])
		if not reqs.is_empty():
			var names: PackedStringArray = []
			for r in reqs:
				names.append(("✔ " if Game.researched.has(r) else "✖ ") + str(Config.tech_nodes.get(r, {}).get("name", r)))
			details.add_child(UiKit.wrap_label("Requires: " + ", ".join(names), 14))
		details.add_child(UiKit.label("Effects:", 15, Color(0.6, 0.85, 1.0)))
		for e in n.get("effects", []):
			details.add_child(UiKit.label("  " + GameWindows.effect_text(e), 14))
		var unlocks: Dictionary = n.get("unlocks", {})
		for m in unlocks.get("modules", []):
			details.add_child(UiKit.label("  Unlocks module: " + str(Config.dict("modules." + m).get("name", m)), 14))
		for r in unlocks.get("recipes", []):
			details.add_child(UiKit.label("  Unlocks recipe: " + str(Config.dict("recipes." + r).get("name", r)), 14))
		if n.has("sets"):
			details.add_child(UiKit.label("  Engine mode: " + str(n["sets"].get("engine_mode", "")), 14))
		var st := _state(selected)
		if st == "done":
			details.add_child(UiKit.label("Researched.", 16, Game.pal("good")))
		elif st == "running":
			details.add_child(UiKit.button("Cancel research (50% refund)", func(): _cancel()))
		else:
			var reason := Game.research_block_reason(selected)
			var b := UiKit.button("Start research", func(): _start(selected))
			b.disabled = reason != ""
			details.add_child(b)
			if reason != "":
				details.add_child(UiKit.wrap_label(reason, 14, Game.pal("warning")))

	func _cancel() -> void:
		Game.cancel_research()
		refresh()

	func _start(id: String) -> void:
		Game.start_research(id)
		refresh()


# --- Cargo & crafting ---------------------------------------------------------------

class CargoWindow extends WindowPanel:
	var content: VBoxContainer

	func _init() -> void:
		window_title = "Cargo & Crafting"
		window_size = Vector2(980, 640)

	func _build() -> void:
		content = UiKit.vbox(6)
		body.add_child(UiKit.scroll(content, 560))
		Game.cargo_changed.connect(_on_cargo_changed)

	func refresh() -> void:
		UiKit.clear(content)
		var w := UiKit.hbox(12)
		w.add_child(UiKit.label("Weight %.1f / %.0f" % [Game.cargo_weight(), Game.stat("cargo_max_weight")], 15))
		w.add_child(UiKit.bar(Game.cargo_weight(), Game.stat("cargo_max_weight"), Color(0.8, 0.7, 0.5), 200))
		w.add_child(UiKit.label("Volume %.1f / %.0f" % [Game.cargo_volume(), Game.stat("cargo_max_volume")], 15))
		w.add_child(UiKit.bar(Game.cargo_volume(), Game.stat("cargo_max_volume"), Color(0.7, 0.6, 0.9), 200))
		content.add_child(w)
		var grid := GridContainer.new()
		grid.columns = 7
		grid.add_theme_constant_override("h_separation", 14)
		for h in ["Item", "Qty", "Weight", "Volume", "Value", "", ""]:
			grid.add_child(UiKit.label(h, 14, Color(0.6, 0.85, 1.0)))
		var keys := Game.cargo.keys()
		keys.sort()
		for k in keys:
			var def := Config.item(k)
			var n := Game.count(k)
			grid.add_child(UiKit.label(Config.item_name(k), 15, Config.color(def.get("color", [1, 1, 1]))))
			grid.add_child(UiKit.label(str(n), 15))
			grid.add_child(UiKit.label("%.1f" % (float(def.get("weight", 1)) * n), 14))
			grid.add_child(UiKit.label("%.1f" % (float(def.get("volume", 1)) * n), 14))
			grid.add_child(UiKit.label("%d cr" % int(float(def.get("price", 0)) * n), 14))
			var use := UiKit.button("Use", func(): Game.use_item(k))
			use.disabled = not def.has("use")
			grid.add_child(use)
			var j := UiKit.hbox(4)
			j.add_child(UiKit.button("Jettison 1", func(): main.jettison(k, 1)))
			j.add_child(UiKit.button("All", func(): main.jettison(k, Game.count(k))))
			grid.add_child(j)
		if keys.is_empty():
			content.add_child(UiKit.label("Cargo hold is empty.", 15))
		content.add_child(grid)
		content.add_child(HSeparator.new())
		content.add_child(UiKit.label("Crafting (Refinery)", 20, Color(0.6, 0.85, 1.0)))
		for rid in Config.dict("recipes").keys():
			var r: Dictionary = Config.dict("recipes." + rid)
			var row := UiKit.hbox()
			var text := "%s:  %s  →  %s" % [r.get("name", rid), Game.cost_text(r.get("inputs", {})), Game.cost_text(r.get("outputs", {}))]
			var lbl := UiKit.label(text, 15)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var reason := Game.recipe_block_reason(rid)
			if reason != "":
				row.add_child(UiKit.label(reason, 13, Game.pal("warning")))
			var b := UiKit.button("Craft", func(): Game.craft(rid))
			b.disabled = reason != ""
			row.add_child(b)
			var b5 := UiKit.button("×5", func(): _craft_many(rid, 5))
			b5.disabled = reason != ""
			row.add_child(b5)
			content.add_child(row)

	func _on_cargo_changed() -> void:
		if visible:
			refresh()

	func _craft_many(rid: String, n: int) -> void:
		for i in n:
			if Game.recipe_block_reason(rid) != "" or not Game.craft(rid):
				break


# --- Modules ------------------------------------------------------------------------

class ModulesWindow extends WindowPanel:
	var content: VBoxContainer

	func _init() -> void:
		window_title = "Ship Modules"
		window_size = Vector2(860, 600)

	func _build() -> void:
		content = UiKit.vbox(6)
		body.add_child(UiKit.scroll(content, 520))

	func refresh() -> void:
		UiKit.clear(content)
		content.add_child(UiKit.label("Slots used: %d / %d" % [Game.modules_installed.size(), int(Game.stat("module_slots"))], 18))
		content.add_child(UiKit.label("Installed", 18, Color(0.6, 0.85, 1.0)))
		for m in Game.modules_installed:
			var def := Config.dict("modules." + m)
			var row := UiKit.hbox()
			var lbl := UiKit.label("%s — %s  (%.1f energy/s)" % [def.get("name", m), def.get("description", ""), float(def.get("energy_per_sec", 0))], 15)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var on := CheckBox.new()
			on.text = "Enabled"
			on.focus_mode = Control.FOCUS_NONE
			on.button_pressed = Game.modules_enabled.get(m, true)
			on.toggled.connect(func(v): Game.set_module_enabled(m, v))
			row.add_child(on)
			row.add_child(UiKit.button("Uninstall", func(): _uninstall(m)))
			content.add_child(row)
		content.add_child(HSeparator.new())
		content.add_child(UiKit.label("Available", 18, Color(0.6, 0.85, 1.0)))
		for m in Config.dict("modules").keys():
			if Game.modules_installed.has(m):
				continue
			var def := Config.dict("modules." + m)
			var row := UiKit.hbox()
			var lbl := UiKit.label("%s — %s" % [def.get("name", m), def.get("description", "")], 15)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			if Game.modules_unlocked.has(m):
				var b := UiKit.button("Install", func(): _install(m))
				b.disabled = Game.free_slots() <= 0
				row.add_child(b)
			else:
				row.add_child(UiKit.label("Research: " + _unlocked_by(m), 13, Color(0.6, 0.65, 0.75)))
			content.add_child(row)

	func _unlocked_by(m: String) -> String:
		for n in Config.tech.get("nodes", []):
			if m in n.get("unlocks", {}).get("modules", []):
				return str(n["name"])
		return "?"

	func _install(m: String) -> void:
		Game.install_module(m)
		refresh()

	func _uninstall(m: String) -> void:
		Game.uninstall_module(m)
		refresh()


# --- Station --------------------------------------------------------------------------

class StationWindow extends WindowPanel:
	var station
	var content: VBoxContainer

	func _init() -> void:
		window_title = "Station"
		window_size = Vector2(960, 640)

	func _build() -> void:
		content = UiKit.vbox(6)
		body.add_child(UiKit.scroll(content, 560))

	func refresh() -> void:
		title_label.text = "Docked: " + (station.display_name() if station else "Station")
		UiKit.clear(content)
		var st := Config.dict("station")
		content.add_child(UiKit.label("Credits: %d   ·   Discovery data: %d pts" % [Game.credits, Game.data_points], 18))
		content.add_child(UiKit.label("Services", 18, Color(0.6, 0.85, 1.0)))
		var fuel_need := Game.stat("fuel_capacity") - Game.fuel
		var energy_need := Game.stat("energy_capacity") - Game.energy
		var hull_need := Game.stat("hull_max") - Game.hull
		_service("Refuel (+%.0f fuel)" % fuel_need, int(ceil(fuel_need * float(st.get("fuel_price_per_unit", 1.5)))), func(): Game.fuel = Game.stat("fuel_capacity"), fuel_need > 0.5)
		_service("Recharge (+%.0f energy)" % energy_need, int(ceil(energy_need * float(st.get("energy_price_per_unit", 0.8)))), func(): Game.energy = Game.stat("energy_capacity"), energy_need > 0.5)
		_service("Repair hull (+%.0f)" % hull_need, int(ceil(hull_need * float(st.get("repair_price_per_point", 2.5)))), func(): Game.hull = Game.stat("hull_max"), hull_need > 0.5)
		var data_value := int(Game.data_points * float(st.get("data_price_per_point", 1.0)))
		var sell_data := UiKit.button("Sell discovery data (+%d cr)" % data_value, _sell_data)
		sell_data.disabled = Game.data_points <= 0
		content.add_child(sell_data)
		content.add_child(HSeparator.new())
		content.add_child(UiKit.label("Sell", 18, Color(0.6, 0.85, 1.0)))
		var keys := Game.cargo.keys()
		keys.sort()
		for k in keys:
			var price := int(round(float(Config.item(k).get("price", 0)) * float(st.get("sell_multiplier", 1.0))))
			var row := UiKit.hbox()
			var lbl := UiKit.label("%s × %d   @ %d cr" % [Config.item_name(k), Game.count(k), price], 15)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			row.add_child(UiKit.button("Sell 1", func(): _sell(k, 1, price)))
			row.add_child(UiKit.button("Sell all", func(): _sell(k, Game.count(k), price)))
			content.add_child(row)
		content.add_child(HSeparator.new())
		content.add_child(UiKit.label("Buy", 18, Color(0.6, 0.85, 1.0)))
		for k in st.get("buy_items", []):
			var price := int(round(float(Config.item(k).get("price", 0)) * float(st.get("buy_multiplier", 1.6))))
			var row := UiKit.hbox()
			var lbl := UiKit.label("%s   @ %d cr   (fits %d)" % [Config.item_name(k), price, Game.space_for(k)], 15)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			var b1 := UiKit.button("Buy 1", func(): _buy(k, 1, price))
			b1.disabled = Game.credits < price or Game.space_for(k) < 1
			row.add_child(b1)
			var b5 := UiKit.button("Buy 5", func(): _buy(k, 5, price))
			b5.disabled = Game.credits < price * 5 or Game.space_for(k) < 5
			row.add_child(b5)
			content.add_child(row)

	func _service(text: String, cost: int, action: Callable, needed: bool) -> void:
		var b := UiKit.button("%s — %d cr" % [text, cost], func(): _pay_service(cost, action))
		b.disabled = not needed or Game.credits < cost
		content.add_child(b)

	func _pay_service(cost: int, action: Callable) -> void:
		if Game.credits < cost:
			return
		Game.add_credits(-cost)
		action.call()
		refresh()

	func _sell_data() -> void:
		var value := int(Game.data_points * Config.fval("station.data_price_per_point", 1.0))
		Game.data_points = 0
		Game.add_credits(value)
		Game.notify("Sold discovery data for %d credits." % value, "good")
		refresh()

	func _sell(k: String, n: int, price: int) -> void:
		if n > 0 and Game.remove_item(k, n):
			Game.add_credits(n * price)
		refresh()

	func _buy(k: String, n: int, price: int) -> void:
		if Game.credits >= n * price and Game.space_for(k) >= n:
			Game.add_credits(-n * price)
			Game.add_item(k, n)
		refresh()
