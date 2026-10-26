extends Node
## Calls: call offers (Y respond / N pass), assignment and duty status, the EMERGENCY band with its alert beep,
## the nearby chase notice, radio speech and ambient radio traffic. API: docs/api/calls.md.

const Catalog := preload("res://scripts/calls/call_catalog.gd")
const RadioVoice := preload("res://scripts/calls/radio_voice.gd")
const SpeechText := preload("res://scripts/calls/speech_text.gd")
const Overlay := preload("res://scripts/traffic_stop/stop_overlay.gd")
const Adapters := preload("res://scripts/traffic_stop/adapters.gd")

signal changed
signal offer_started(call: Dictionary)
## result: &"responded", &"passed" or &"expired"
signal offer_ended(call: Dictionary, result: StringName)
signal call_started(call: Dictionary)
## outcome: &"cleared" or &"cancelled"
signal call_ended(call: Dictionary, outcome: StringName)
signal emergency_started(call: Dictionary)
signal status_changed(status: StringName)
signal chase_notice_changed(active: bool)
signal chase_join_requested
signal chase_called_off

const OFFER_SECONDS := 25.0
const EMERGENCY_BAND_SECONDS := 4.0  # band visible about 4 s
const CALL_SCORE := 10  # TODO(tahmin): no score is defined for completed calls
const ARRIVE_RADIUS := 25.0  # metres: a call with a "position" is reached inside this radius
# TODO(tahmin): without a world position the response is simulated: 10-97 after 25-45 s, clearing 30-60 s later.
const SIM_ARRIVE := Vector2(25.0, 45.0)
const SIM_CLEAR := Vector2(30.0, 60.0)
const ALERT_PATHS: Array[String] = ["res://assets/audio/weapons/alert_beep.wav", "res://assets/audio/radio/alert_beep.wav"]

## The player's call sign (MDT header, radio lines).
var unit_name: String = "1-Adam-12"
var status: StringName = &"available"
var offer_call: Dictionary = {}
var offer_left: float = 0.0
var current: Dictionary = {}
var history: Array[Dictionary] = []
var stats: Dictionary = {"calls": 0, "passed": 0, "stops": 0, "warnings": 0, "citations": 0, "arrests": 0}
## Ambient chatter of other units (assignments, 10-97, clearing) and automatic call offers; both off by default.
var ambient_enabled: bool = false
var auto_offers: bool = false
## Arrive and clear assigned calls by themselves (see SIM_ARRIVE); off for scenarios that call arrive()/complete().
var simulate_response: bool = true
var voice: Node
var rng := RandomNumberGenerator.new()

var _alert: AudioStreamPlayer
var _emergency_token := 0
var _ambient_timer := 12.0
var _offer_timer := 60.0
var _last_shown := -1
var _chase_active := false
var _chase_mi := 0.2
var _chase_token := 0
var _script_token := 0
var _overlay: CanvasLayer
var _arrive_timer := 0.0
var _clear_timer := 0.0
var _poll_timer := 0.0


func _ready() -> void:
	rng.randomize()
	voice = RadioVoice.new()
	voice.name = "RadioVoice"
	add_child(voice)
	_alert = AudioStreamPlayer.new()
	add_child(_alert)
	_register_actions()
	_overlay = Overlay.of(get_tree())
	Dispatch.line_added.connect(_on_log_line)


## Every line on the radio log is spoken (also the ones other modules log with Dispatch.say), queued in order.
## "Dispatch: ..." uses the dispatch voice, the player's call sign the officer voice, any other "<unit>: ..." a unit voice.
func _on_log_line(line: String) -> void:
	var split := line.find(": ")
	if split <= 0 or split > 48:
		return
	var speaker := line.substr(0, split)
	var kind: StringName = &"dispatch" if speaker == "Dispatch" else (&"officer" if speaker == unit_name else &"unit")
	voice.speak(kind, line.substr(split + 2))


func _register_actions() -> void:
	for pair in [["call_respond", KEY_Y], ["call_pass", KEY_N]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
			var event := InputEventKey.new()
			event.physical_keycode = pair[1] as Key
			InputMap.action_add_event(pair[0], event)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if not offer_call.is_empty():
		if event.is_action("call_respond"):
			respond()
			get_viewport().set_input_as_handled()
		elif event.is_action("call_pass"):
			pass_offer()
			get_viewport().set_input_as_handled()
	if _chase_active:
		if event.is_action("join_chase"):
			join_chase()
			get_viewport().set_input_as_handled()
		elif event.is_action("call_off"):
			call_off_chase()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not offer_call.is_empty():
		offer_left -= delta
		if offer_left <= 0.0:
			_expire_offer()
		else:
			var shown := ceili(offer_left)
			if shown != _last_shown:
				_last_shown = shown
				_refresh_offer_text()
	if not current.is_empty():
		_tick_response(delta)
	if auto_offers and offer_call.is_empty():
		_offer_timer -= delta
		if _offer_timer <= 0.0:
			_offer_timer = rng.randf_range(90.0, 170.0)
			offer()
	if ambient_enabled:
		_ambient_timer -= delta
		if _ambient_timer <= 0.0:
			_ambient_timer = rng.randf_range(25.0, 55.0)
			_ambient_assignment()


## Progress of the assigned call: 10-97 when the officer is at the call position, else after a simulated drive.
func _tick_response(delta: float) -> void:
	var status_now: StringName = current.get("status", &"")
	if status_now == &"assigned":
		if current.has("position"):
			_poll_timer -= delta
			if _poll_timer <= 0.0:
				_poll_timer = 0.5
				var who := Adapters.player(get_tree())
				if who != null and who.global_position.distance_to(current["position"]) < ARRIVE_RADIUS:
					arrive()
		elif simulate_response:
			_arrive_timer -= delta
			if _arrive_timer <= 0.0:
				arrive()
	elif status_now == &"on_scene" and simulate_response:
		_clear_timer -= delta
		if _clear_timer <= 0.0:
			complete()


# --- radio ----------------------------------------------------------------------------------------

## Logs "<speaker>: <text>" immediately (Dispatch log, HUD, MDT) and queues the speech.
## speaker "Dispatch" uses the dispatch voice, the player's call sign the officer voice, anything else a unit voice.
func radio(speaker: String, text: String) -> void:
	Dispatch.say("%s: %s" % [speaker, text])  # the voice follows through _on_log_line


func radio_unit(text: String) -> void:
	radio(unit_name, text)


func radio_dispatch(text: String) -> void:
	radio("Dispatch", text)


## Plays timed radio lines: entries [delay_seconds, speaker, text] (delay after the previous entry).
## For scenarios that replay a fixed timeline. Starting a new script cancels the previous one.
func play_script(entries: Array) -> void:
	_script_token += 1
	var token := _script_token
	for entry: Array in entries:
		await get_tree().create_timer(float(entry[0])).timeout
		if token != _script_token:
			return
		radio(String(entry[1]), String(entry[2]))


func stamp() -> String:
	return GameState.clock_text().substr(0, 5)


# --- duty status -----------------------------------------------------------------------------------

## Switches Available/Busy. announce: the stop flow says "show me 10-6" and shows the "Status: Busy" toast.
func set_status(new_status: StringName, announce: bool = true) -> void:
	if status == new_status:
		return
	status = new_status
	GameState.set_duty_status("Busy" if new_status == &"busy" else "Available")
	if announce:
		if new_status == &"busy":
			_overlay.toast("Status: Busy", 2.0)
			radio_unit("show me 10-6.")
		else:
			_overlay.toast("Status: Available", 2.0)
			radio_unit("show me 10-8.")
		radio_dispatch("10-4, %s." % unit_name)
	status_changed.emit(new_status)
	changed.emit()


## Adds points to the HUD score (negative allowed).
func add_score(points: int) -> void:
	GameState.set_score(GameState.score + points)


# --- call offers -----------------------------------------------------------------------------------

## Offers a call to the player: Dispatch reads it out, the amber prompt counts down 25 s.
## call: a call dictionary (see make_call), a type id (StringName) or null for a random one.
func offer(call: Variant = null) -> Dictionary:
	var data: Dictionary
	if call is Dictionary:
		data = call
		_complete_call_fields(data)
	elif call is StringName or call is String:
		data = make_call(StringName(call))
	else:
		var codes: Array = [&"trespassing", &"suspicious_person", &"noise_complaint", &"shoplifting", &"traffic_collision",
			&"disturbance", &"welfare_check", &"stolen_vehicle", &"armed_robbery", &"burglary", &"foot_pursuit", &"shots_fired",
			&"traffic_stop"]
		data = make_call(codes[rng.randi() % codes.size()])
	if not offer_call.is_empty():
		_end_offer(&"expired")  # a newer call replaces an unanswered one
	data["status"] = &"offered"
	data["time"] = stamp()
	offer_call = data
	offer_left = OFFER_SECONDS
	_last_shown = -1
	history.append(data)
	radio_dispatch(String(data["line"]))
	_refresh_offer_text()
	offer_started.emit(data)
	changed.emit()
	return data


func make_call(type_id: StringName, opts: Dictionary = {}) -> Dictionary:
	return Catalog.make(type_id, rng, opts)


func _complete_call_fields(data: Dictionary) -> void:
	var base := Catalog.make(StringName(data.get("type", &"trespassing")), rng)
	for key: String in base:
		if not data.has(key):
			data[key] = base[key]
	if not data.has("line") or String(data["line"]).is_empty():
		data["line"] = String(data["head"]) + " " + String(data["text"])


func _refresh_offer_text() -> void:
	if offer_call.is_empty():
		_overlay.set_offer("")
		return
	_overlay.set_offer("Code %d: %s.   Y respond   N pass   (%d)" % [offer_call["code"], offer_call["title"], ceili(offer_left)])


## Y: respond. The call becomes the current assignment and the status turns Busy.
func respond() -> void:
	if offer_call.is_empty():
		return
	var data := offer_call
	var code_three := int(data.get("code", 2)) >= 3
	_end_offer(&"responded")
	radio_unit("show me 10-76.")
	radio_dispatch(("10-4, %s responding Code 3." if code_three else "10-4, %s.") % unit_name)
	assign(data)


## N: pass. The call goes to another unit.
func pass_offer() -> void:
	if offer_call.is_empty():
		return
	var data := offer_call
	_end_offer(&"passed")
	stats["passed"] += 1
	radio_unit("unable, I'm tied up.")
	radio_dispatch("10-22, another unit will handle the %s." % data["noun"])


func _expire_offer() -> void:
	var data := offer_call
	_end_offer(&"expired")
	var other := Catalog.random_unit(rng, [unit_name])
	radio_dispatch("%s, take the %s. Code %d." % [other, data["noun"], data["code"]])
	radio(other, "10-4, responding." if int(data["code"]) >= 3 else "10-4, 10-76.")


func _end_offer(result: StringName) -> void:
	var data := offer_call
	offer_call = {}
	offer_left = 0.0
	data["status"] = result
	_overlay.set_offer("")
	offer_ended.emit(data, result)
	changed.emit()


## Makes a call the player's current assignment (Y, emergency calls, scenarios).
func assign(call: Dictionary) -> void:
	_complete_call_fields(call)
	if not history.has(call):
		call["time"] = stamp()
		history.append(call)
	call["status"] = &"assigned"
	current = call
	_arrive_timer = rng.randf_range(SIM_ARRIVE.x, SIM_ARRIVE.y)
	_clear_timer = rng.randf_range(SIM_CLEAR.x, SIM_CLEAR.y)
	if call.has("position"):
		Adapters.hud_call_marker(get_tree(), call["position"])
	stats["calls"] += 1
	set_status(&"busy", false)
	Adapters.hud_set_mission(get_tree(), "Respond to the %s near %s." % [call["noun"], call["location"]])
	call_started.emit(call)
	changed.emit()


## 10-97: the player reached the scene.
func arrive() -> void:
	if current.is_empty():
		return
	radio_unit("10-97.")
	current["status"] = &"on_scene"
	changed.emit()


## Ends the current assignment: "clearing", status back to Available, a little score (estimate).
func complete(outcome: StringName = &"cleared") -> void:
	if current.is_empty():
		return
	var data := current
	current = {}
	data["status"] = outcome
	Adapters.hud_set_mission(get_tree(), "")
	if outcome == &"cleared":
		radio_unit("clearing.")
		add_score(CALL_SCORE)
	set_status(&"available", true)
	call_ended.emit(data, outcome)
	changed.emit()


# --- emergency calls --------------------------------------------------------------------------------

## "All units, shots fired, officer needs assistance": alert beep, EMERGENCY band and an automatic Code 3 response.
## Timeline: dispatch call, other units en route, the player's 10-76 and Dispatch's 10-4.
func emergency(location: String = "the Southside", auto_respond: bool = true) -> void:
	var data := {"id": -1, "type": &"shots_fired", "code": 3, "title": "Shots fired, officer needs assistance",
		"noun": "officer needs assistance", "location": location, "emergency": true, "status": &"new", "head": "",
		"text": "", "plate": "", "time": stamp()}
	data["line"] = "all units, shots fired, officer needs assistance. %s, %s. Respond Code 3." % [unit_name, location]
	radio_dispatch(String(data["line"]))
	start_emergency_band()
	emergency_started.emit(data)
	var others := PackedStringArray()
	var pool: Array[String] = Catalog.UNITS.duplicate()
	pool.shuffle()
	for i in 4:
		others.append(pool[i])
	radio(", ".join(others), "en route.")
	if auto_respond:
		await get_tree().create_timer(1.0).timeout
		history.append(data)
		radio_unit("show me 10-76.")
		radio_dispatch("10-4, %s responding Code 3." % unit_name)
		assign(data)


## Alert beep plus the HUD's EMERGENCY band for four seconds.
func start_emergency_band() -> void:
	_emergency_token += 1
	var token := _emergency_token
	_play_alert()
	Adapters.hud_set_emergency(get_tree(), true, _overlay)
	await get_tree().create_timer(EMERGENCY_BAND_SECONDS).timeout
	if token == _emergency_token:
		Adapters.hud_set_emergency(get_tree(), false, _overlay)


func _play_alert() -> void:
	for path in ALERT_PATHS:
		if FileAccess.file_exists(path):
			var stream := RadioVoice.load_wav(path)
			if stream != null:
				_alert.stream = stream
				_alert.volume_db = -3.0
				_alert.play()
				return


# --- nearby chase notice ----------------------------------------------------------------------------

## Red "Chase nearby, 0.2 mi   C join   Z call off" (other units are chasing). C joins, Z calls it off.
func chase_nearby(miles: float = 0.2) -> void:
	_chase_active = true
	set_chase_distance(miles)
	chase_notice_changed.emit(true)


func set_chase_distance(miles: float) -> void:
	_chase_mi = miles
	if _chase_active:
		_overlay.set_chase_miles(miles)


func clear_chase_notice() -> void:
	_chase_token += 1
	if _chase_active:
		_chase_active = false
		_overlay.clear_chase()
		chase_notice_changed.emit(false)


func join_chase() -> void:
	clear_chase_notice()
	chase_join_requested.emit()
	if Pursuit.has_method("join_chase"):
		Pursuit.call("join_chase")


func call_off_chase() -> void:
	clear_chase_notice()
	_overlay.toast("Chase called off", 2.0)
	radio_unit("terminate the pursuit.")
	radio_dispatch("10-4, all units, pursuit terminated.")
	chase_called_off.emit()


func is_chase_notice_active() -> bool:
	return _chase_active


## Radio chatter of a chase elsewhere: join-ins, direction/speed callouts, PIT request. Runs until cleared or called off.
## Callout format.
func play_nearby_chase(seconds: float = 40.0, lead_unit: String = "1-Adam-14", reporter: String = "7-Sam-34") -> void:
	_chase_token += 1
	var token := _chase_token
	chase_nearby(0.2)
	radio(reporter, "Joining in.")
	await get_tree().create_timer(2.0).timeout
	if token != _chase_token:
		return
	radio(lead_unit, "I've got the lead.")
	var dirs := ["northbound", "eastbound", "southbound", "westbound"]
	var elapsed := 2.0
	while elapsed < seconds and token == _chase_token:
		await get_tree().create_timer(rng.randf_range(6.0, 10.0)).timeout
		elapsed += 8.0
		if token != _chase_token:
			return
		radio(reporter, unit_report(rng.randi_range(20, 90), dirs[rng.randi() % dirs.size()]))
		set_chase_distance(0.2 + 0.1 * float(rng.randi() % 3))
	if token == _chase_token:
		radio(lead_unit, "Requesting permission to PIT.")
		radio_dispatch("%s, stand by." % lead_unit)


## "Still northbound, at thirty." style position report Speed thresholds are estimates.
func unit_report(mph: float, direction: String, prefix: String = "Still") -> String:
	return "%s %s, %s." % [prefix, direction, speed_phrase(mph)]


## Speed words: at twenty / at thirty / slow / moderate / very fast / speeds over a hundred.
## TODO(tahmin): the thresholds between the words were not measured.
func speed_phrase(mph: float) -> String:
	if mph > 100.0:
		return "speeds over a hundred"
	if mph > 75.0:
		return "very fast speeds"
	if mph > 50.0:
		return "moderate speeds"
	if mph >= 38.0:
		return "slow speeds"
	if mph >= 28.0:
		return "at thirty"
	if mph >= 18.0:
		return "at twenty"
	return "slow speeds"


# --- ambient traffic ---------------------------------------------------------------------------------

func _ambient_assignment() -> void:
	var type_id: StringName = [&"trespassing", &"noise_complaint", &"shoplifting", &"suspicious_person", &"disturbance"][rng.randi() % 5]
	var data := Catalog.make(type_id, rng)
	var unit := Catalog.random_unit(rng, [unit_name])
	radio_dispatch(String(data["line"]))
	await get_tree().create_timer(rng.randf_range(1.5, 3.0)).timeout
	radio_dispatch("%s, take the %s. Code %d." % [unit, data["noun"], data["code"]])
	radio(unit, "10-4, 10-76.")
	await get_tree().create_timer(rng.randf_range(15.0, 30.0)).timeout
	radio(unit, "10-97.")
	await get_tree().create_timer(rng.randf_range(20.0, 40.0)).timeout
	radio(unit, "clearing.")
