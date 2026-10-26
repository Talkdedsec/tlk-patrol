extends SceneTree
## Dev check: drives the ELS panel with synthetic mouse clicks and verifies Els/Sirens state.
## araclar/godot.sh --headless --script res://scripts/hud/els_selftest.gd
## Prints "PASS"/"FAIL" lines; exit code 1 if any check failed.

var _fail := 0
var _panel: Control


func _check(name: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + name)
	if not ok:
		_fail += 1


func _click(at: Vector2, down_frames: int = 2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at - Vector2(993.0, 766.0)  # panel-local; headless windows cannot hit-test the canvas
		e.global_position = at
		_panel._gui_input(e)
		if pressed:
			for i in down_frames:
				await process_frame


func _click_local(panel: Control, local: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = local
		panel._gui_input(e)


func _unique(arr: Array) -> int:
	var seen := {}
	for v in arr:
		seen[v] = true
	return seen.size()


func _btn(col: int, row: int) -> Vector2:
	return Vector2(993.0 + 26.0 + 64.0 * col + 29.0, 766.0 + [68.0, 108.0, 148.0][row] + 16.0)


func _initialize() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		print("FAIL selftest watchdog: a check aborted with a script error")
		quit(2))
	var hud = load("res://scripts/hud/hud.gd").new()
	root.add_child(hud)
	await process_frame
	hud.set_vehicle_hud(true)
	_panel = hud.els_panel
	await process_frame
	var els = root.get_node("Els")
	var sirens = root.get_node("Sirens")
	_check("initial: siren off, lights off, stage 3", els.siren_tone == &"" and not els.lights_on and els.stage == 3)
	_check("initial status lines", els.status_lines()[0] == "STAGE 3  Auto: Double cross" and els.status_lines()[1] == "SIREN  Off" and els.status_lines()[2] == "READY")

	await _click(_btn(0, 1))
	_check("WAIL click -> wail + lights", els.siren_tone == &"wail" and els.lights_on)
	_check("WAIL pattern Counter-rotating", els.pattern_name() == "Counter-rotating" and els.status_lines()[1] == "SIREN  Wail")
	await create_timer(0.3).timeout
	_check("Sirens playing wail", sirens.tone == &"wail" and sirens.is_playing())

	await _click(_btn(1, 1))
	_check("YELP click switches tone", els.siren_tone == &"yelp" and els.status_lines()[0] == "STAGE 3  Auto: Triple alternate")
	await _click(_btn(2, 1))
	_check("PRTY label is Priority", els.status_lines()[1] == "SIREN  Priority" and els.pattern_name() == "Sparkle")
	await _click(_btn(7, 1))
	_check("HYPER HI-LO", els.siren_tone == &"hyper_hilo" and els.pattern_name() == "Six-burst cross fast")

	# Pattern override and back.
	await _click(Vector2(993.0 + 171.0 + 20.0, 766.0 + 214.0 + 14.0))
	_check("PTRN < overrides pattern (bare name, no Auto:)", els.pattern_index >= 0 and not els.status_lines()[0].contains("Auto:"))
	await _click(_btn(1, 1))
	_check("new siren returns to auto pattern", els.pattern_index == -1)

	# Same button again: siren + lights off.
	await _click(_btn(1, 1))
	_check("second click on active siren silences it", els.siren_tone == &"" and not els.lights_on)

	# Toggle and hold buttons.
	await _click(_btn(4, 2))
	_check("RUMBLER toggles on", els.is_on(&"rumbler"))
	await _click(_btn(4, 2))
	_check("RUMBLER toggles off", not els.is_on(&"rumbler"))
	await _click(_btn(3, 2), 5)
	_check("A/H released after click", not els.held.get(&"ah", false))

	# Stage slider: click OFF then 2.
	await _click(Vector2(993.0 + 39.4, 766.0 + 234.0))
	_check("stage OFF", els.stage == 0 and not els.lights_active())
	await _click(Vector2(993.0 + 107.4, 766.0 + 234.0))
	_check("stage 2", els.stage == 2 and els.lights_on)

	# Light cell colors contract.
	els.set_stage(3)
	els.set_siren(&"yelp")
	var any_on := false
	for i in 200:
		var cols: PackedColorArray = els.cell_colors(i * 0.01)
		if cols.size() != 10:
			_check("cell_colors size", false)
		for c in cols:
			if c != Color(0, 0, 0):
				any_on = true
	_check("cell_colors returns 10 cells and some are lit", any_on)

	# Pattern data: 57 names + Slow alternate, rows, notices.
	var patterns = load("res://scripts/els/patterns.gd")
	_check("ORDER has 58 names and no duplicates", patterns.ORDER.size() == 58 and patterns.ORDER.size() == _unique(patterns.ORDER))
	var all_rows := true
	for n in patterns.ORDER:
		if n == "Slow alternate":
			continue
		var rows: PackedStringArray = patterns.rows_at(n, 0.37)
		if rows.size() != 4 or rows[0].length() != 10 or patterns.period_of(n) < 0.15:
			all_rows = false
	_check("every measured pattern has 4 rows of 10 cells and a period", all_rows)
	var noticed: Array[String] = []
	var cb := func(text: String) -> void: noticed.append(text)
	els.notice.connect(cb)
	els.set_siren(&"")
	els.set_stage(3)
	els.set_lights(true)
	els.cycle_pattern(1)
	_check("PTRN toast text", noticed.size() > 0 and noticed[noticed.size() - 1] == "Stage 3: " + els.pattern_name())
	els.set_traffic_dir(&"left")
	_check("traffic advisor toast", noticed[noticed.size() - 1] == "Traffic advisor: left")
	els.set_traffic_dir(&"left")
	_check("traffic advisor off toast", noticed[noticed.size() - 1] == "Traffic advisor: off")
	els.notice.disconnect(cb)
	els.set_stage(1)
	var stage1: Array = els.row_colors(0.5)
	var front_dark := true
	for c in stage1[0]:
		if c != Color(0, 0, 0):
			front_dark = false
	_check("stage 1 never lights the FRONT row", front_dark)
	els.set_stage(3)
	_check("row_colors gives 4 rows of 10", els.row_colors(0.5).size() == 4 and (els.row_colors(0.5)[3] as PackedColorArray).size() == 10)

	# HUD: legacy panel, street visibility, overrides.
	hud.set_els_panel_style("legacy")
	await process_frame
	_check("legacy panel visible, overhaul hidden", hud.els_panel_legacy.visible and not hud.els_panel.visible)
	_click_local(hud.els_panel_legacy, Vector2(44.5 + 10.0, 124.5 + 8.0))
	_check("legacy stage box 2 click", els.stage == 2 and els.lights_on)
	hud.set_els_panel_style("overhaul")
	hud.set_street_visible(false)
	_check("street label hidden", not hud._street.visible and not hud._map_hint.visible)
	hud.set_street_visible(true)
	hud.set_speed(50.0)
	hud.override_values({"speed": 77.0})
	hud.set_speed(10.0)
	_check("override wins over set_speed", is_equal_approx(hud.gauges.speed, 77.0))
	hud.clear_overrides()
	hud.set_speed(10.0)
	_check("clear_overrides hands control back", is_equal_approx(hud.gauges.speed, 10.0))

	# Automatic pattern with the lights on and no siren: Bounce -> Slow alternate -> ... -> Rotator slow (holds).
	_check("idle auto pattern sequence", els.idle_pattern_at(1.0) == "Bounce" and els.idle_pattern_at(9.0) == "Slow alternate"
		and els.idle_pattern_at(17.0) == "Double alternate slow" and els.idle_pattern_at(25.0) == "Slow pulse together"
		and els.idle_pattern_at(33.0) == "Rotator slow" and els.idle_pattern_at(500.0) == "Rotator slow")
	els.set_siren(&"")
	els.set_lights(false)
	await process_frame
	els.set_pattern("")  # back to automatic
	els.set_lights(true)
	els.set_stage(3)
	await process_frame
	await process_frame
	_check("lights on without siren starts at Bounce", els.pattern_name() == "Bounce")
	els.set_siren(&"yelp")
	els.set_siren(&"")
	_check("after a siren the off pattern is Double cross", els.pattern_name() == "Double cross")
	els.set_lights(false)

	# Log lines expire by timer even when the 8-line cap already freed the label (no "lambda capture was freed" error).
	hud.clear_log()
	for i in 12:
		hud.add_log_line("line %d" % i, 0.25)
	await create_timer(0.6).timeout
	_check("log lines expired after their lifetime", hud._log_box.get_child_count() == 0)

	# Every siren tone loads and plays.
	for tone in sirens.TONES:
		sirens.play(tone)
		await process_frame
	_check("all tones accepted", sirens.tone == &"hyper_hilo" or sirens.tone == sirens.TONES[sirens.TONES.size() - 1])
	sirens.stop()
	quit(1 if _fail > 0 else 0)
