extends Node
## End-to-end check of the game loop with real input events (InputEventKey / InputEventMouseButton through
## Input.parse_input_event): walk, get in, drive, ELS keys, RADAR / ALPR / MDT, call offer -> accept -> scene ->
## traffic stop, stolen vehicle -> pursuit -> PIT -> bail -> foot chase -> Taser -> cuffs -> booking, armed suspect.
## Headless with a fixed frame time (one process frame = 1/60 s of game time, runs faster than real time):
##   araclar/godot.sh --headless --fixed-fps 60 --script res://scripts/game/e2e_check.gd -- [--only name,name]
## Sections: boot foot drive radar hud calls stop pursuit flee armed talk weapons quiet. Prints "CHECK n PASS|FAIL <what>" and "E2E n/m OK".

const MAIN_SCENE := "res://scenes/main.tscn"

var main: Node
var checks := 0
var passed := 0
var failures: Array[String] = []
var only: PackedStringArray = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--only")
	if i >= 0 and i + 1 < args.size():
		only = args[i + 1].split(",")
	var packed := load(MAIN_SCENE) as PackedScene
	main = packed.instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await _run()
	var line := "E2E %d/%d %s" % [passed, checks, "OK" if passed == checks else "FAILED"]
	print(line)
	for failure in failures:
		print("  failed: ", failure)
	get_tree().quit(0 if passed == checks else 1)


func _run() -> void:
	await frames(30)
	# the call director must not start by itself while the sections run (each section offers its own calls)
	main.hooks.director.enabled = false
	main.hooks.alpr_enabled = false
	TrafficStop.auto_detect = false
	for section: String in ["boot", "foot", "drive", "radar", "hud", "calls", "stop", "pursuit", "flee", "armed", "talk", "weapons", "quiet"]:
		if only.is_empty() or only.has(section):
			print("-- ", section)
			await call("_section_" + section)


# --- helpers ------------------------------------------------------------------------------------------------------

func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		passed += 1
	else:
		failures.append("%d %s" % [checks, what])
	print("CHECK %d %s %s" % [checks, "PASS" if ok else "FAIL", what])


func frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func secs(seconds: float) -> void:
	await frames(int(seconds * 60.0))


## Waits until `cond` is true (polled every frame); returns whether it became true within `timeout` seconds.
func until(cond: Callable, timeout: float) -> bool:
	for _i in int(timeout * 60.0):
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _key_event(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


func key_down(code: Key) -> void:
	Input.parse_input_event(_key_event(code, true))
	await get_tree().process_frame


func key_up(code: Key) -> void:
	Input.parse_input_event(_key_event(code, false))
	await get_tree().process_frame


func tap(code: Key, hold := 0.08) -> void:
	await key_down(code)
	await secs(hold)
	await key_up(code)
	await frames(2)


func hold(code: Key, seconds: float) -> void:
	await key_down(code)
	await secs(seconds)
	await key_up(code)


func mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = Vector2(960, 540)
	Input.parse_input_event(event)
	await get_tree().process_frame


func click(button: MouseButton) -> void:
	await mouse(button, true)
	await secs(0.06)
	await mouse(button, false)
	await frames(2)


func hud() -> Node:
	return main.hud


func seat() -> Node:
	return main.seat


func player() -> Node3D:
	return main.player


func car() -> Vehicle:
	return main.patrol_vehicle


func driving() -> bool:
	return bool(seat().call("is_driving"))


## Puts the player (on foot) next to the patrol car's driver door and waits for the prompt.
func go_to_door() -> void:
	var door := car().enter_transform(&"driver")
	player().global_position = Vector3(door.origin.x, 0.1, door.origin.z) + door.basis.z * 0.9
	player().velocity = Vector3.ZERO
	await frames(10)


func place_car(pos: Vector3, heading_dir: Vector3, mph := 0.0) -> void:
	var basis := Basis.looking_at(heading_dir.normalized(), Vector3.UP)
	car().teleport(Transform3D(basis, pos + Vector3(0.0, 0.4, 0.0)))
	car().linear_velocity = heading_dir.normalized() * mph * 0.44704
	await frames(6)


## Gets into the patrol car with the E key (walk to the door first).
func get_in() -> void:
	await go_to_door()
	await tap(KEY_E)
	await until(func() -> bool: return driving(), 6.0)


func get_out() -> void:
	car().set_cruise_mph(-1.0)
	await hold(KEY_S, 2.0)
	await until(func() -> bool: return car().speed_mph() < 3.0, 6.0)
	await tap(KEY_F)
	await until(func() -> bool: return bool(seat().call("is_on_foot")), 4.0)


# --- sections -----------------------------------------------------------------------------------------------------

func _section_boot() -> void:
	check(main.player != null and main.patrol_vehicle != null and main.hud != null and main.seat != null and main.hooks != null,
		"main scene: player, patrol vehicle, hud, seat and hooks exist")
	check(hud().get_script().resource_path.ends_with("game_hud.gd") and hud().is_in_group("hud"), "game HUD (prompt arbiter) is the hud")
	check(not hud().radar.visible and not hud().els_panel.visible, "RADAR/ALPR and ELS panels are hidden on foot")
	var civilians := 0
	for v: Vehicle in Vehicles.all:
		if not v.is_police:
			civilians += 1
	check(civilians >= 10, "ambient traffic spawned (%d civilian cars)" % civilians)
	check(main.hooks.director != null and main.hooks.radar != null and main.hooks.duty != null, "director, radar feed and duty flow are running")
	check(not Calls.auto_offers and not Calls.simulate_response, "random call offers and simulated responses are off (director owns the calls)")
	check(GameState.duty_status == "Available" and GameState.score == 0, "day starts Available, score 0")
	check(main.officer_model == &"police" and player().get("model_kind") == "police", "the officer is the police model by default")
	var old_officer: Node3D = player()
	var old_position := old_officer.global_position
	var old_heading := old_officer.rotation.y
	main.set_officer_model(&"sheriff")
	await frames(5)
	check(player() != old_officer and player().get("model_kind") == "sheriff" and seat().officer == player() and player().get("seat") == seat() and player().is_inside_tree(),
		"set_officer_model(&\"sheriff\") builds the sheriff officer in the old one's place; the seat follows")
	check(player().global_position.distance_to(old_position) < 0.2 and is_equal_approx(player().rotation.y, old_heading),
		"the new officer stands where the old one stood, same heading")


func _section_foot() -> void:
	var start := player().global_position
	await hold(KEY_W, 1.2)
	check(player().global_position.distance_to(start) > 2.0, "W moves the officer (%.1f m in 1.2 s)" % player().global_position.distance_to(start))
	await go_to_door()
	check(hud().prompt_text() == "E  Get in", "prompt \"E  Get in\" next to the driver door (shown: %s)" % hud().prompt_text())
	player().global_position = car().global_position + Vector3(40.0, 0.1, 40.0)
	await frames(20)
	await tap(KEY_TAB)
	check(not Mdt.is_open, "Tab far from the patrol car does not open the MDT")
	await go_to_door()
	await tap(KEY_TAB)
	check(Mdt.is_open, "Tab next to the patrol car opens the MDT")
	await tap(KEY_ESCAPE)
	check(not Mdt.is_open, "Esc closes the MDT")


func _section_drive() -> void:
	await go_to_door()
	await tap(KEY_E)
	await tap(KEY_E)   # a second E while the door walk is running must not do anything
	await until(func() -> bool: return driving(), 6.0)
	check(driving() and car().driver == player(), "E gets the officer into the car (door walk, sit); a second E is ignored")
	check(hud().radar.visible and hud().els_panel.visible, "vehicle panels (RADAR/ALPR, ELS) show while driving")
	check(hud().prompt_text() == "", "no prompt while seated")
	await tap(KEY_Q)
	check(Els.lights_on, "Q switches the emergency lights on")
	await tap(KEY_X)
	check(Els.siren_tone != &"", "X selects a siren tone (%s)" % Els.siren_tone)
	await key_down(KEY_H)
	var horn_on: bool = Els.held.get(&"ah", false)
	await key_up(KEY_H)
	check(horn_on and not Els.held.get(&"ah", false), "H held = A/H horn, released = off")
	var lamps := car().headlights_on
	await tap(KEY_L)
	check(car().headlights_on != lamps, "L toggles the headlights")
	await tap(KEY_Q)
	await tap(KEY_X)
	await tap(KEY_X)
	await key_down(KEY_W)
	await secs(3.5)
	var fast := car().speed_mph()
	await tap(KEY_F)
	check(driving() and hud()._toast.text == "Stop the car first", "F is refused while the car is moving (toast: %s)" % hud()._toast.text)
	await key_up(KEY_W)
	check(fast > 12.0, "W accelerates (%.0f mph after 3.5 s)" % fast)
	var before_coast := car().speed_mph()
	await secs(2.0)
	check(car().speed_mph() < before_coast - 2.0 and car().speed_mph() > 1.0, "lifting off the throttle slows the car by itself (%.0f -> %.0f mph)" % [before_coast, car().speed_mph()])
	await hold(KEY_S, 1.2)
	check(car().speed_mph() < fast - 5.0, "S brakes (%.0f mph)" % car().speed_mph())
	await key_down(KEY_SPACE)
	await secs(2.5)
	await key_up(KEY_SPACE)
	check(car().speed_mph() < 3.0, "Space hand brake stops the car (%.1f mph)" % car().speed_mph())
	# getting out: the "E  Get in" prompt is up during the exit and from about 6 m away on foot
	await tap(KEY_F)
	check(await until(func() -> bool: return int(seat().get("mode")) == 3, 2.0), "F starts the exit (EXITING)")
	await frames(10)
	check(hud().prompt_text() == "E  Get in", "\"E  Get in\" is shown while getting out (shown: %s)" % hud().prompt_text())
	await until(func() -> bool: return bool(seat().call("is_on_foot")), 4.0)
	var door := car().enter_transform(&"driver")
	player().global_position = Vector3(door.origin.x, 0.1, door.origin.z) - car().global_transform.basis.x * 5.4
	await frames(10)
	check(hud().prompt_text() == "E  Get in", "\"E  Get in\" still shows 5.4 m from the door (shown: %s)" % hud().prompt_text())
	player().global_position = Vector3(door.origin.x, 0.1, door.origin.z) - car().global_transform.basis.x * 7.5
	await frames(10)
	check(hud().prompt_text() == "", "no prompt 7.5 m from the door")


func _section_radar() -> void:
	if not driving():
		await get_in()
	var forward := -car().global_transform.basis.z
	var target := Vehicles.spawn(&"civ_sedan", Transform3D(Basis.looking_at(forward, Vector3.UP),
		car().global_position + forward * 45.0 + Vector3(0.0, 0.5, 0.0)), main)
	target.set_handbrake(true)
	await tap(KEY_V)
	await secs(0.6)
	check(hud().radar.radar_on, "V switches the RADAR panel on")
	check(not main.hooks.radar.front_reading.is_empty() and hud().radar.values.has("front"),
		"RADAR reads the car ahead (FRONT %s mph)" % main.hooks.radar.front_reading)
	await tap(KEY_G)
	await secs(0.3)
	check(hud().radar.values.has("lock_f"), "G locks the front reading (LOCK F %s)" % str(hud().radar.values.get("lock_f", "")))
	await tap(KEY_V)
	await secs(0.3)
	check(not hud().radar.radar_on, "V again switches RADAR off")
	await tap(KEY_P)
	check(not hud().radar.alpr_on and main.hooks.radar.alpr_on == false, "P switches the plate reader off")
	await tap(KEY_P)
	check(hud().radar.alpr_on, "P switches the plate reader on again")
	await tap(KEY_TAB)
	check(Mdt.is_open, "Tab opens the MDT in the car")
	await key_down(KEY_W)
	await secs(1.5)
	var moving := car().speed_mph()
	await key_up(KEY_W)
	check(moving > 3.0, "the car can still be driven with the MDT open (%.0f mph)" % moving)
	await tap(KEY_TAB)
	check(not Mdt.is_open, "Tab closes the MDT")
	var records: GDScript = load("res://scripts/traffic_stop/records.gd")
	var wanted: Dictionary = records.call("for_plate", target.plate, "Sedan")
	wanted["warrant"] = true
	target.set_meta("mdt_record", records.call("finish", wanted))
	target.set_meta("alpr_force", true)
	target.set_meta("flees", false)
	Els.set_lights(false)   # lights off: the marked car is only marked (with the lights on within 65 ft Pursuit would act on it at once)
	main.hooks.alpr_enabled = true
	check(await until(func() -> bool: return not hud().radar.alpr_hits.is_empty(), 4.0), "ALPR reads an ordinary car and lists the warrant hit (%s)" % str(hud().radar.alpr_hits))
	check(Pursuit.get("_marked").get("vehicle") == target and not Pursuit.get("_marked").get("flees"), "the hit car is marked for Pursuit (pulls over: flees false)")
	Pursuit.clear_mark()
	main.hooks.alpr_enabled = false
	target.queue_free()
	await hold(KEY_S, 2.5)


func _section_hud() -> void:
	var h: Node = hud()
	h.set_prompt_from(&"seat", "E  Get in")
	check(h.prompt_text() == "E  Get in", "HUD shows the seat's prompt")
	h.set_prompt("E  Cuff")                                  # a direct caller is the Pursuit banner
	check(h.prompt_text() == "E  Cuff", "Pursuit's prompt wins over \"E  Get in\"")
	h.set_prompt_from(&"scene", "E  Talk")
	check(h.prompt_text() == "E  Cuff", "Pursuit's prompt also wins over the scene's \"E  Talk\"")
	h.set_prompt("")
	check(h.prompt_text() == "E  Talk", "scene prompt shows when Pursuit's is gone")
	h.set_prompt_from(&"scene", "")
	check(h.prompt_text() == "E  Get in", "seat prompt returns last")
	h.set_prompt_from(&"seat", "")
	check(h.prompt_text() == "" and not h._prompt.visible, "no prompt left")
	h.set_weapon_line("Pistol", 17, 34)
	check(h.weapon_slot_text().begins_with("Pistol  17 / 34"), "weapon line in the top-right slot")
	h.set_equipment_lines(["Taser out   LMB use", "on target, 14 ft"])
	check(h.weapon_slot_text().begins_with("Taser out"), "Taser lines take the slot over from the weapon line")
	h.set_equipment_lines([])
	check(h.weapon_slot_text().begins_with("Pistol  17 / 34"), "weapon line returns when the Taser lines go")
	h.clear_weapon_line()
	check(h.weapon_slot_text() == "", "slot empty again")
	var overlay: CanvasLayer = (load("res://scripts/traffic_stop/stop_overlay.gd") as GDScript).call("of", get_tree())
	overlay.call("set_offer", "Code 2: Trespassing.  Y respond  N pass  (25)")
	overlay.call("set_flashlight_line", true)
	await frames(3)
	check(h.offer_text() == "Code 2: Trespassing.  Y respond  N pass  (25)" and overlay.get("_offer").modulate.a == 0.0,
		"TrafficStop's amber offer is drawn by the HUD (overlay label transparent)")
	check(h.weapon_slot_text() == "Flashlight on   4 off", "TrafficStop's flashlight line is drawn by the HUD slot")
	overlay.call("set_offer", "")
	overlay.call("set_flashlight_line", false)
	await frames(3)
	check(h.offer_text() == "" and h.weapon_slot_text() == "", "offer and flashlight line clear again")


func _section_calls() -> void:
	var d: Node = main.hooks.director
	if not driving():
		await get_in()
	await place_car(Vector3(3.5, 0.0, -60.0), Vector3(0.0, 0.0, -1.0))
	var call: Dictionary = d.offer(&"traffic_stop", {"position": Vector3(0.0, 0.0, -320.0)})
	await frames(10)
	check(not Calls.offer_call.is_empty() and Calls.offer_call == call, "director offers a playable call (%s)" % str(call.get("head", "")))
	check(hud().offer_text().begins_with("Code 2") and hud().offer_text().contains("Y respond"), "amber offer line on the HUD (%s)" % hud().offer_text())
	check(hud()._offer.visible and not hud()._mission.visible, "the gold mission line stays hidden while the offer is up")
	await tap(KEY_Y)
	check(not Calls.current.is_empty() and Calls.current.get("status") == &"assigned", "Y accepts the call (assigned)")
	check(GameState.duty_status == "Busy", "duty status turns Busy")
	check(hud().mission_text().begins_with("Respond to the"), "gold mission line: %s" % hud().mission_text())
	await frames(10)
	var markers: Array = hud().minimap._markers
	check(markers.size() == 1 and markers[0]["kind"] == &"call", "minimap has the yellow call marker")
	check(seat().get("_feed").highlight_street == "Hoover St", "the call's street is highlighted on the minimap")
	check(d.scene != null and not d.scene.spawned, "scene actors wait until the player is within 230 m")
	await place_car(Vector3(3.5, 0.0, -250.0), Vector3(0.0, 0.0, -1.0), 30.0)
	await frames(30)
	check(d.scene.spawned and d.scene.car != null and is_instance_valid(d.scene.car), "scene car appears when the player gets close")
	await place_car(Vector3(3.5, 0.0, d.scene.origin.z + 14.0), Vector3(0.0, 0.0, -1.0), 20.0)
	check(await until(func() -> bool: return Calls.current.get("status") == &"on_scene", 6.0), "10-97 when the player is within 25 m (on scene)")


func _section_stop() -> void:
	var d: Node = main.hooks.director
	if d.scene == null:
		print("stop section needs the calls section first")
		return
	var scene_car: Vehicle = d.scene.car
	var ahead := -scene_car.global_transform.basis.z
	TrafficStop.auto_detect = true
	if not Els.lights_active():
		await tap(KEY_Q)
	await place_car(scene_car.global_position - ahead * 24.0, ahead, 22.0)
	check(await until(func() -> bool: return TrafficStop.state == TrafficStop.State.PULLING_OVER, 8.0),
		"lights on behind the car: TrafficStop starts the stop (pulling over)")
	check(TrafficStop.vehicle == scene_car, "the stopped car is the call's car")
	check(await until(func() -> bool: return TrafficStop.state == TrafficStop.State.STOPPED, 40.0), "the car pulls over and stops")
	check(TrafficStop.driver != null, "the driver sits in the car")
	check(await until(func() -> bool: return Calls.stats["stops"] >= 1, 5.0), "traffic stop radio call logged (stops %d)" % Calls.stats["stops"])
	await get_out()
	check(bool(seat().call("is_on_foot")), "F gets the officer out once the car has stopped")
	check(await until(func() -> bool: return TrafficStop.state == TrafficStop.State.ON_FOOT, 4.0), "TrafficStop sees the officer on foot")
	check(await until(func() -> bool: return GameState.duty_status == "Busy", 3.0), "status is Busy during the stop")
	check(not hud().radar.visible, "RADAR/ALPR and ELS panels hide when the officer gets out")
	var door := scene_car.enter_transform(&"driver")
	player().global_position = Vector3(door.origin.x, 0.1, door.origin.z)
	await frames(30)
	check(hud().prompt_text() == "E  Talk to the driver", "prompt \"E  Talk to the driver\" (shown: %s)" % hud().prompt_text())
	await tap(KEY_E)
	check(TrafficStop.dialog_open, "E opens the dialog panel")
	var score_before: int = GameState.score
	var dialog: Object = TrafficStop.dialog
	dialog.choose(&"why")
	dialog.choose(&"docs")
	dialog.choose(&"warn")
	dialog.choose(&"done")
	await frames(10)
	check(not TrafficStop.dialog_open and GameState.score != score_before, "warning ruling closes the panel and scores (%+d)" % (GameState.score - score_before))
	check(await until(func() -> bool: return Calls.current.is_empty(), 3.0), "the call is cleared when the stop is finished")
	check(d.completed >= 1 and d.scene == null, "director finished the scene")
	await go_to_door()
	check(hud().prompt_text() == "E  Get in", "prompt \"E  Get in\" back at the patrol car")
	await tap(KEY_E)
	check(await until(func() -> bool: return driving(), 6.0), "E gets the officer back into the car")
	check(hud().radar.visible, "vehicle panels return in the car")
	check(await until(func() -> bool: return TrafficStop.state == TrafficStop.State.IDLE, 20.0), "the stopped car is released, TrafficStop idle")
	TrafficStop.auto_detect = false


## Foot chase to the end: join (C), Taser (LMB) when the suspect still runs, cuffs (E), process (E), booking menu.
func _foot_chase_to_booking(label: String) -> void:
	var suspect: Node3D = Pursuit.suspect
	if Pursuit.state == Pursuit.State.BAILED:
		await tap(KEY_C)
		check(Pursuit.state == Pursuit.State.FOOT_CHASE and hud()._foot_chase.visible,
			"%s: C joins the chase, FOOT CHASE gauge shows (%s)" % [label, hud()._foot_chase.text])
	if Pursuit.state == Pursuit.State.FOOT_CHASE:
		check(await until(func() -> bool: return hud().weapon_slot_text().begins_with("Taser out"), 5.0),
			"%s: Taser line in the weapon slot (%s)" % [label, hud().weapon_slot_text().replace("\n", " | ")])
		# the suspect runs at the officer's speed: put him in front of the muzzle and aim at the chest
		for _i in 3:
			suspect.global_position = _in_front(7.0)
			var chest := suspect.global_position + Vector3(0.0, 1.1, 0.0)
			var dir: Vector3 = (chest - player().camera.global_position).normalized()
			player().call("force_look", atan2(-dir.x, -dir.z), asin(dir.y))
			await frames(2)
		suspect.global_position = _in_front(7.0)
		await click(MOUSE_BUTTON_LEFT)
		check(await until(func() -> bool: return Pursuit.state == Pursuit.State.SUBDUED, 2.0), "%s: LMB Taser hits, suspect is down (SUBDUED)" % label)
	check(hud().prompt_text() == "E  Cuff", "%s: prompt \"E  Cuff\" (shown: %s)" % [label, hud().prompt_text()])
	suspect.global_position = _in_front(1.5)
	await tap(KEY_E)
	check(Pursuit.state == Pursuit.State.CUFFING, "%s: E starts the cuffs (Cuffing...)" % label)
	check(await until(func() -> bool: return Pursuit.state == Pursuit.State.CUFFED, 5.0), "%s: suspect cuffed after about 3 s" % label)
	check(hud().prompt_text() == "E  Process the suspect", "%s: prompt \"E  Process the suspect\" (shown: %s)" % [label, hud().prompt_text()])
	await tap(KEY_E)
	check(await until(func() -> bool: return TrafficStop.state == TrafficStop.State.BOOKING and TrafficStop.dialog_open, 2.0),
		"%s: E on the cuffed suspect opens the booking menu" % label)
	check(Pursuit.state == Pursuit.State.IDLE, "%s: pursuit is closed (processed)" % label)
	var score_before: int = GameState.score
	var booking: Object = TrafficStop.dialog
	booking.choose(&"book")
	booking.choose(&"arrest_on")
	booking.choose(&"done")
	await frames(10)
	check(not TrafficStop.dialog_open and GameState.score != score_before, "%s: booking scores (%+d) and closes" % [label, GameState.score - score_before])


## A ground point `metres` in front of the officer (the way the camera looks).
func _in_front(metres: float) -> Vector3:
	var yaw: float = player().get("yaw")
	return player().global_position + Vector3(-sin(yaw), 0.0, -cos(yaw)) * metres + Vector3(0.0, 0.1, 0.0)


func _section_pursuit() -> void:
	var d: Node = main.hooks.director
	if not driving():
		await get_in()
	main.hooks.alpr_enabled = true
	Pursuit.lost_enabled = false
	if not Els.lights_active():
		await tap(KEY_Q)
	await place_car(Vector3(3.5, 0.0, -60.0), Vector3(0.0, 0.0, -1.0))
	var completed_before: int = d.completed
	d.offer(&"stolen_vehicle", {"position": Vector3(0.0, 0.0, -300.0)})
	await frames(5)
	await tap(KEY_Y)
	check(Calls.current.get("type") == &"stolen_vehicle" and Calls.current.get("code") == 3, "stolen vehicle call (Code 3) accepted")
	await place_car(Vector3(3.5, 0.0, -200.0), Vector3(0.0, 0.0, -1.0), 10.0)
	check(await until(func() -> bool: return d.scene.spawned, 3.0), "BOLO car is placed when the player is close")
	var bolo: Vehicle = d.scene.car
	check(bolo.plate == Calls.current.get("plate") and bolo.get_meta("mdt_record")["stolen"], "the car has the plate of the call and a stolen record")
	var behind := (-bolo.global_transform.basis.z)
	await place_car(bolo.global_position - behind * 42.0, behind, 8.0)
	check(await until(func() -> bool: return Pursuit.snapshot()["toast"].begins_with("ALPR HIT"), 4.0),
		"ALPR reads the plate: %s" % Pursuit.snapshot()["toast"])
	check(not hud().radar.alpr_hits.is_empty() and String(hud().radar.alpr_hits[0]).contains(bolo.plate), "ALPR panel lists the hit (%s)" % str(hud().radar.alpr_hits))
	await place_car(bolo.global_position - behind * 14.0, behind, 6.0)
	check(await until(func() -> bool: return Pursuit.state == Pursuit.State.PURSUIT, 4.0), "lights on within 65 ft: the car runs, PURSUIT starts")
	check(Pursuit.snapshot()["line"].begins_with("PURSUIT") and Pursuit.snapshot()["toast"] != "", "PURSUIT line and toast on the HUD (%s)" % Pursuit.snapshot()["line"])
	check(GameState.duty_status == "Busy", "Busy while the pursuit runs")
	Pursuit.set_pit_decision(true, 1.0)
	await tap(KEY_R)
	check(Pursuit.pit_state() == Pursuit.PitState.REQUESTED, "R requests the PIT")
	check(await until(func() -> bool: return Pursuit.pit_state() == Pursuit.PitState.AUTHORIZED, 4.0), "PIT authorized")
	Pursuit.force_pit_success(1.0)
	check(Pursuit.state == Pursuit.State.SUSPECT_DOWN, "PIT: the car spun out")
	check(await until(func() -> bool: return Pursuit.state == Pursuit.State.BAILED, 20.0), "the driver bails out on foot")
	check(await until(func() -> bool: return bool(seat().call("is_on_foot")), 12.0), "the player's car brakes and the officer gets out for the foot chase")
	await _foot_chase_to_booking("pursuit")
	check(await until(func() -> bool: return d.completed > completed_before and Calls.current.is_empty(), 4.0), "the call ends when the booking is done (director cleared)")
	check(await until(func() -> bool: return GameState.duty_status == "Available", 25.0), "Available again after the booking")
	var events: Array = main.hooks.duty.events
	var order := ["pursuit_started", "pit_spun", "bailed", "downed", "cuffed", "booking_started", "booking_finished"]
	var last := -1
	var in_order := true
	for event_name in order:
		var at := events.find(StringName(event_name))
		if at < 0 or at < last:
			in_order = false
		last = at
	check(in_order and events.has(&"process_requested") and events.has(&"pursuit_ended_processed"), "chain order: %s" % str(events))
	Pursuit.lost_enabled = true


func _section_flee() -> void:
	var d: Node = main.hooks.director
	if not driving():
		await get_in()
	Pursuit.lost_enabled = false
	TrafficStop.auto_detect = true
	if Els.lights_active():
		await tap(KEY_Q)
	await place_car(Vector3(3.5, 0.0, -60.0), Vector3(0.0, 0.0, -1.0))
	d.offer(&"traffic_stop", {"position": Vector3(0.0, 0.0, -150.0), "flees": true, "cruise_factor": 0.5})
	await frames(5)
	await tap(KEY_Y)
	check(await until(func() -> bool: return d.scene != null and d.scene.spawned, 3.0), "traffic stop call: the car is placed")
	var runner: Vehicle = d.scene.car
	check(Pursuit.get("_marked").get("vehicle") == runner, "the car that will not stop is marked like an ALPR hit")
	var ahead := -runner.global_transform.basis.z
	await place_car(runner.global_position - ahead * 16.0, ahead, 8.0)
	await tap(KEY_Q)
	check(await until(func() -> bool: return Pursuit.state == Pursuit.State.PURSUIT, 5.0), "lights on behind it: the car flees and Pursuit starts")
	check(TrafficStop.state == TrafficStop.State.IDLE, "TrafficStop leaves the marked car to Pursuit")
	check(Pursuit.target == runner and Pursuit.snapshot()["toast"] == "The driver is fleeing!", "\"The driver is fleeing!\" (%s)" % Pursuit.snapshot()["toast"])
	Pursuit.end(&"aborted")
	await frames(10)
	check(await until(func() -> bool: return d.scene == null, 4.0), "the call ends when the pursuit is aborted")
	TrafficStop.auto_detect = false
	Pursuit.lost_enabled = true


func _section_armed() -> void:
	await _armed_case("run", 0.0)
	await _armed_case("surrender", 1.0)


func _armed_case(label: String, surrender_chance: float) -> void:
	var d: Node = main.hooks.director
	if driving():
		await get_out()
	player().global_position = Vector3(2.0, 0.1, -60.0)   # well away from the call (the previous section may end next to it)
	await frames(5)
	var completed_before: int = d.completed
	d.offer(&"armed_robbery", {"position": Vector3(0.0, 0.0, -150.0), "surrender_chance": surrender_chance})
	await frames(5)
	await tap(KEY_Y)
	check(Calls.current.get("type") == &"armed_robbery", "armed (%s): robbery call accepted" % label)
	player().global_position = Vector3(2.0, 0.1, -105.0)
	check(await until(func() -> bool: return d.scene.spawned, 3.0), "the suspect is placed near the call")
	var suspect: Node3D = d.scene.suspect
	player().global_position = suspect.global_position + Vector3(0.0, 0.0, 30.0)
	await frames(30)
	check(hud()._toast.visible and hud()._toast.text.begins_with("They're holding a gun"), "hint on sight: %s" % hud()._toast.text)
	check(suspect.get("model_kind") == "civilian" and String(suspect.get("state")) != "", "armed suspect stands at the scene")
	await tap(KEY_R)
	check(await until(func() -> bool: return Pursuit.is_active(), 6.0), "armed (%s): R orders the drop, the suspect %s and the foot chase starts" % [label, "gives up" if surrender_chance > 0.5 else "runs"])
	await _foot_chase_to_booking("armed-" + label)
	check(await until(func() -> bool: return d.completed > completed_before, 4.0), "armed (%s): call cleared after the booking" % label)


func _section_talk() -> void:
	var d: Node = main.hooks.director
	if driving():
		await get_out()
	var completed_before: int = d.completed
	d.offer(&"traffic_collision", {"position": Vector3(0.0, 0.0, -120.0)})
	await frames(5)
	await tap(KEY_Y)
	check(Calls.current.get("type") == &"traffic_collision", "traffic collision call accepted")
	player().global_position = Vector3(2.0, 0.1, -60.0)
	check(await until(func() -> bool: return d.scene.spawned and d.scene.people.size() == 2, 3.0), "two people and two crashed cars are placed")
	var crashed := 0
	for v: Vehicle in Vehicles.all:
		if v.has_meta("stop_hold") and v.global_position.distance_to(d.scene.origin) < 12.0:
			crashed += 1
	check(crashed == 2, "two crashed cars stand at the scene (%d)" % crashed)
	for i in 2:
		var person: Node3D = d.scene.people[i]
		player().global_position = person.global_position + Vector3(1.4, 0.0, 0.0)
		await frames(20)
		check(hud().prompt_text() == "E  Talk", "person %d: prompt \"E  Talk\" (shown: %s)" % [i + 1, hud().prompt_text()])
		await tap(KEY_E)
		check(d.scene.talked[i] and hud()._toast.text.begins_with("Driver:"), "person %d: E takes the statement (%s)" % [i + 1, hud()._toast.text.left(40)])
	check(await until(func() -> bool: return d.completed > completed_before and Calls.current.is_empty(), 10.0), "both heard: the call is cleared")
	check(hud().prompt_text() == "", "no prompt left after the call")


func _section_weapons() -> void:
	if driving():
		await get_out()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await frames(2)
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED   # a headless display server cannot capture the mouse
	if captured:
		await tap(KEY_5)
		check(await until(func() -> bool: return Weapons.equipped == &"pistol", 3.0), "5 draws the pistol")
		check(hud().weapon_slot_text().begins_with("Pistol"), "weapon line shows (%s)" % hud().weapon_slot_text())
		await until(func() -> bool: return Weapons.state == Weapons.State.READY, 3.0)
		var before: int = Weapons.get_ammo(&"pistol")["mag"]
		await click(MOUSE_BUTTON_LEFT)
		check(Weapons.get_ammo(&"pistol")["mag"] == before - 1, "LMB fires (%d -> %d)" % [before, Weapons.get_ammo(&"pistol")["mag"]])
	else:
		print("note: mouse capture is not available here: the pistol is drawn through Weapons.equip instead of 5 and LMB")
		Weapons.equip(&"pistol", true)
		await frames(10)
		check(hud().weapon_slot_text().begins_with("Pistol"), "weapon line shows (%s)" % hud().weapon_slot_text())
	var d: Node = main.hooks.director
	var completed_before: int = d.completed
	d.offer(&"armed_robbery", {"position": Vector3(0.0, 0.0, -150.0)})
	await frames(5)
	await tap(KEY_Y)
	player().global_position = Vector3(2.0, 0.1, -105.0)
	await until(func() -> bool: return d.scene.spawned, 3.0)
	var suspect: Node3D = d.scene.suspect
	player().global_position = suspect.global_position + Vector3(0.0, 0.0, 40.0)
	player().call("force_look", 0.0, 0.0)
	await frames(30)
	# shots at the suspect before any chase: the foot chase is set up and Pursuit gets the fall
	var events_before: int = main.hooks.duty.events.size()
	for _i in 6:
		suspect.global_position = _in_front(9.0)
		var chest := suspect.global_position + Vector3(0.0, 1.0, 0.0)
		var dir: Vector3 = (chest - player().camera.global_position).normalized()
		player().call("force_look", atan2(-dir.x, -dir.z), asin(dir.y))
		await frames(3)
		Weapons.fire_at(suspect, "torso", true)
		await frames(4)
		if Pursuit.state != Pursuit.State.IDLE and String(suspect.get("state")) == "downed":
			break
	var new_events: Array = main.hooks.duty.events.slice(events_before)
	check(new_events.has(&"bailed"), "shooting the armed suspect sets up the foot chase (events %s)" % str(new_events))
	check(String(suspect.get("state")) == "downed" and (Pursuit.is_active() or new_events.has(&"pursuit_ended_suspect_down")), "the pistol took him down and Pursuit handled the fall (%s)" % suspect.get("state"))
	if captured:
		await tap(KEY_5)
	else:
		Weapons.holster()
	check(await until(func() -> bool: return Weapons.equipped == &"", 3.0), "the pistol is holstered again and the weapon line goes")
	Pursuit.end(&"aborted")
	await frames(10)
	check(await until(func() -> bool: return d.scene == null or d.completed > completed_before, 6.0), "the call ends when the chase is aborted")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _section_quiet() -> void:
	var hooks: Node = main.hooks
	if driving():
		await get_out()
	Calls.ambient_enabled = true
	Calls.auto_offers = true
	hooks.alpr_enabled = true
	hooks.quiet()
	await frames(5)
	var civilians := 0
	for v: Vehicle in Vehicles.all:
		if not v.is_police and not v.is_queued_for_deletion():
			civilians += 1
	check(civilians == 0, "quiet(): no civilian car is left (%d)" % civilians)
	check(not Calls.ambient_enabled and not Calls.auto_offers and not hooks.director.enabled and not hooks.radar.alpr_enabled,
		"quiet(): ambient radio, random offers, call director and ALPR are off")
	check(hooks.recycler == null and Traffic.ambient_target == 0 and Traffic.cars.is_empty(), "quiet(): the recycler is closed and Traffic has no cars")
	await secs(4.0)
	var again := 0
	for v: Vehicle in Vehicles.all:
		if not v.is_police and not v.is_queued_for_deletion():
			again += 1
	check(again == 0 and Calls.offer_call.is_empty(), "quiet(): nothing comes back (cars %d, offer %s)" % [again, str(not Calls.offer_call.is_empty())])
