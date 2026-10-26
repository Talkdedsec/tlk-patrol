extends "res://scripts/dev/scenario_base.gd"
## Call -> traffic stop -> warning, played through the game's own loop: the officer gets in, a traffic stop call is offered and
## accepted (Y), the patrol car drives up behind the call's car, the lights come on, TrafficStop pulls it over, the officer gets
## out, walks to the driver, talks (E), questions, decides (warning), walks back and drives off. The bot only replaces the hands.
## Record: araclar/kayit.sh _demo_stop   (about 80 s; shots go to the runner's --out folder)

const DemoTools := preload("res://scripts/game/demo_tools.gd")
const PerfProbe := preload("res://scripts/game/perf_probe.gd")

var t: Node


func _init() -> void:
	duration = 240.0     # safety: the script ends the run itself


func setup(main_scene: Node) -> void:
	super(main_scene)
	main.add_child(PerfProbe.new())
	t = DemoTools.new()
	t.main = main
	t.scenario_name = "_demo_stop"
	main.add_child(t)
	main.hooks.set_calls_enabled(false)
	main.hooks.alpr_enabled = false
	Calls.ambient_enabled = false
	Calls.auto_offers = false
	TrafficStop.auto_detect = true
	at(0.3, func() -> void: _run())


func _run() -> void:
	var seat: Node = main.seat
	var car: Vehicle = main.patrol_vehicle
	var director: Node = main.hooks.director
	seat.scripted_drive = true
	# the north end of the straight part of Hoover St, facing south; the officer stands behind the driver door
	var south := Vector3(0.0, 0.0, 1.0)
	car.teleport(Transform3D(Basis.looking_at(south, Vector3.UP), Vector3(-3.5, 0.4, -138.0)))
	var door := car.enter_transform(&"driver")
	main.player.global_position = Vector3(door.origin.x, 0.1, door.origin.z) - south * 1.4
	main.player.force_look(atan2(-south.x, -south.z), Officer.DEFAULT_PITCH)
	await t.wait(1.5)
	seat.enter(car)
	await t.until(func() -> bool: return seat.is_driving(), 8.0, "officer in the car")
	await t.wait(1.0)

	# --- the call -------------------------------------------------------------------------------------------------
	director.offer(&"traffic_stop", {"position": Vector3(0.0, 0.0, -85.0), "cruise_factor": 0.55, "violation": &"lane"})
	await t.wait(4.5)
	await t.snap("01_offer")
	Calls.respond()                                         # Y
	await t.until(func() -> bool: return director.scene != null and director.scene.spawned, 5.0, "scene car")
	await t.wait(1.5)
	await t.snap("02_accepted")

	# --- drive up behind the car, lights on, TrafficStop pulls it over -------------------------------------------------
	var target: Vehicle = director.scene.car
	t.follow_car(target, 22.0, 44.0)
	await t.until(func() -> bool: return t.distance_to_car(target) < 75.0, 30.0, "closing in")
	Els.set_stage(2)
	Els.set_lights(true)
	await t.until(func() -> bool: return TrafficStop.state != TrafficStop.State.IDLE, 25.0, "traffic stop start")
	await t.wait(1.2)
	await t.snap("03_pulling_over")
	await t.until(func() -> bool: return TrafficStop.state == TrafficStop.State.STOPPED, 40.0, "car stopped")
	t.follow_car(target, 11.0, 15.0)                         # roll up and stop behind it
	await t.until(func() -> bool: return car.speed_mph() < 3.0 and t.distance_to_car(target) < 16.0, 15.0, "patrol car stopped")
	t.stop_follow(0.8)
	await t.wait(1.0)
	await t.snap("04_stopped")

	# --- on foot: to the driver, talk, rule ---------------------------------------------------------------------------
	seat.exit()
	await t.until(func() -> bool: return seat.is_on_foot(), 8.0, "officer out")
	await t.wait(0.8)
	var stop_door := target.enter_transform(&"driver").origin
	main.player.walk_to(Vector3(stop_door.x, 0.1, stop_door.z), false)
	await t.until(func() -> bool: return t.distance_to(TrafficStop.driver if TrafficStop.driver != null else target) < 2.3, 25.0, "at the driver")
	await t.wait(0.6)
	await t.snap("05_talk_prompt")
	TrafficStop.open_dialog()                                # E
	await t.wait(2.0)
	await t.snap("06_dialog")
	var dialog: Object = TrafficStop.dialog
	dialog.choose(&"why")
	await t.wait(2.2)
	dialog.choose(&"docs")
	await t.wait(2.2)
	await t.snap("07_dialog_questions")
	dialog.choose(&"warn")
	await t.wait(2.0)
	await t.snap("08_warning")
	dialog.choose(&"done")
	await t.wait(2.0)
	await t.snap("09_score")

	# --- back to the car -------------------------------------------------------------------------------------------------
	var back := car.enter_transform(&"driver").origin
	main.player.walk_to(Vector3(back.x, 0.1, back.z), false)
	await t.until(func() -> bool: return t.distance_to(car) < 3.5, 25.0, "back at the patrol car")
	seat.enter(car)
	await t.until(func() -> bool: return seat.is_driving(), 8.0, "officer back in the car")
	await t.until(func() -> bool: return TrafficStop.state == TrafficStop.State.IDLE, 25.0, "stopped car released")
	await t.wait(2.0)
	await t.snap("10_done")
	t.note("score %d, calls cleared %d, status %s" % [GameState.score, director.completed, GameState.duty_status])
	main.get_tree().quit()
