extends Node
## Mobile Data Terminal (Tab / Esc). Four tabs: DISPATCH (assigned call + radio traffic), CALLS, PLATES, UNIT.
## The terminal does not pause anything: the car can still be driven. API: docs/api/mdt.md.
## CALLS and UNIT tabs are our own design (tahmin).

const Ui := preload("res://scripts/mdt/ui_kit.gd")
const MdtWindow := preload("res://scripts/mdt/mdt_window.gd")
const WindowScene := preload("res://scenes/mdt/mdt_window.tscn")
const Adapters := preload("res://scripts/traffic_stop/adapters.gd")
const Catalog := preload("res://scripts/calls/call_catalog.gd")

signal opened
signal closed
signal tab_changed(tab: StringName)
## Emitted when a plate run finishes; result is the vehicle record (see TrafficStop.record_for).
signal plate_result(result: Dictionary)

const PLATE_DELAY_REPLY := 2.0   # dispatch reply logged ~2 s after the click
const PLATE_DELAY_RESULT := 3.5  # MDT result 3-4 s after the click
const MAX_TRAFFIC := 400

var is_open: bool = false
var tab: StringName = &"dispatch"
## Node that hosts the window (default: the tree root). Set before the first open to render in a SubViewport.
var ui_parent: Node = null
## Radio traffic list: {stamp, kind (dispatch|unit|me), text}
var traffic: Array[Dictionary] = []
var plate_busy: bool = false

var _layer: CanvasLayer
var _window: MdtWindow
var _plate_lines: PackedStringArray = []
var _clock_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Dispatch.line_added.connect(_on_dispatch_line)
	for line in Dispatch.lines:
		_record_line(line, "")


## Opens the terminal. tab: &"dispatch", &"calls", &"plates", &"unit" (empty keeps the last tab).
func open(tab_id: StringName = &"") -> void:
	if not tab_id.is_empty():
		tab = tab_id
	_ensure_window()
	_window.show_tab(tab)
	_layer.visible = true
	if not is_open:
		is_open = true
		Adapters.cursor_push()
		_connect_live()
		opened.emit()
	refresh()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_layer.visible = false
	Adapters.cursor_pop()
	closed.emit()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func show_tab(tab_id: StringName) -> void:
	tab = tab_id
	if _window != null:
		_window.show_tab(tab_id)


func window() -> Control:
	return _window


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if is_open and (event.is_action("close_menu") or event.is_action("toggle_mdt")):
		close()
		get_viewport().set_input_as_handled()
	elif not is_open and event.is_action("toggle_mdt") and not _blocked():
		open()
		get_viewport().set_input_as_handled()


func _blocked() -> bool:
	return TrafficStop.dialog_open


func _process(delta: float) -> void:
	if not is_open:
		return
	_clock_timer -= delta
	if _clock_timer <= 0.0:
		_clock_timer = 0.5
		_refresh_header()


# --- plates --------------------------------------------------------------------------------------------

## Same as pressing "RUN THE PLATE OF THE VEHICLE AHEAD": the stopped car, else the car ahead of the patrol car.
func run_plate_ahead() -> void:
	var target: Node3D = TrafficStop.vehicle
	if target == null:
		var mine := Adapters.player_vehicle(get_tree())
		if mine != null:
			target = Adapters.vehicle_ahead(get_tree(), mine, 80.0, 25.0)
	if target == null:
		_add_plate_text("%s  No vehicle ahead." % Calls.stamp())
		return
	run_plate(target)


## Runs a plate for a vehicle: radio request, dispatch reply, then the MDT result block.
func run_plate(vehicle: Node3D) -> void:
	if plate_busy:
		return
	plate_busy = true
	var record: Dictionary = TrafficStop.record_for(vehicle)
	var plate: String = record["plate"]
	if _window != null:
		_window.set_plate_busy(true)
	_add_plate_text(Ui.tint("%s  Running plate %s..." % [Calls.stamp(), plate], Ui.MDT_FOOTER))
	Calls.radio_unit("run a 10-28 for me, %s." % plate)
	await get_tree().create_timer(PLATE_DELAY_REPLY).timeout
	Calls.radio_dispatch(TrafficStop.plate_reply_text(record))
	await get_tree().create_timer(PLATE_DELAY_RESULT - PLATE_DELAY_REPLY).timeout
	for line in TrafficStop.plate_result_lines(record):
		_add_plate_text(line)
	plate_busy = false
	if _window != null:
		_window.set_plate_busy(false)
	plate_result.emit(record)


## Appends a line to the PLATES result log (BBCode allowed).
func add_plate_line(bbcode: String) -> void:
	_add_plate_text(bbcode)


func clear_plate_log() -> void:
	_plate_lines.clear()
	_refresh_plates()


func _add_plate_text(bbcode: String) -> void:
	_plate_lines.append(bbcode)
	_refresh_plates()


func _refresh_plates() -> void:
	if _window != null:
		_window.set_plate_log("\n".join(_plate_lines))


# --- radio traffic ---------------------------------------------------------------------------------------

## Adds a radio traffic line manually (history seeding for scenarios). stamp "" uses the game clock.
func add_traffic(text: String, stamp: String = "") -> void:
	_record_line(text, stamp if not stamp.is_empty() else Calls.stamp())


func clear_traffic() -> void:
	traffic.clear()
	if _window != null:
		_window.set_traffic(traffic)


func _on_dispatch_line(text: String) -> void:
	_record_line(text, Calls.stamp())


func _record_line(text: String, stamp: String) -> void:
	var kind := &"unit"
	if text.begins_with("Dispatch:"):
		kind = &"dispatch"
	elif text.begins_with(Calls.unit_name + ":"):
		kind = &"me"
	var entry := {"stamp": stamp, "kind": kind, "text": text}
	traffic.append(entry)
	if traffic.size() > MAX_TRAFFIC:
		traffic.remove_at(0)
	if _window != null:
		_window.add_traffic(entry)


# --- window -------------------------------------------------------------------------------------------------

func _ensure_window() -> void:
	if _window != null and is_instance_valid(_window):
		return
	_layer = CanvasLayer.new()
	_layer.layer = 20
	_layer.visible = false
	_window = WindowScene.instantiate() as MdtWindow
	_layer.add_child(_window)
	var host: Node = ui_parent if ui_parent != null and is_instance_valid(ui_parent) else get_tree().root
	host.add_child(_layer)
	_window.run_plate_pressed.connect(run_plate_ahead)
	_window.respond_pressed.connect(Calls.respond)
	_window.pass_pressed.connect(Calls.pass_offer)
	_window.tab_changed.connect(_on_tab_changed)
	_window.set_traffic(traffic)
	_refresh_plates()


func _connect_live() -> void:
	if not Calls.changed.is_connected(refresh):
		Calls.changed.connect(refresh)
		GameState.changed.connect(_refresh_header)


func _on_tab_changed(id: StringName) -> void:
	tab = id
	refresh()
	tab_changed.emit(id)


## Redraws every page from the current game state.
func refresh() -> void:
	if _window == null:
		return
	_refresh_header()
	_window.set_call(Calls.current)
	_refresh_calls()
	_refresh_unit()
	_window.scroll_traffic_to_end()


func _refresh_header() -> void:
	if _window != null:
		_window.set_header(Calls.unit_name, "Busy" if Calls.status == &"busy" else "Available", Calls.stamp())


func _refresh_calls() -> void:
	var pending := Calls.offer_call
	if pending.is_empty():
		_window.set_offer("No call waiting for an answer.", false)
	else:
		_window.set_offer("Code %d: %s  near %s" % [pending["code"], pending["title"], pending["location"]], true)
	var rows: Array = []
	for i in range(Calls.history.size() - 1, maxi(Calls.history.size() - 15, -1), -1):
		var call: Dictionary = Calls.history[i]
		var color := Ui.FAIL_RED if call.get("emergency", false) else Ui.MDT_DISPATCH
		rows.append([
			Ui.tint(String(call.get("time", "")), Ui.MDT_STAMP), Ui.tint(str(call["code"]), color),
			Ui.tint(String(call["title"]), Ui.MDT_TEXT), Ui.tint(String(call["location"]), Ui.MDT_UNIT),
			Ui.tint(String(call.get("status", &"")).replace("_", " "), _status_color(StringName(call.get("status", &"")))),
		])
	if rows.is_empty():
		rows.append(["", "", Ui.tint("No calls yet this shift. Offers come in over the radio.", Ui.MDT_UNIT), "", ""])
	_window.set_calls_table(rows)


func _status_color(status: StringName) -> Color:
	match status:
		&"assigned", &"on_scene":
			return Ui.MDT_ME
		&"offered":
			return Ui.AMBER
		&"cleared":
			return Ui.MDT_GREEN
	return Ui.MDT_UNIT


func _refresh_unit() -> void:
	var vehicle_line := "Vehicle: not assigned"
	var mine := Adapters.player_vehicle(get_tree())
	if mine != null:
		vehicle_line = "Vehicle: %s  %s" % [Adapters.model_of(mine, "Patrol vehicle"), Adapters.plate_of(mine)]
	var status_text := "BUSY" if Calls.status == &"busy" else "AVAILABLE"
	var status_color := Ui.AMBER if Calls.status == &"busy" else Ui.MDT_GREEN
	var s: Dictionary = Calls.stats
	var left := "[b]%s[/b]\n%s\n\n%s\n%s\n\nCalls answered  %d\nCalls passed  %d\nTraffic stops  %d\nWarnings  %d\nCitations  %d\nArrests  %d\n\nScore  %d" % [
		Ui.tint(Calls.unit_name.to_upper(), Ui.MDT_TEXT), Ui.tint(status_text, status_color),
		Ui.tint(vehicle_line, Ui.MDT_UNIT), Ui.tint(_els_line(), Ui.MDT_UNIT),
		s["calls"], s["passed"], s["stops"], s["warnings"], s["citations"], s["arrests"], GameState.score]
	var units: Array = []
	var minute_slot := floori(GameState.minutes / 10.0)
	for unit in Catalog.UNITS:
		# TODO(tahmin): other units' status is decorative, derived from a hash of the call sign and the game clock.
		var roll := hash("%s%d" % [unit, minute_slot]) % 5
		var state := "available" if roll < 2 else ("busy" if roll == 2 else ("en route" if roll == 3 else "on scene"))
		units.append([Ui.tint(unit, Ui.MDT_UNIT), Ui.tint(state, Ui.MDT_STAMP)])
	_window.set_unit_texts(left, units)


func _els_line() -> String:
	var els := get_node_or_null("/root/Els")
	if els == null or not els.has_method("status_lines"):
		return "Lights: off"
	var lines: PackedStringArray = els.call("status_lines")
	return "Lights: " + lines[0] if lines.size() > 0 else "Lights: off"
