class_name HudStatePlayer
extends RefCounted
## Loads scenarios/data/hud_states.json and puts the HUD into a saved state.
## Used by hud_states_shot.gd (screenshots) and usable from scenarios.
##
##   var states := HudStatePlayer.load_states()
##   HudStatePlayer.apply(hud, HudStatePlayer.find(states, "silah_emergency"))
##
## State keys: id, note, game {minutes, paused, weather, score, duty}, hud [[method, args...]],
## log [lines], street [name, mph], vehicle {speed, rpm, gear, panels},
## els {stage, siren, lights, pattern, auto_pattern, toggles [ids], note},
## radar {target, alpr [lines]}, els_style ("legacy"), street_visible, checks [region names], waive {region: reason}.
## hud calls may target sub-objects with a dotted name, e.g. ["radar.set_alpr", true, ["..."]].

const DEFAULT_PATH := "res://scenarios/data/hud_states.json"


static func load_states(path: String = DEFAULT_PATH) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("HudStatePlayer: cannot open %s" % path)
		return []
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary and data.has("states"):
		return data["states"]
	push_error("HudStatePlayer: bad JSON in %s" % path)
	return []


static func find(states: Array, id: String) -> Dictionary:
	for s in states:
		if s["id"] == id:
			return s
	return {}


## Applies a state to `hud` (the HUD node, hud.gd) and to the GameState / Els autoloads.
static func apply(hud: Node, state: Dictionary) -> void:
	var tree := hud.get_tree()
	var game_state := tree.root.get_node("GameState")
	var els := tree.root.get_node("Els")
	hud.call("reset")
	_reset_els(els)

	var g: Dictionary = state.get("game", {})
	if not g.is_empty():
		game_state.minutes = float(g.get("minutes", game_state.minutes))
		game_state.clock_running = not bool(g.get("paused", false))
		game_state.weather = String(g.get("weather", game_state.weather))
		game_state.score = int(g.get("score", game_state.score))
		game_state.duty_status = String(g.get("duty", game_state.duty_status))
		game_state.changed.emit()

	for line in state.get("log", []):
		hud.call("add_log_line", line, 0.0)
	if state.has("street"):
		hud.call("set_street", state["street"][0], int(state["street"][1]))

	if state.has("els_style"):
		hud.call("set_els_panel_style", String(state["els_style"]))
	if state.has("street_visible"):
		hud.call("set_street_visible", bool(state["street_visible"]))
	var v: Dictionary = state.get("vehicle", {})
	if not v.is_empty():
		hud.call("set_vehicle_hud", bool(v.get("panels", true)))
		hud.call("set_speed", float(v.get("speed", 0)))
		hud.call("set_rpm", float(v.get("rpm", 0)))
		hud.call("set_gear", String(v.get("gear", "N")))
	var r: Dictionary = state.get("radar", {})
	if not r.is_empty():
		hud.radar.set_radar(false, {}, "BOTH", "CLOSING", true, int(r.get("target", 75)))
		var hits: Array = r.get("alpr", [])
		hud.radar.set_alpr(not hits.is_empty(), hits)
	var e: Dictionary = state.get("els", {})
	if not e.is_empty():
		els.set_stage(int(e.get("stage", 3)))
		els.set_siren(StringName(String(e.get("siren", ""))))
		els.set_lights(bool(e.get("lights", false)))
		if e.has("auto_pattern"):
			els.set_auto_pattern(String(e["auto_pattern"]))
		if e.has("pattern"):
			els.set_pattern(String(e["pattern"]))
		for id in e.get("toggles", []):
			els.set_toggle(StringName(String(id)), true)
		if e.has("note"):
			els.set_siren_note(String(e["note"]))

	hud.call("clear_notify")  # Els notices (stage/pattern toasts) from the state changes above
	for call in state.get("hud", []):
		_call(hud, call)


static func _call(hud: Node, call: Array) -> void:
	var target: Object = hud
	var method := String(call[0])
	while method.contains("."):
		var parts := method.split(".", true, 1)
		target = target.get(parts[0])
		method = parts[1]
	target.callv(method, call.slice(1))


static func _reset_els(els: Node) -> void:
	els.set_siren(&"")
	els.set_stage(3)
	els.set_lights(false)
	for id in els.TOGGLES:
		els.set_toggle(id, false)
	if els.traffic_dir != &"":
		els.set_traffic_dir(els.traffic_dir)
	els.pattern_index = -1
	els.set_auto_pattern("")
	els.set_siren_note("")
