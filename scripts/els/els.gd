extends Node
## ELS (emergency lighting + siren) state. Contract: docs/MIMARI.md, API: docs/api/els.md.
## The ELS panel (scripts/hud/els_panel.gd) is a pure view of this node; vehicles read cell_colors(t).

signal changed
## Short white toast text ("Stage 3: Quad alternate", "Traffic advisor: left"); the HUD shows it with notify().
signal notice(text: String)

const SIRENS := {
	&"wail": {"label": "Wail", "pattern": "Counter-rotating"},
	&"yelp": {"label": "Yelp", "pattern": "Triple alternate"},
	&"prty": {"label": "Priority", "pattern": "Sparkle"},
	&"hilo": {"label": "Hi-lo", "pattern": "Double cross"},
	&"hyper_yelp": {"label": "Hyper yelp", "pattern": "Six-burst cross fast"},
	&"rotor": {"label": "Mechanical rotor", "pattern": "Counter-rotating"},
	&"mech_wail": {"label": "Mech wail", "pattern": "Bounce"},
	&"yelp2": {"label": "Yelp 2", "pattern": "Triple alternate"},
	&"pierce": {"label": "Piercer", "pattern": "Sparkle"},
	&"hyper_hilo": {"label": "Hyper hi-lo", "pattern": "Six-burst cross fast"},
}
const OFF_PATTERN := "Double cross"
const WIG_REST := "CCrr..rrCC"
## With the lights on and no siren used yet the automatic pattern walks through this list (traffic stop, stage 2,
## changes seen at 46.5, 54.5, 62.5 and 70.5 s after the lights came on at ~39 s); the last entry holds.
const IDLE_SEQUENCE := [["Bounce", 7.5], ["Slow alternate", 8.0], ["Double alternate slow", 8.0],
	["Slow pulse together", 8.0], ["Rotator slow", 0.0]]
const TOGGLES: Array[StringName] = [
	&"take_down", &"left_alley", &"right_alley", &"spot", &"cruise", &"dim", &"front_cut", &"rear_cut",
	&"rumbler", &"auto_siren", &"prog", &"warn", &"haz", &"road_clsd",
]
const TRAFFIC_AMBER := Color("ffa000")
const TRAFFIC_CELLS := 8

var stage: int = 3: set = set_stage
var lights_on: bool = false: set = set_lights
var siren_tone: StringName = &"": set = set_siren
var pattern_index: int = -1  # -1 = automatic (follows the siren), else index into ElsPatterns.ORDER
var traffic_dir: StringName = &""  # "", left, split, right
var siren_note: String = ""  # e.g. "(junction ahead)" appended to the siren line
var toggles: Dictionary = {}  # StringName -> bool
var held: Dictionary = {}  # momentary buttons currently pressed: man, ah, blip

var _time: float = 0.0
var _auto_override := ""
var _lights_started := -1.0  # Els time the current lights session began (-1 = lights off)
var _siren_used := false  # a siren ran during this lights session


func _ready() -> void:
	for id in TOGGLES:
		toggles[id] = false


func _process(delta: float) -> void:
	_time += delta
	if lights_active():
		if _lights_started < 0.0:
			_lights_started = _time
	else:
		_lights_started = -1.0
		_siren_used = false


## Seconds since start; pass to cell_colors() / traffic_colors().
func now() -> float:
	return _time


# --- state ------------------------------------------------------------------------

func set_stage(value: int) -> void:
	value = clampi(value, 0, 3)
	if stage == value:
		return
	stage = value
	if value > 0 and lights_on:
		notice.emit("Stage %d: %s" % [stage, pattern_name()])
	changed.emit()


func set_lights(value: bool) -> void:
	if lights_on == value:
		return
	lights_on = value
	changed.emit()


## Selects a siren tone (see SIRENS keys); &"" switches the siren off. Selecting a siren also turns the lights on.
func set_siren(tone: StringName) -> void:
	if tone != &"" and not SIRENS.has(tone):
		push_warning("Els: unknown siren tone %s" % tone)
		return
	if siren_tone == tone:
		return
	siren_tone = tone
	if tone != &"":
		_siren_used = true
	pattern_index = -1
	_auto_override = ""
	siren_note = ""
	if tone != &"":
		lights_on = true
		if stage == 0:
			stage = 3
	_sirens_call("click")
	if tone == &"":
		_sirens_call("stop")
	else:
		_sirens_call("play", [tone])
	changed.emit()


## Panel button behaviour: pressing the active siren again silences it and the lights.
func toggle_siren(tone: StringName) -> void:
	if siren_tone == tone:
		set_siren(&"")
		set_lights(false)
	else:
		set_siren(tone)


func set_toggle(id: StringName, on: bool) -> void:
	if not TOGGLES.has(id) or toggles.get(id, false) == on:
		return
	toggles[id] = on
	if id == &"rumbler":
		_sirens_call("set_rumbler", [on])
	if id == &"warn" or id == &"haz" or id == &"road_clsd":
		var any: bool = toggles.get(&"warn", false) or toggles.get(&"haz", false) or toggles.get(&"road_clsd", false)
		var names := {&"warn": "warn", &"haz": "hazard", &"road_clsd": "road closed"}
		notice.emit("Traffic advisor: %s" % (names[id] if on else ("off" if not any and traffic_dir == &"" else names[id] + " off")))
	_sirens_call("click")
	changed.emit()


func toggle(id: StringName) -> void:
	set_toggle(id, not toggles.get(id, false))


func is_on(id: StringName) -> bool:
	return toggles.get(id, false)


func set_traffic_dir(dir: StringName) -> void:
	traffic_dir = &"" if traffic_dir == dir else dir
	notice.emit("Traffic advisor: %s" % (String(traffic_dir) if traffic_dir != &"" else "off"))
	_sirens_call("click")
	changed.emit()


## Momentary buttons: man (manual siren), ah (air horn), blip.
func press(id: StringName) -> void:
	if held.get(id, false):
		return
	held[id] = true
	match id:
		&"man":
			_sirens_call("set_manual", [true])
		&"ah":
			_sirens_call("set_horn", [true])
		&"blip":
			_sirens_call("blip")
	changed.emit()


func release(id: StringName) -> void:
	if not held.get(id, false):
		return
	held[id] = false
	match id:
		&"man":
			_sirens_call("set_manual", [false])
		&"ah":
			_sirens_call("set_horn", [false])
	changed.emit()


func set_siren_note(note: String) -> void:
	siren_note = note
	changed.emit()


func cycle_pattern(direction: int) -> void:
	var order := ElsPatterns.ORDER
	var current := pattern_index if pattern_index >= 0 else order.find(auto_pattern())
	pattern_index = posmod(current + direction, order.size())
	_sirens_call("click")
	notice.emit("Stage %d: %s" % [maxi(stage, 1), pattern_name()])
	changed.emit()


# --- derived info -----------------------------------------------------------------

func auto_pattern() -> String:
	if _auto_override != "":
		return _auto_override
	if SIRENS.has(siren_tone):
		return SIRENS[siren_tone]["pattern"]
	if lights_active() and not _siren_used:
		if _lights_started < 0.0:
			_lights_started = _time
		return idle_pattern_at(_time - _lights_started)
	return OFF_PATTERN


## Automatic pattern name `elapsed` seconds after the lights came on with no siren (see IDLE_SEQUENCE).
static func idle_pattern_at(elapsed: float) -> String:
	var t := maxf(elapsed, 0.0)
	for step in IDLE_SEQUENCE:
		if step[1] <= 0.0 or t < step[1]:
			return step[0]
		t -= step[1]
	return IDLE_SEQUENCE[IDLE_SEQUENCE.size() - 1][0]


## Chooses a pattern by name (manual, shown without the "Auto:" prefix). Unknown name = back to automatic.
func set_pattern(pattern_name: String, announce: bool = false) -> void:
	pattern_index = ElsPatterns.ORDER.find(pattern_name)
	if announce and pattern_index >= 0:
		notice.emit("Stage %d: %s" % [maxi(stage, 1), pattern_name])
	changed.emit()


## Overrides the automatic pattern of the current siren (the old panel showed "Auto: Response quad cross" for
## "Yelp (junction ahead)"). Cleared when the siren changes; "" clears it now.
func set_auto_pattern(pattern_name: String) -> void:
	_auto_override = pattern_name
	pattern_index = -1
	changed.emit()


func pattern_name() -> String:
	return ElsPatterns.ORDER[pattern_index] if pattern_index >= 0 else auto_pattern()


func siren_label() -> String:
	return SIRENS[siren_tone]["label"] if SIRENS.has(siren_tone) else "Off"


## The three text lines of the panel status box.
func status_lines() -> PackedStringArray:
	var prefix := "Auto: " if pattern_index < 0 else ""  # a manually chosen pattern shows its bare name (old panel)
	var siren := siren_label()
	if not siren_note.is_empty():
		siren += "  " + siren_note
	return PackedStringArray([
		"STAGE %d  %s%s" % [stage, prefix, pattern_name()] if stage > 0 else "STAGE OFF  %s%s" % [prefix, pattern_name()],
		"SIREN  " + siren,
		"READY",
	])


func lights_active() -> bool:
	return lights_on and stage > 0


## Cells a stage may light, per row (FRONT, REAR, PODS, WIG) as 10-bit masks. Old panel behaviour:
## stage 1 never lights FRONT, lights the whole REAR row, PODS cells 3-6 and the static outer wig blocks;
## stage 2 and 3 use every cell of a pattern.
const STAGE_ROW_MASKS := {
	1: [0, 0x3FF, 0x078, 0x303],
	2: [0x3FF, 0x3FF, 0x3FF, 0x3FF],
	3: [0x3FF, 0x3FF, 0x3FF, 0x3FF],
}


func _stage_mask(row: int = 2) -> int:
	return STAGE_ROW_MASKS[stage][row] if STAGE_ROW_MASKS.has(stage) else 0


## Bit mask of lit pods cells at time t (the panel's blue row and the world lights share it).
func cell_mask(t: float) -> int:
	if not lights_active():
		return 0
	if toggles.get(&"cruise", false):
		return _stage_mask()  # TODO(tahmin): CRUISE = steady burn at the current stage
	return ElsPatterns.mask_at(pattern_name(), t) & _stage_mask()


## Current color of each of the 10 light cells (black = off): the PODS row. Legacy patterns use red left, blue right;
## measured patterns carry their own colors (white cells etc.).
func cell_colors(t: float) -> PackedColorArray:
	var colors := PackedColorArray()
	var gain := 0.4 if toggles.get(&"dim", false) else 1.0
	if not lights_active():
		colors.resize(ElsPatterns.CELL_COUNT)
		colors.fill(Color(0, 0, 0))
		return colors
	if toggles.get(&"cruise", false):
		var base := ElsPatterns.default_colors()
		var m := _stage_mask()
		for i in ElsPatterns.CELL_COUNT:
			colors.append(base[i] * gain if m & (1 << i) else Color(0, 0, 0))
		return colors
	var all := ElsPatterns.colors_at(pattern_name(), t)
	var mask := _stage_mask()
	for i in ElsPatterns.CELL_COUNT:
		colors.append(all[i] * gain if mask & (1 << i) else Color(0, 0, 0))
	return colors


## All four measured rows at time t as an Array of four PackedColorArray(10): FRONT, REAR, PODS, WIG. The WIG row is the
## wig-wag headlight flasher; dim red/blue entries are the static dim cells of the old panel.
func row_colors(t: float) -> Array:
	var rows: Array = []
	var gain := 0.4 if toggles.get(&"dim", false) else 1.0
	for r in 4:
		var colors := PackedColorArray()
		if not lights_active() and r == 3:
			# The wig-wag row keeps its static rest cells (cream outer blocks, dim red inner blocks) with the lights off.
			for ch in WIG_REST:
				colors.append(ElsPatterns.CLASS_COLORS[ch] if ElsPatterns.CLASS_COLORS.has(ch) else Color(0, 0, 0))
		elif not lights_active():
			colors.resize(ElsPatterns.CELL_COUNT)
			colors.fill(Color(0, 0, 0))
		elif r == 2:
			colors = cell_colors(t)
		elif toggles.get(&"cruise", false):
			var base := ElsPatterns.default_colors()
			for i in ElsPatterns.CELL_COUNT:
				colors.append(base[i] * gain if r < 2 and _stage_mask(r) & (1 << i) else Color(0, 0, 0))
		else:
			var src := ElsPatterns.row_colors(pattern_name(), r, t)
			var mask := _stage_mask(r)
			for i in ElsPatterns.CELL_COUNT:
				colors.append(src[i] * gain if mask & (1 << i) else Color(0, 0, 0))
		rows.append(colors)
	return rows


## Traffic advisor: 8 amber cells. Direction arms sweep; WARN/HAZ flash all.
func traffic_colors(t: float) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(TRAFFIC_CELLS)
	colors.fill(Color(0, 0, 0))
	var step := int(fposmod(t, 0.8) / 0.1)
	var blink := fposmod(t, 0.8) < 0.4
	if traffic_dir == &"left":
		for i in TRAFFIC_CELLS:
			if i >= TRAFFIC_CELLS - 1 - step:
				colors[i] = TRAFFIC_AMBER
	elif traffic_dir == &"right":
		for i in TRAFFIC_CELLS:
			if i <= step:
				colors[i] = TRAFFIC_AMBER
	elif traffic_dir == &"split":
		for i in TRAFFIC_CELLS / 2:  # arms open from the centre outwards
			if TRAFFIC_CELLS / 2 - 1 - i <= step:
				colors[i] = TRAFFIC_AMBER
				colors[TRAFFIC_CELLS - 1 - i] = TRAFFIC_AMBER
	if (toggles.get(&"warn", false) or toggles.get(&"haz", false) or toggles.get(&"road_clsd", false)) and blink:
		colors.fill(TRAFFIC_AMBER)
	return colors


func _sirens_call(method: String, args: Array = []) -> void:
	var sirens := get_node_or_null("/root/Sirens")
	if sirens and sirens.has_method(method):
		sirens.callv(method, args)
