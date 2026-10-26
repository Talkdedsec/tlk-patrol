extends Node
## Pursuit autoload: vehicle pursuit state machine, PIT authorisation, AI units, foot chase, Taser, cuffing.
## API: docs/api/pursuit.md.
##
##   IDLE -> PURSUIT -> SUSPECT_DOWN -> BAILED -> FOOT_CHASE -> SUBDUED -> CUFFING -> CUFFED -> (end) IDLE
##   Pursuit.start(vehicle) / alpr_hit(...) + lights on; request_pit() (R); set_pit_decision(); request_backup() (B);
##   join_chase() (C); call_off() (Z); taser_fire() (LMB); interact() (E); signals suspect_bailed / suspect_cuffed.

const Adapters := preload("res://scripts/pursuit/adapters.gd")
const BannerScript := preload("res://scripts/pursuit/banner.gd")
const Pit := preload("res://scripts/pursuit/pit.gd")
const Radio := preload("res://scripts/pursuit/radio.gd")
const AiUnits := preload("res://scripts/pursuit/ai_units.gd")
const FootChase := preload("res://scripts/pursuit/foot_chase.gd")
const SuspectDriver := preload("res://scripts/pursuit/suspect_driver.gd")
const Registry := preload("res://scripts/traffic/registry.gd")

enum State { IDLE, PURSUIT, SUSPECT_DOWN, BAILED, FOOT_CHASE, SUBDUED, CUFFING, CUFFED }
## Mirrors Pit.S (kept as a plain enum so other modules do not need the Pit script).
enum PitState { IDLE, REQUESTED, DENIED, AUTHORIZED }

signal state_changed(old_state: int, new_state: int)
signal started(target: Node3D)
signal ended(reason: StringName)               # &"processed", &"lost", &"called_off", &"aborted", &"yielded"
signal pit_state_changed(new_state: int)
signal pit_succeeded(target: Node3D)
signal suspect_bailed(npc: Node3D)
signal suspect_downed(npc: Node3D)
signal suspect_cuffed(npc: Node3D)             # TrafficStop.begin_booking listens to this
signal process_requested(npc: Node3D, charges: Array)   # E on the cuffed suspect ("E  Process the suspect")
signal target_yielded(vehicle: Node3D)
signal backup_changed(requested: bool)
signal taser_fired(hit: bool)

const FT := 0.3048
const START_RANGE_FT := 65.0       # TODO(tahmin): the start shows at 47 ft; the exact trigger range is a guess
const START_DELAY := 0.25          # lights to "driver is fleeing" in at most 0.25 s
const BAIL_SCORE := 20             # -5 -> 15 about 1 s after the bail; TODO(tahmin): the game event it is bound to
const BAIL_SCORE_DELAY := 1.0
const MIN_DOWN_SECONDS := 3.0      # TODO(tahmin): earliest bail after the spin-out (10.75 s incl. the slide to the rail)
const MAX_DOWN_SECONDS := 16.0
const BAIL_STOP_SECONDS := 1.2     # stopped this long -> the driver gets out (about 1.5 s)
## TODO(tahmin): losing the suspect: more than half a mile away for this long.
const LOST_FT := 2640.0
const LOST_SECONDS := 12.0
const EVIDENCE := ["Evading police in a vehicle", "Fleeing a police officer on foot", "Resisting arrest"]
const PIT_HINT := "PIT position: steer into the back corner"

var state: int = State.IDLE
var target: Node3D
var player_vehicle: Node3D
var officer: Node3D
var suspect: Node3D                    # the driver on foot after the bail
var callsign := "1-Adam-12"
var distance_ft := 0.0
var elapsed := 0.0
var drive_suspect := true              # false: scenarios drive the suspect themselves
var auto_book := false                 # true: call TrafficStop.begin_booking on "Process the suspect"
## false: the duty status stays as it is while the pursuit runs ("Available" for the whole pursuit).
## The Busy switch itself is done by whoever listens to `started` (scripts/game/duty_flow.gd); Pursuit puts the status back.
var busy_on_start := true
## Seconds from the spin-out to the bail; < 0 = natural (stopped for 1.2 s, at least 3 s). Typical: 10.75 s.
var bail_delay := -1.0
## PIT contact without a Vehicle.pit_scuff() API shoves the suspect with Vehicle.pit_push(); false = no shove (smoke/skid only).
var pit_contact_push := true
var lost_enabled := true               # false: the suspect can never be lost (scenarios, soak tests)
var owner_evader := true               # dispatch warns about prior evading arrests
var suspect_plate := ""
var evidence_charges: Array[String] = []
var banner: Node
var pit: Pit
var driver: SuspectDriver
var units: AiUnits
var foot: FootChase

var _clock := 0.0
var _radio: Array = []
var _marked: Dictionary = {}
var _lights_t := 0.0
var _last_line := ""
var _down_t := 0.0
var _stopped_t := 0.0
var _score_t := -1.0
var _lost_t := 0.0
var _roadblock: Array = []             # [{node, passed_t, unit}]
var _roadblock_unit := ""
var _yield_target: Node3D = null
var _yield_t := 0.0


func _ready() -> void:
	if not InputMap.has_action("request_pit"):
		InputMap.add_action("request_pit")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_R
		InputMap.action_add_event("request_pit", ev)
	process_physics_priority = -5
	var weapons := Adapters.singleton("Weapons")
	if weapons != null and weapons.has_signal("target_downed"):
		weapons.connect("target_downed", _on_target_downed)


## A shot suspect on foot closes the foot chase (FOOT CHASE gauge off at once, 01-silahlar.md 3.5).
func _on_target_downed(npc: Node, _weapon: Variant, lethal: bool) -> void:
	if suspect == null or npc != suspect or not (state == State.BAILED or state == State.FOOT_CHASE):
		return
	if lethal:
		end(&"suspect_down")
	elif foot != null:
		foot.downed_externally()


func _ensure_banner(parent: Node = null) -> void:
	if banner != null and is_instance_valid(banner):
		return
	banner = BannerScript.new()
	banner.name = "PursuitBanner"
	if parent != null:
		parent.add_child(banner)
	else:
		get_tree().root.add_child.call_deferred(banner)


## Hosts that draw into their own viewport (sub-viewport screenshots) call this to put the overlay inside their tree.
func bind_ui(parent: Node) -> void:
	if banner != null and is_instance_valid(banner):
		if banner.get_parent() != null:
			banner.get_parent().remove_child(banner)
		parent.add_child(banner)
	else:
		_ensure_banner(parent)


func is_active() -> bool:
	return state != State.IDLE


func in_vehicle_phase() -> bool:
	return state == State.PURSUIT or state == State.SUSPECT_DOWN


func player_position() -> Vector3:
	if in_vehicle_phase() and player_vehicle != null and is_instance_valid(player_vehicle):
		return player_vehicle.global_position
	if officer != null and is_instance_valid(officer):
		return officer.global_position
	var o := Adapters.officer()
	if o != null:
		return o.global_position
	if player_vehicle != null and is_instance_valid(player_vehicle):
		return player_vehicle.global_position
	return Vector3.ZERO


# --- public API: scripted use ------------------------------------------------------------------------------------

## ALPR hit on a vehicle: shows the white line and marks the vehicle. When the lights go on within about 50 ft and it
## does not stop, the pursuit starts by itself (flees = true) or the driver pulls over (flees = false).
func alpr_hit(vehicle: Node3D, plate: String, reason: String, flees: bool = true, evader: bool = true) -> void:
	_ensure_banner()
	banner.call("toast", "ALPR HIT   %s   %s" % [plate, reason.to_upper()], 4.75, &"alpr_hit")
	mark_target(vehicle, plate, flees, evader)


func mark_target(vehicle: Node3D, plate: String = "", flees: bool = true, evader: bool = true) -> void:
	_marked = {"vehicle": vehicle, "plate": plate, "flees": flees, "evader": evader}
	_lights_t = 0.0


func clear_mark() -> void:
	_marked = {}


## Starts the pursuit of `target_vehicle`. options: player_vehicle, officer, callsign, drive_suspect (bool),
## units (bool: AI unit radio traffic), evader (bool), plate (String), announce (bool: radio lines).
func start(target_vehicle: Node3D, options: Dictionary = {}) -> bool:
	if state != State.IDLE or target_vehicle == null or not is_instance_valid(target_vehicle):
		return false
	_ensure_banner()
	target = target_vehicle
	suspect = null
	callsign = String(options.get("callsign", callsign))
	player_vehicle = options.get("player_vehicle", player_vehicle)
	if player_vehicle == null or not is_instance_valid(player_vehicle):
		player_vehicle = Adapters.player_vehicle()
	officer = options.get("officer", officer)
	drive_suspect = bool(options.get("drive_suspect", true))
	bail_delay = float(options.get("bail_delay", bail_delay))
	owner_evader = bool(options.get("evader", _marked.get("evader", true)))
	var plate_var: Variant = target.get("plate")
	suspect_plate = String(options.get("plate", plate_var if plate_var != null else ""))
	evidence_charges.clear()
	evidence_charges.append(EVIDENCE[0])
	elapsed = 0.0
	distance_ft = _flat_distance_ft(target)
	_lost_t = 0.0
	_down_t = 0.0
	_marked = {}
	pit = Pit.new()
	pit.state_changed.connect(_on_pit_state)
	var traffic := Adapters.singleton("Traffic")
	if traffic != null and traffic.has_method("release"):
		traffic.call("release", target)
	if traffic != null:
		traffic.set("focus_node", player_vehicle)
		traffic.set("siren_source", player_vehicle)
	Registry.add(target, &"suspect")
	if player_vehicle != null:
		Registry.add(player_vehicle, &"player")
	driver = null
	if drive_suspect:
		var g := Adapters.graph()
		if g != null:
			var sd := SuspectDriver.new()
			sd.attach(target, g)
			sd.player = player_vehicle
			driver = sd
	units = AiUnits.new()
	units.enabled = bool(options.get("units", true))
	units.start(self)
	_set_state(State.PURSUIT)
	banner.call("toast", "The driver is fleeing!", 1.0, &"driver_fleeing")
	_last_line = ""
	_refresh_banner()
	if bool(options.get("announce", true)):
		say("%s: 10-80, vehicle failing to yield." % callsign)
		say("Dispatch: Copy, %s is 10-80. All units, be advised." % callsign, 0.7)
		if owner_evader:
			say("Dispatch: Be advised, the registered owner has prior evading arrests. Use caution.", 1.4)
	var duty_before := GameState.duty_status
	var calls := Adapters.singleton("Calls")
	var calls_before: Variant = calls.get("status") if calls != null else null
	started.emit(target)
	if not bool(options.get("busy", busy_on_start)):
		GameState.set_duty_status(duty_before)
		if calls != null and calls_before != null and calls.has_method("set_status"):
			calls.call("set_status", calls_before, false)
	return true


## R: asks for PIT permission. false when a request is pending, refused (20 s cooldown) or already granted.
func request_pit() -> bool:
	if state != State.PURSUIT or pit == null:
		return false
	if not pit.request():
		return false
	say("%s: Requesting permission to PIT." % callsign)
	say("Dispatch: %s, stand by." % callsign, 0.6)
	banner.call("toast", "PIT requested", 2.25, &"pit_requested")
	return true


## Scripted outcome of the next PIT decision (authorised or refused) and optionally its delay in seconds.
func set_pit_decision(authorized: bool, delay: float = -1.0) -> void:
	if pit == null:
		pit = Pit.new()
		pit.state_changed.connect(_on_pit_state)
	pit.set_decision(authorized, delay)


func pit_state() -> int:
	return pit.state if pit != null else PitState.IDLE


## B: asks for backup; B again clears the unit.
func request_backup() -> void:
	if state != State.PURSUIT or units == null:
		return
	var requested: bool = units.toggle_backup()
	if requested:
		say("%s: I need a 10-78." % callsign)
		say("Dispatch: 10-4. %s, respond Code 3 to assist %s." % [Radio.BACKUP_UNIT, callsign], 0.6)
		banner.call("toast", "%s is on the way (B again to clear them)" % Radio.BACKUP_UNIT, 3.0, &"backup_on_the_way")
	else:
		say("Dispatch: 10-4, %s, disregard." % Radio.BACKUP_UNIT)
		banner.call("toast", "%s cleared" % Radio.BACKUP_UNIT, 2.0)   # TODO(tahmin): the clear message wording is our own
	backup_changed.emit(requested)


## C: join the foot chase (also called by Calls for its chase notice).
func join_chase() -> void:
	if state == State.BAILED and foot != null:
		foot.join()
		_set_state(State.FOOT_CHASE)


## Z: call off the foot chase.
func call_off() -> void:
	if state == State.BAILED or state == State.FOOT_CHASE:
		say("%s: Calling off the foot pursuit." % callsign)
		say("Dispatch: 10-4, foot pursuit terminated.", 0.6)
		var gone := suspect
		end(&"called_off")
		if gone != null and is_instance_valid(gone):
			gone.call("flee_from", player_position(), 120.0)
			get_tree().create_timer(30.0).timeout.connect(func() -> void:
				if is_instance_valid(gone):
					gone.queue_free())


## LMB with the Taser out. Returns true when it hit.
func taser_fire() -> bool:
	if foot == null or not (state == State.BAILED or state == State.FOOT_CHASE):
		return false
	var o := officer if officer != null and is_instance_valid(officer) else Adapters.officer()
	if o != null and o.has_method("notify_shot"):
		o.call("notify_shot")
	var hit: bool = foot.taser_fire()
	taser_fired.emit(hit)
	return hit


## E: cuff the downed suspect / process the cuffed one.
func interact() -> bool:
	if foot == null:
		return false
	return foot.interact()


func say(text: String, delay: float = 0.0) -> void:
	if delay <= 0.0:
		Dispatch.say(text)
	else:
		_radio.append({"t": _clock + delay, "text": text})


func toast(text: String, seconds: float = 3.0, key: StringName = &"", center_x: float = 960.0) -> void:
	_ensure_banner()
	banner.call("toast", text, seconds, key, center_x)


func end(reason: StringName = &"ended") -> void:
	if state == State.IDLE:
		return
	if foot != null:
		foot.cleanup()
	var finished_target := target
	_clear_roadblock()
	if banner != null:
		banner.call("clear_all")
	var traffic := Adapters.singleton("Traffic")
	if traffic != null:
		traffic.set("siren_source", null)
	if reason == &"lost":
		say("Dispatch: %s, we have lost the suspect. All units, terminate the pursuit." % callsign)
		toast("You lost the suspect.", 3.0)   # TODO(tahmin): wording
		if finished_target != null and is_instance_valid(finished_target) and traffic != null and traffic.has_method("adopt"):
			traffic.call("adopt", finished_target)
	if finished_target != null:
		Registry.remove(finished_target)
	driver = null
	_set_state(State.IDLE)
	ended.emit(reason)


## Debug / test snapshot of what the player sees.
func snapshot() -> Dictionary:
	var b := banner
	return {
		"state": State.keys()[state], "pit": PitState.keys()[pit_state()], "distance_ft": distance_ft,
		"toast": b.call("toast_text") if b != null else "", "line": b.call("pursuit_text") if b != null else "",
		"chase": b.call("chase_text") if b != null else "", "foot": b.call("foot_text") if b != null else "",
		"prompt": b.call("prompt_text") if b != null else "",
	}


# --- main loop ---------------------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	_clock += dt
	_radio_tick()
	if _score_t >= 0.0:
		_score_t -= dt
		if _score_t < 0.0:
			GameState.set_score(GameState.score + BAIL_SCORE)
	match state:
		State.IDLE:
			_tick_idle(dt)
		State.PURSUIT:
			_tick_pursuit(dt)
		State.SUSPECT_DOWN:
			_tick_down(dt)
		_:
			if foot != null:
				foot.tick(dt)
				distance_ft = foot.distance_ft
	if state != State.IDLE:
		elapsed += dt
	_tick_yield(dt)


func _radio_tick() -> void:
	for i in range(_radio.size() - 1, -1, -1):
		if _clock >= float(_radio[i].t):
			Dispatch.say(String(_radio[i].text))
			_radio.remove_at(i)


func _unhandled_input(event: InputEvent) -> void:
	if state == State.IDLE:
		return
	if event.is_action_pressed("request_pit"):
		request_pit()
	elif event.is_action_pressed("request_backup"):
		request_backup()
	elif event.is_action_pressed("join_chase"):
		join_chase()
	elif event.is_action_pressed("call_off"):
		call_off()
	elif event.is_action_pressed("fire"):
		taser_fire()
	elif event.is_action_pressed("interact"):
		interact()


func _set_state(new_state: int) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	state_changed.emit(old, new_state)


func _flat_distance_ft(node: Node3D) -> float:
	var d := node.global_position - player_position()
	d.y = 0.0
	return d.length() / FT


func _target_ok() -> bool:
	return target != null and is_instance_valid(target) and target.is_inside_tree()


# --- idle: automatic start ---------------------------------------------------------------------------------------

func _tick_idle(dt: float) -> void:
	if _marked.is_empty():
		return
	var tv: Node3D = _marked.vehicle
	if tv == null or not is_instance_valid(tv):
		_marked = {}
		return
	var pv := player_vehicle if player_vehicle != null and is_instance_valid(player_vehicle) else Adapters.player_vehicle()
	if pv == null:
		return
	if not Adapters.lights_on():
		_lights_t = 0.0
		return
	var to := tv.global_position - pv.global_position
	to.y = 0.0
	var behind: bool = to.length() > 0.5 and to.normalized().dot(-pv.global_transform.basis.z) > 0.5
	if not (behind and to.length() / FT <= START_RANGE_FT):
		_lights_t = 0.0
		return
	_lights_t += dt
	if _lights_t < START_DELAY:
		return
	if bool(_marked.flees):
		player_vehicle = pv
		start(tv, {"evader": _marked.evader, "plate": _marked.plate})
	else:
		_pull_over(tv)
		_marked = {}


func _pull_over(tv: Node3D) -> void:
	var traffic := Adapters.singleton("Traffic")
	if traffic != null and traffic.has_method("pull_over"):
		traffic.call("pull_over", tv)
	_yield_target = tv
	_yield_t = 0.0


func _tick_yield(dt: float) -> void:
	if _yield_target == null:
		return
	if not is_instance_valid(_yield_target):
		_yield_target = null
		return
	if Adapters.speed_ms(_yield_target) < 0.4:
		_yield_t += dt
		if _yield_t > 1.0:
			var v := _yield_target
			_yield_target = null
			target_yielded.emit(v)
			var ts := Adapters.singleton("TrafficStop")
			if ts != null and ts.has_method("begin"):
				ts.call("begin", v)
	else:
		_yield_t = 0.0


# --- vehicle pursuit ---------------------------------------------------------------------------------------------

func _tick_pursuit(dt: float) -> void:
	if not _target_ok():
		end(&"aborted")
		return
	if player_vehicle == null or not is_instance_valid(player_vehicle):
		player_vehicle = Adapters.player_vehicle()
	distance_ft = _flat_distance_ft(target)
	if driver != null:
		driver.player = player_vehicle
		driver.update(dt)
	var player_mph := Adapters.speed_mph(player_vehicle) if player_vehicle != null else 0.0
	var ev: StringName = pit.tick(dt, player_mph)
	if ev == &"authorized":
		say("Dispatch: %s, supervisor clears the PIT." % callsign)
	elif ev == &"denied":
		say("Dispatch: %s, supervisor says negative on the PIT, speeds are too high. Keep following." % callsign)
	if pit.state == Pit.S.AUTHORIZED and player_vehicle != null:
		var info := Pit.contact(player_vehicle, target)
		var pit_contact: bool = bool(info.pit)
		if pit_contact:
			Adapters.pit_contact(target, float(info.side), dt, pit_contact_push)
		if pit.update_contact(dt, pit_contact, Adapters.speed_mph(target)):
			_pit_success(float(info.side))
	_tick_units(dt)
	_tick_roadblock()
	_refresh_banner()
	_check_lost(dt)


func _tick_units(dt: float) -> void:
	if units == null:
		return
	var vel := Adapters.velocity(target)
	var dir := vel.normalized() if vel.length() > 1.0 else -target.global_transform.basis.z
	var edge: Dictionary = {}
	if driver != null:
		edge = driver.current_edge()
	var info := Adapters.street_at(target.global_position)
	units.tick(dt, {"dir": dir, "mph": Adapters.speed_mph(target), "limit": int(info.limit_mph), "kind": String(edge.get("kind", info.kind))})


func _check_lost(dt: float) -> void:
	if not lost_enabled:
		return
	if distance_ft > LOST_FT:
		_lost_t += dt
		if _lost_t > LOST_SECONDS:
			end(&"lost")
	else:
		_lost_t = 0.0


func _on_pit_state(new_state: int) -> void:
	pit_state_changed.emit(new_state)
	_last_line = ""


func _refresh_banner() -> void:
	if banner == null:
		return
	var key := "%s|%s" % [BannerScript.format_distance(distance_ft), pit.status_text() if pit != null else ""]
	if state == State.PURSUIT or state == State.SUSPECT_DOWN:
		if key != _last_line:
			_last_line = key
			banner.call("set_pursuit", distance_ft, pit.status_text())
		var show_hint: bool = state == State.PURSUIT and pit.update_hint(distance_ft)
		banner.call("set_hint", PIT_HINT if show_hint else "")


## Scenario hook: the PIT worked now (spin-out), regardless of the contact counter. side: -1 left rear, +1 right rear.
func force_pit_success(side: float = 1.0) -> void:
	if state == State.PURSUIT:
		_pit_success(side)


func _pit_success(side: float) -> void:
	pit_succeeded.emit(target)
	Adapters.pit_spin(target, side, 1.0)
	Adapters.drive(target, 0.0, 1.0, 0.0)
	if driver != null:
		driver.enabled = false
	_set_state(State.SUSPECT_DOWN)
	_down_t = 0.0
	_stopped_t = 0.0
	banner.call("toast", "PIT: The car spun out.", 7.0, &"pit_spun_out")
	banner.call("set_hint", "")
	var u: String = units.any_unit() if units != null else ""
	say("%s: Good PIT, vehicle spun out." % (u if u != "" else Radio.COVER_UNIT), 4.5)


func _tick_down(dt: float) -> void:
	if not _target_ok():
		end(&"aborted")
		return
	_down_t += dt
	distance_ft = _flat_distance_ft(target)
	Adapters.drive(target, 0.0, 1.0, 0.0)
	var spd := Adapters.speed_mph(target)
	_stopped_t = _stopped_t + dt if spd < 1.0 else 0.0
	_tick_units(dt)
	_tick_roadblock()
	_refresh_banner()
	var natural := _down_t >= MIN_DOWN_SECONDS and _stopped_t >= BAIL_STOP_SECONDS
	if bail_delay >= 0.0:
		natural = _down_t >= bail_delay and (_stopped_t >= 0.3 or _down_t >= bail_delay + 3.0)
	if natural or _down_t >= maxf(MAX_DOWN_SECONDS, bail_delay + 3.0):
		_bail()


## Starts the foot phase for a suspect who is already on foot (armed-suspect calls, scenarios): the same state, banner,
## radio, score and chase logic as after a vehicle pursuit's bail, without a car. The suspect should already be running
## (`npc.flee_from`). options: plate (String), cover (callsign of the covering unit, default 7-Sam-34), announce (bool: toast
## "The suspect is running! Catch them."), declare (bool: the "foot pursuit" radio lines), score (bool: +20 after 1 s),
## evidence (Array of charge names, default the foot-flight charge), callsign, officer. false when a pursuit is active.
func begin_foot_chase(npc: Node3D, options: Dictionary = {}) -> bool:
	if state != State.IDLE or npc == null or not is_instance_valid(npc):
		return false
	_ensure_banner()
	target = null
	driver = null
	pit = null
	units = null
	suspect = npc
	suspect_plate = String(options.get("plate", ""))
	callsign = String(options.get("callsign", callsign))
	officer = options.get("officer", officer)
	elapsed = 0.0
	evidence_charges.clear()
	for c in options.get("evidence", [EVIDENCE[1]]):
		evidence_charges.append(String(c))
	foot = FootChase.new()
	foot.start(self, banner, npc, String(options.get("cover", Radio.COVER_UNIT)))
	foot.set("announced", not bool(options.get("declare", true)))
	_set_state(State.BAILED)
	banner.call("clear_pursuit")
	banner.call("set_hint", "")
	if bool(options.get("announce", true)):
		banner.call("toast", "The suspect is running! Catch them.", 3.5, &"bailed_out")
	if bool(options.get("score", true)):
		_score_t = BAIL_SCORE_DELAY
	var o := officer if officer != null and is_instance_valid(officer) else Adapters.officer()
	if o != null and Adapters.in_vehicle(o):
		Adapters.exit_vehicle(o)
	suspect_bailed.emit(npc)
	return true


## Public entry for Weapons.target_downed style notifications (scenes that shoot the suspect before the chase state exists).
func notify_target_downed(npc: Node, weapon: Variant, lethal: bool) -> void:
	_on_target_downed(npc, weapon, lethal)


func _bail() -> void:
	Adapters.open_driver_door(target)
	var xf := Adapters.driver_exit_transform(target)
	suspect = Adapters.spawn_npc(xf, "civilian", &"red_shirt")
	if target.has_method("set_driver"):
		target.call("set_driver", null)
	var o := officer if officer != null and is_instance_valid(officer) else Adapters.officer()
	if o != null and Adapters.in_vehicle(o):
		Adapters.exit_vehicle(o)
	evidence_charges.append(EVIDENCE[1])
	foot = FootChase.new()
	foot.start(self, banner, suspect, units.cover_unit() if units != null else Radio.COVER_UNIT)
	_set_state(State.BAILED)
	banner.call("clear_pursuit")
	banner.call("set_hint", "")
	banner.call("toast", "They bailed out of the car! Catch them.", 3.5, &"bailed_out")
	_score_t = BAIL_SCORE_DELAY
	suspect_bailed.emit(suspect)


## Foot-phase callbacks (FootChase) ------------------------------------------------------------------------------

func on_foot_pursuit_declared() -> void:
	say("%s: Suspect bailed, I'm in foot pursuit." % callsign)
	say("Dispatch: 10-4, foot pursuit. All units, be advised.", 0.5)
	var names: Array[String] = []
	if units != null:
		names = units.active_callsigns()
	for n in [Radio.COVER_UNIT, "7-Sam-21"]:
		if not names.has(n):
			names.append(n)
	for i in mini(2, names.size()):
		say("%s: 10-97." % names[i], 0.9)
	say("%s: Thanks for the assist, %s." % [names[0], callsign], 1.6)


func on_taser_out() -> void:
	var o := officer if officer != null and is_instance_valid(officer) else Adapters.officer()
	if o != null and o.has_method("draw_weapon"):
		o.call("draw_weapon", &"taser")


func on_suspect_downed() -> void:
	evidence_charges.append(EVIDENCE[2])
	_set_state(State.SUBDUED)
	suspect_downed.emit(suspect)
	say("%s: Code four; suspect's down." % (foot.cop_name if foot != null else Radio.COVER_UNIT), 0.6)


func on_cuff_started() -> void:
	_set_state(State.CUFFING)


func on_cuff_interrupted() -> void:
	_set_state(State.SUBDUED)


func on_suspect_cuffed() -> void:
	_set_state(State.CUFFED)
	suspect_cuffed.emit(suspect)
	say("%s: 10-15." % (foot.cop_name if foot != null else Radio.COVER_UNIT), 1.0)


func process_suspect() -> void:
	var charges: Array = evidence_charges.duplicate()
	var npc := suspect
	process_requested.emit(npc, charges)
	if auto_book:
		var ts := Adapters.singleton("TrafficStop")
		if ts != null and ts.has_method("begin_booking"):
			ts.call("begin_booking", npc, charges)
	end(&"processed")


# --- roadblock (TODO(tahmin): our own design; two parked patrol cars ahead of the suspect) ----------------

func roadblock(unit: String) -> void:
	if driver == null or not _target_ok() or driver.route == null:
		return
	var route := driver.route
	var s_now: float = driver.s_now
	var from_s := s_now + clampf(Adapters.speed_ms(target) * 8.0, 140.0, 420.0)
	var s_at := -1.0
	var step := 20.0
	var cand := from_s
	while cand < route.total() - 40.0:
		var clear := true
		for e in route.leg_end:
			if absf(float(e) - cand) < 55.0:
				clear = false
		if clear and route.dir_at(cand - 30.0).dot(route.dir_at(cand + 30.0)) > 0.99:
			s_at = cand
			break
		cand += step
	if s_at < 0.0:
		return
	var pos: Vector3 = route.pos_at(s_at)
	var dir: Vector3 = route.dir_at(s_at)
	_clear_roadblock()
	_roadblock_unit = unit
	# one car angled across the suspect's lane, a second one parked on the shoulder behind it (the oncoming lane stays open)
	var specs := [[0.0, 0.0, 62.0], [-9.0, 6.5, -20.0]]
	for sp in specs:
		var p := pos + dir * float(sp[0]) + dir.cross(Vector3.UP) * float(sp[1])
		var yaw := atan2(-dir.x, -dir.z) + deg_to_rad(float(sp[2]))
		var xf := Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 0.3, 0))
		var car := Adapters.spawn_vehicle(&"patrol_sedan", xf, {"team": &"police"})
		Adapters.park(car)
		Adapters.set_vehicle_lights(car, true)
		Registry.add(car, &"roadblock")
		_roadblock.append({"node": car, "passed_t": -1.0})


func _tick_roadblock() -> void:
	if _roadblock.is_empty() or not _target_ok():
		return
	for rb: Dictionary in _roadblock:
		var car: Node3D = rb.node
		if not is_instance_valid(car):
			continue
		var d := car.global_position - target.global_position
		d.y = 0.0
		if float(rb.passed_t) < 0.0 and d.length() < 12.0:
			rb.passed_t = elapsed
			if _roadblock_unit != "":
				say("%s: my unit's disabled, I'm out of the pursuit." % _roadblock_unit, 1.5)
				_roadblock_unit = ""
		elif float(rb.passed_t) >= 0.0 and elapsed - float(rb.passed_t) > 20.0:
			_clear_roadblock()
			return


func _clear_roadblock() -> void:
	for rb: Dictionary in _roadblock:
		var car: Node3D = rb.node
		if is_instance_valid(car):
			Registry.remove(car)
			car.queue_free()
	_roadblock.clear()
