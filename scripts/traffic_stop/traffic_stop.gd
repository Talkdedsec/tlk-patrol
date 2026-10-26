extends Node
## Traffic stop flow: lights -> the car pulls over -> scene commands (M) -> the officer steps out and walks to the driver
## -> dialog panel -> decision -> score -> back to the car. Also the booking menu after a cuffed pursuit suspect.
## API: docs/api/traffic_stop.md.

const Ui := preload("res://scripts/mdt/ui_kit.gd")
const Adapters := preload("res://scripts/traffic_stop/adapters.gd")
const Overlay := preload("res://scripts/traffic_stop/stop_overlay.gd")
const Records := preload("res://scripts/traffic_stop/records.gd")
const Profiles := preload("res://scripts/traffic_stop/driver_profiles.gd")
const Charges := preload("res://scripts/traffic_stop/charges.gd")
const DialogModel := preload("res://scripts/traffic_stop/dialog_model.gd")
const PanelScene := preload("res://scenes/traffic_stop/dialog_panel.tscn")
const PullOver := preload("res://scripts/traffic_stop/pull_over.gd")
const RadioVoice := preload("res://scripts/calls/radio_voice.gd")

signal stop_started(vehicle: Node3D)
signal state_changed(state: StringName)
## The stopped car came to rest (also emitted for instant stops).
signal vehicle_stopped(vehicle: Node3D)
signal officer_on_foot
signal dialog_opened
signal dialog_closed
## result: {ruling (warning|citation|arrest), points, items, charges, fines, arrested, plate, name}
signal stop_finished(result: Dictionary)
signal booking_started(npc: Node)
signal booking_finished(result: Dictionary)
signal scene_command(index: int)

const AUTO_RANGE := 40.0        # TODO(tahmin): lights on with a car this close ahead starts a stop
const AUTO_MAX_MPH := 45.0      # TODO(tahmin): no automatic stop while the patrol car is faster than this
const RADIO_DELAY := 3.0        # lights on -> "traffic stop, plate ..."
const PULL_TIMEOUT := 25.0
const TALK_RANGE := 2.6
const CAR_RANGE := 3.4
const FLASHLIGHT_RANGE := 8.5   # the light comes on during the last ~5 s of the walk, about 8 m from the driver
const FLASHLIGHT_LINE_SECONDS := 4.5
const AVAILABLE_DELAY := 8.0    # TODO(tahmin): the status stays Busy until the end; here "10-8" follows 8 s after getting back in
# TODO(tahmin): only command 1 (PA text and result) was seen; commands 2-8 and their texts are our own.
const SCENE_COMMAND_TEXT: Array[String] = [
	"PA: \"Driver, pull forward a little more and stop.\"",
	"PA: \"Driver, pull into the next street on your right and stop.\"",
	"PA: \"Driver, follow me.\"",
	"PA: \"Driver, stop right there.\"",
	"Flares are out: traffic is slowing past the stop.",
	"Flares are out: the lane is closed.",
	"Road closed: traffic is detouring.",
	"Flares picked up.",
]

enum State { IDLE, PULLING_OVER, STOPPED, ON_FOOT, DIALOG, WRAP_UP, BOOKING }
const STATE_NAMES := [&"idle", &"pulling_over", &"stopped", &"on_foot", &"dialog", &"wrap_up", &"booking"]

var state: int = State.IDLE
var vehicle: Node3D
var driver: Node3D
var record: Dictionary = {}
var profile: Dictionary = {}
var dialog: DialogModel
var dialog_open: bool = false
## Start a stop by itself when the lights are on and a car stays ahead of the patrol car.
var auto_detect: bool = true
## Go back to Available (10-8) a few seconds after the officer is back in the car.
var auto_available: bool = true
## Node that hosts the dialog panel (default: the tree root).
var ui_parent: Node = null
var rng := RandomNumberGenerator.new()
var dialog_voice: Node
var scene_commands_open: bool = false
## Show "Suspect cuffed..." and "E  Process the suspect" here instead of in Pursuit (off: Pursuit draws them).
var own_booking_ui: bool = false

var _overlay: CanvasLayer
var _layer: CanvasLayer
var _panel: Control
var _pull: Node
var _violation: StringName = &""
var _finished := false
## Distance to the driver at which the flashlight comes on by itself while walking up (metres).
var flashlight_range: float = FLASHLIGHT_RANGE
var flashlight_on: bool = false
var _flashlight_seen := false
var _line_token := 0
var _prompt_target: StringName = &""
var _scan_time := 0.0
var _lock_timer := 0.0
var _lock_vehicle: Node3D
var _recent: Dictionary = {}
var _flares: Array[Node3D] = []
var _booking_npc: Node3D
var _booking_charges: Array = []
var _booking_model: DialogModel
var _booking_ready := false
var _begin_token := 0
var _talked := false
var _traffic_pull := false
var _driver_aboard := true
var _rest_time := 0.0
var _releasing := false


func _ready() -> void:
	rng.randomize()
	dialog_voice = RadioVoice.new()
	dialog_voice.name = "DialogVoice"
	add_child(dialog_voice)
	_register_actions()
	_late_setup.call_deferred()


func _late_setup() -> void:
	_overlay = Overlay.of(get_tree())
	if Pursuit.has_signal("suspect_cuffed"):
		Pursuit.connect("suspect_cuffed", _on_suspect_cuffed)
	if Pursuit.has_signal("process_requested"):
		Pursuit.connect("process_requested", _on_process_requested)


func _register_actions() -> void:
	for pair in [["scene_commands", KEY_M], ["flashlight", KEY_4], ["exit_vehicle", KEY_F]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var event := InputEventKey.new()
			event.physical_keycode = pair[1] as Key
			InputMap.action_add_event(pair[0], event)


# --- public API ---------------------------------------------------------------------------------------

## Starts a stop on a vehicle. opts: profile (Dictionary or &"showcase"), violation (StringName from DriverProfiles.VIOLATIONS),
## instant (skip the pull-over), lights (false: do not touch ELS), siren (tone id such as &"wail"), announce (false: no radio),
## flee (true: hand over to Pursuit).
func begin(target: Node3D, opts: Dictionary = {}) -> bool:
	if state != State.IDLE or target == null:
		return false
	vehicle = target
	_finished = false
	_talked = false
	_violation = StringName(opts.get("violation", target.get_meta("violation", &"")))
	record = record_for(target)
	var chosen: Variant = opts.get("profile", null)
	if chosen is Dictionary:
		profile = chosen
	elif chosen == &"showcase" or String(record["plate"]) == "KEA-9291":
		profile = Profiles.showcase()
	else:
		var seeded := RandomNumberGenerator.new()
		seeded.seed = hash(String(record["plate"]) + "profile")
		profile = Profiles.make(Profiles.random_kind(seeded), record, seeded, _violation)
	if opts.get("lights", true) and not Els.lights_active():
		Els.set_stage(2)
		Els.set_lights(true)
	if opts.has("siren"):
		Els.set_siren(StringName(opts["siren"]))  # the showcase stop runs lights only; a siren tone is optional
	_traffic_pull = false
	_rest_time = 0.0
	_pull = PullOver.new()
	add_child(_pull)
	_pull.attach(vehicle)
	_pull.stopped.connect(_on_vehicle_stopped)
	_set_state(State.PULLING_OVER)
	stop_started.emit(vehicle)
	_begin_token += 1
	var token := _begin_token
	if opts.get("flee", false):
		_hand_to_pursuit()
		return true
	if opts.get("announce", true):
		_announce_after(token, RADIO_DELAY)
	var at_rest := Adapters.speed_mph(vehicle) < 1.0
	if opts.get("instant", false) or at_rest:
		# Already stopped (Pursuit.target_yielded, scenarios): take the car over where it stands.
		Adapters.hold_vehicle_ai(vehicle, true)
		_pull.hold()
		_on_vehicle_stopped.call_deferred()
	elif Adapters.traffic_pull_over(vehicle):
		_traffic_pull = true  # the Traffic module signals right and parks; we wait for the car to come to rest
		_timeout_pull(token)
	else:
		Adapters.hold_vehicle_ai(vehicle, true)
		_pull.pull_over()
		_timeout_pull(token)
	return true


## Ends the stop without a ruling (the car goes back to traffic).
func cancel() -> void:
	if state == State.IDLE:
		return
	close_dialog()
	_cleanup_stop(true)


## Vehicle record (plate, model, owner, flags) used by plate runs and the dialog. Stored in the vehicle's "mdt_record" meta.
func record_for(target: Node) -> Dictionary:
	if target.has_meta("mdt_record"):
		return target.get_meta("mdt_record")
	var plate := Adapters.plate_of(target)
	if plate.is_empty():
		plate = Records.random_plate(rng)
		target.set_meta("plate", plate)
	var rec := Records.showcase() if plate == "KEA-9291" else Records.for_plate(plate, Adapters.model_of(target))
	target.set_meta("mdt_record", rec)
	return rec


func plate_reply_text(rec: Dictionary) -> String:
	return Records.reply_text(Calls.unit_name, rec)


func plate_result_lines(rec: Dictionary) -> PackedStringArray:
	return Records.result_lines(rec)


## Tells the stop that the Traffic module saw a violation before the lights came on ("speeding", "lane", ...).
func report_violation(target: Node, violation: StringName) -> void:
	target.set_meta("violation", violation)


## Scene command 1..8 (the M menu).
func command(index: int) -> void:
	if vehicle == null or index < 1 or index > 8:
		return
	_toast(SCENE_COMMAND_TEXT[index - 1], 3.0)
	if index <= 4 and index != 3:
		dialog_voice.speak(&"pa", SCENE_COMMAND_TEXT[index - 1].trim_prefix("PA: ").replace("\"", ""))
	match index:
		1:
			_pull.creep(8.0)
		2:
			_pull.turn_right_into_side_street()
		3:
			var mine := Adapters.player_vehicle(get_tree())
			if mine != null:
				_pull.follow(mine)
			dialog_voice.speak(&"pa", "Driver, follow me.")
		4:
			_pull.hold()
		5:
			_place_flares(3, &"slow")
		6:
			_place_flares(6, &"close_lane")
		7:
			_place_flares(8, &"detour")
		8:
			_clear_flares()
	scene_command.emit(index)


func set_scene_commands(open: bool) -> void:
	scene_commands_open = open
	if open and vehicle != null:
		_overlay.show_scene_commands(String(record.get("plate", "")))
	else:
		_overlay.hide_scene_commands()


## Opens the dialog panel for the current stop.
func open_dialog() -> void:
	if vehicle == null or state == State.IDLE or state == State.PULLING_OVER:
		return
	if dialog == null:
		dialog = DialogModel.new()
		dialog.setup(record, profile, {"vehicle": true})
		dialog.entry_added.connect(_on_entry)
		dialog.action_requested.connect(_on_action)
		dialog.finished.connect(_on_dialog_finished)
	_show_panel(dialog)
	if not _talked:
		_talked = true
		dialog_voice.speak(&"driver", dialog.greeting())
	if state != State.WRAP_UP:
		_set_state(State.DIALOG)


func close_dialog() -> void:
	if not dialog_open:
		return
	dialog_open = false
	_panel.close()
	_layer.visible = false
	Adapters.cursor_pop()
	dialog_closed.emit()
	if state == State.DIALOG:
		_set_state(State.ON_FOOT)


## Booking menu for a cuffed suspect (Pursuit.suspect_cuffed -> E "Process the suspect").
## charges: ids or display names; the evidence ones are pre-checked and count as supported.
func begin_booking(npc: Node3D, charges: Array = [], opts: Dictionary = {}) -> void:
	if state == State.BOOKING and _booking_npc == npc:
		return  # Pursuit.process_requested and auto_book may both ask
	_booking_npc = npc
	_booking_ready = false
	_overlay.set_prompt("")
	var rec: Dictionary
	var suspect_vehicle: Variant = Pursuit.get("target")
	if npc != null and npc.has_meta("mdt_record"):
		rec = npc.get_meta("mdt_record")
	elif not opts.has("plate") and suspect_vehicle is Node3D and is_instance_valid(suspect_vehicle):
		rec = record_for(suspect_vehicle)  # the car the suspect bailed from
	else:
		var plate: String = opts.get("plate", String(Pursuit.get("suspect_plate")) if String(Pursuit.get("suspect_plate")) != "" else Records.random_plate(rng))
		rec = Records.for_plate(plate, String(opts.get("model", "Halvorsen Ranger SUV")))
	var ids: Array = []
	for value in charges:
		var id := Charges.resolve(value)
		if id != &"" and not ids.has(id):
			ids.append(id)
	if ids.is_empty():
		ids = [&"evading", &"fleeing_foot", &"resisting"]
	var suspect: Dictionary = opts.get("profile", Profiles.make(&"hostile", rec, rng, &""))
	_booking_model = DialogModel.new()
	_booking_model.setup(rec, suspect, {"booking": true, "vehicle": opts.get("vehicle", true), "evidence": ids})
	_booking_model.entry_added.connect(_on_entry)
	_booking_model.action_requested.connect(_on_action)
	_booking_model.finished.connect(_on_booking_done)
	dialog = _booking_model
	record = rec
	profile = suspect
	_set_state(State.BOOKING)
	_show_panel(_booking_model)
	booking_started.emit(npc)


# --- state ----------------------------------------------------------------------------------------------

func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(STATE_NAMES[new_state])


func state_name() -> StringName:
	return STATE_NAMES[state]


func _announce_after(token: int, seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	if token != _begin_token or vehicle == null:
		return
	Calls.radio_unit("traffic stop, plate %s." % record["plate"])
	Calls.radio_dispatch("received, %s, traffic stop near %s." % [Calls.unit_name, Adapters.district_name(get_tree())])
	Calls.stats["stops"] += 1


func _timeout_pull(token: int) -> void:
	await get_tree().create_timer(PULL_TIMEOUT).timeout
	if token == _begin_token and state == State.PULLING_OVER:
		_pull.hold()
		_on_vehicle_stopped()


func _hand_to_pursuit() -> void:
	var target := vehicle
	_cleanup_stop(false)
	if Pursuit.has_method("start"):
		Pursuit.call("start", target)


func _on_vehicle_stopped() -> void:
	if state != State.PULLING_OVER:
		return
	if _traffic_pull:
		Adapters.hold_vehicle_ai(vehicle, true)
		_pull.hold()
	_set_state(State.STOPPED)
	driver = Adapters.spawn_driver(vehicle)
	vehicle_stopped.emit(vehicle)


func _on_officer_on_foot() -> void:
	_set_state(State.ON_FOOT)
	Calls.set_status(&"busy", true)  # "Status: Busy" toast, 10-6 on the radio
	Adapters.hud_set_vehicle(get_tree(), false)
	set_scene_commands(false)
	officer_on_foot.emit()


func _on_officer_in_vehicle() -> void:
	if _releasing:
		return
	_overlay.set_prompt("")
	_overlay.set_flashlight_line(false)
	Adapters.hud_set_vehicle(get_tree(), true)
	flashlight_on = false
	_flashlight_seen = false
	if state == State.WRAP_UP or _finished:
		_release_vehicle()
		if auto_available:
			_available_later()
	elif state == State.ON_FOOT:
		_set_state(State.STOPPED)


func _available_later() -> void:
	await get_tree().create_timer(AVAILABLE_DELAY).timeout
	if state == State.IDLE:
		Calls.set_status(&"available", true)


# --- driver and car ----------------------------------------------------------------------------------------

func _driver_steps_out() -> void:
	if driver == null:
		return
	_driver_aboard = false
	Adapters.open_driver_door(vehicle, true)
	Adapters.npc_stand(driver, vehicle)
	driver.global_position = Adapters.driver_door_position(vehicle)
	Adapters.npc_walk(driver, Adapters.driver_stand_position(vehicle), 1.6)
	await get_tree().create_timer(2.2).timeout
	if driver != null and is_instance_valid(driver):
		var who := Adapters.player(get_tree())
		if who != null:
			Adapters.npc_face(driver, who.global_position)
		Adapters.npc_talk(driver, &"talk_a")
	Adapters.open_driver_door(vehicle, false)


func _driver_boards() -> void:
	if driver == null or not is_instance_valid(driver):
		return
	if _driver_aboard:
		return
	_driver_aboard = true
	Adapters.open_driver_door(vehicle, true)
	Adapters.npc_walk(driver, Adapters.driver_door_position(vehicle), 1.8)
	await get_tree().create_timer(2.4).timeout
	if driver != null and is_instance_valid(driver) and vehicle != null:
		Adapters.npc_sit(driver, vehicle)
		Adapters.open_driver_door(vehicle, false)


func _release_vehicle() -> void:
	if vehicle == null:
		_cleanup_stop(false)
		return
	var leaving := vehicle
	_clear_flares()
	await _driver_boards()
	if _pull != null and is_instance_valid(leaving):
		_pull.creep(90.0)
	_set_state(State.IDLE)
	await get_tree().create_timer(7.0).timeout
	if is_instance_valid(leaving):
		Adapters.hold_vehicle_ai(leaving, false)
	_recent[leaving] = Time.get_ticks_msec()
	_cleanup_stop(false)


func _cleanup_stop(release_ai: bool) -> void:
	if _pull != null and is_instance_valid(_pull):
		_pull.queue_free()
	_pull = null
	if release_ai and vehicle != null and is_instance_valid(vehicle):
		Adapters.hold_vehicle_ai(vehicle, false)
	if driver != null and is_instance_valid(driver) and driver.get_parent() != null and driver.is_in_group("npc"):
		driver.queue_free()
	driver = null
	vehicle = null
	dialog = null
	_overlay.set_prompt("")
	_overlay.hide_scene_commands()
	scene_commands_open = false
	_set_state(State.IDLE)


func _place_flares(count: int, mode: StringName) -> void:
	_clear_flares()
	if vehicle == null:
		return
	var fwd := Adapters.forward(vehicle)
	var right := Adapters.right(vehicle)
	var base := vehicle.global_position - fwd * 10.0
	for i in count:
		var flare := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.04
		mesh.bottom_radius = 0.05
		mesh.height = 0.28
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("FF2A1A")
		material.emission_enabled = true
		material.emission = Color("FF2A1A")
		material.emission_energy_multiplier = 3.0
		mesh.material = material
		flare.mesh = mesh
		var spread := float(i) / maxf(count - 1, 1.0)
		var offset := base - fwd * (4.0 * i) + right * (2.5 - 3.0 * spread if mode != &"slow" else 1.2)
		flare.global_position = Vector3(offset.x, vehicle.global_position.y + 0.14, offset.z)
		vehicle.get_parent().add_child(flare)
		_flares.append(flare)
	Adapters.traffic_zone(get_tree(), base, 28.0, &"slow" if mode == &"slow" else &"closed")


func _clear_flares() -> void:
	for flare in _flares:
		if is_instance_valid(flare):
			flare.queue_free()
	_flares.clear()
	Adapters.traffic_zone(get_tree(), Vector3.ZERO, 0.0, &"clear")


# --- panel -----------------------------------------------------------------------------------------------------

func _show_panel(model: DialogModel) -> void:
	if _layer == null or not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.layer = 18
		_panel = PanelScene.instantiate()
		_layer.add_child(_panel)
		var host: Node = ui_parent if ui_parent != null and is_instance_valid(ui_parent) else get_tree().root
		host.add_child(_layer)
	_layer.visible = true
	_panel.open(model)
	if not dialog_open:
		dialog_open = true
		Adapters.cursor_push()
		dialog_opened.emit()


func _on_entry(_bbcode: String, speaker: StringName, spoken: String) -> void:
	if spoken.is_empty():
		return
	if speaker == &"you":
		dialog_voice.speak(&"you", spoken)
	elif speaker == &"driver":
		dialog_voice.speak(&"driver", spoken)


func _on_action(action: StringName, args: Dictionary) -> void:
	match action:
		&"step_out":
			_driver_steps_out()
		&"vehicle_command":
			command(int(args["index"]))
		&"mdt_lines":
			for line in args["lines"]:
				Mdt.add_plate_line(String(line))
		&"step_away":
			close_dialog()
		&"warning", &"citation", &"arrest":
			if action == &"arrest" and dialog != null and dialog.mode == DialogModel.Mode.STOP:
				Calls.radio_unit("one in custody, transporting to booking.")
				Calls.radio_dispatch("10-4, %s." % Calls.unit_name)
			_apply_result(args["result"])


func _on_dialog_finished(result: Dictionary) -> void:
	if _finished:
		close_dialog()
		return
	_finished = true
	close_dialog()
	_set_state(State.WRAP_UP)
	_driver_boards()
	stop_finished.emit(result)


## Score, toast and counters at the moment of the ruling (score and toast change at the click, Done comes later).
func _apply_result(result: Dictionary) -> void:
	var points: int = result["points"]
	Calls.add_score(points)
	_toast("Stop complete: %+d points" % points, 3.0)
	if result.get("booking", false):
		Calls.stats["arrests"] += 1
		Calls.radio_unit("10-15.")
		_booked_later()
		return
	match result["ruling"]:
		&"warning":
			Calls.stats["warnings"] += 1
		&"citation":
			Calls.stats["citations"] += 1
		&"arrest":
			Calls.stats["arrests"] += 1
			_booked_later()


func _booked_later() -> void:
	await get_tree().create_timer(20.0).timeout
	Calls.radio_unit("my prisoner's booked, show me 10-8.")
	Calls.radio_dispatch("10-4, %s." % Calls.unit_name)


func _on_booking_done(result: Dictionary) -> void:
	close_dialog()
	booking_finished.emit(result)
	_booking_npc = null
	_booking_model = null
	dialog = null
	_set_state(State.IDLE)


func _toast(text: String, seconds: float) -> void:
	if _overlay != null:
		_overlay.toast(text, seconds)


# --- pursuit hook ------------------------------------------------------------------------------------------------

## E on the cuffed suspect ("E  Process the suspect", drawn by Pursuit): open the booking menu.
func _on_process_requested(npc: Node3D, charges: Array) -> void:
	begin_booking(npc, charges)


func _on_suspect_cuffed(npc: Node3D) -> void:
	_booking_npc = npc
	if not own_booking_ui:
		return  # Pursuit shows "Suspect cuffed..." and "E  Process the suspect", then calls begin_booking()
	_booking_ready = true
	var charges: Array = []
	if npc != null and npc.has_meta("charges"):
		charges = npc.get_meta("charges")
	_booking_charges = charges
	_toast("Suspect cuffed. E to process them and book the charges.", 6.0)


# --- per-frame: detection, prompts, flashlight ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _overlay == null:
		return
	if state == State.PULLING_OVER and _traffic_pull and vehicle != null:
		_rest_time = _rest_time + delta if Adapters.speed_ms(vehicle) < 0.4 else 0.0
		if _rest_time > 1.0:
			_on_vehicle_stopped()
	_scan_time -= delta
	if _scan_time <= 0.0:
		_scan_time = 0.2
		_scan_for_stop(0.2)
		_follow_player_state()
	_update_prompt()


func _scan_for_stop(step: float) -> void:
	if not auto_detect or state != State.IDLE or not Els.lights_active() or Pursuit.is_active():
		_lock_vehicle = null
		_lock_timer = 0.0
		return
	var mine := Adapters.player_vehicle(get_tree())
	if mine == null or not Adapters.player_in_vehicle(get_tree()):
		return
	if Adapters.speed_mph(mine) > AUTO_MAX_MPH:
		return
	var candidate := Adapters.vehicle_ahead(get_tree(), mine, AUTO_RANGE, 14.0)
	var marked: Variant = Pursuit.get("_marked")  # an ALPR-marked car belongs to Pursuit (it starts the stop or the chase)
	if marked is Dictionary and (marked as Dictionary).has("vehicle") and (marked as Dictionary)["vehicle"] == candidate:
		return
	if candidate == null or candidate.get_meta("stop_hold", false) or candidate.get_meta("stop_ignore", false):
		_lock_vehicle = null
		_lock_timer = 0.0
		return
	if _recent.has(candidate) and Time.get_ticks_msec() - int(_recent[candidate]) < 60000:
		return
	if candidate != _lock_vehicle:
		_lock_vehicle = candidate
		_lock_timer = 0.0
	_lock_timer += step
	if _lock_timer >= 1.0:
		_lock_vehicle = null
		begin(candidate)


## Notices the officer leaving or entering the car (the Officer module or the test stage does the actual move).
func _follow_player_state() -> void:
	if vehicle == null:
		return
	var in_car := Adapters.player_in_vehicle(get_tree())
	if not in_car and (state == State.STOPPED):
		_on_officer_on_foot()
	elif in_car and (state == State.ON_FOOT or state == State.WRAP_UP):
		_on_officer_in_vehicle()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action("scene_commands") and vehicle != null and state != State.IDLE:
		set_scene_commands(not scene_commands_open)
		get_viewport().set_input_as_handled()
		return
	if scene_commands_open and event is InputEventKey:
		var index := int(event.physical_keycode) - int(KEY_0)
		if index >= 1 and index <= 8:
			command(index)
			get_viewport().set_input_as_handled()
			return
	if event.is_action("flashlight") and not scene_commands_open and state != State.IDLE:
		set_flashlight(not flashlight_on)
		get_viewport().set_input_as_handled()
		return
	if event.is_action("interact"):
		_interact()


func _interact() -> void:
	match _prompt_target:
		&"talk":
			if _finished and state == State.WRAP_UP:
				_toast("Driver: \"Thank you, officer.\"", 2.0)
				dialog_voice.speak(&"driver", "Thank you, officer.")
			else:
				open_dialog()
		&"get_in":
			Adapters.player_enter_vehicle(get_tree(), Adapters.player_vehicle(get_tree()))
		&"process":
			begin_booking(_booking_npc, _booking_charges)


func _update_prompt() -> void:
	var text := ""
	_prompt_target = &""
	var who := Adapters.player(get_tree())
	if who != null and not dialog_open and not Adapters.player_in_vehicle(get_tree()):
		var here := who.global_position
		if _booking_ready and _booking_npc != null and is_instance_valid(_booking_npc) and here.distance_to(_booking_npc.global_position) < 3.2:
			text = "E  Process the suspect"
			_prompt_target = &"process"
		elif vehicle != null and state in [State.ON_FOOT, State.WRAP_UP, State.STOPPED]:
			var talk_point := Adapters.driver_door_position(vehicle)
			if driver != null and driver.visible:
				talk_point = driver.global_position
			var mine := Adapters.player_vehicle(get_tree())
			var to_driver := here.distance_to(talk_point)
			var to_car := here.distance_to(Adapters.patrol_door_position(mine)) if mine != null else 999.0
			if to_driver < TALK_RANGE and to_driver <= to_car:
				text = "E  Talk" if (_talked or _finished) else "E  Talk to the driver"
				_prompt_target = &"talk"
			elif to_car < CAR_RANGE:
				text = "E  Get in"
				_prompt_target = &"get_in"
			if state == State.ON_FOOT and not _flashlight_seen and to_driver < flashlight_range:
				set_flashlight(true)
		elif Adapters.player_vehicle(get_tree()) != null:
			var d := here.distance_to(Adapters.patrol_door_position(Adapters.player_vehicle(get_tree())))
			if d < CAR_RANGE:
				text = "E  Get in"
				_prompt_target = &"get_in"
	if _overlay.prompt_text() != text:
		_overlay.set_prompt(text)


## Flashlight on/off (the `4` key). Turning it on shows the green "Flashlight on   4 off" line for 4.5 s (show_line).
## The stop turns it on by itself once when the officer comes within `flashlight_range` of the driver.
func set_flashlight(on: bool, show_line: bool = true) -> void:
	flashlight_on = on
	if on:
		_flashlight_seen = true
	Adapters.player_flashlight(get_tree(), on)
	_line_token += 1
	if not on or not show_line:
		_overlay.set_flashlight_line(false)
		return
	var token := _line_token
	_overlay.set_flashlight_line(true)
	await get_tree().create_timer(FLASHLIGHT_LINE_SECONDS).timeout
	if token == _line_token:
		_overlay.set_flashlight_line(false)
