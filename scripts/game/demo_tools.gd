extends Node
## Helpers for the scripted demos (scenarios/_demo_stop.gd, _demo_pursuit.gd): waiting on conditions, screenshots that follow the
## scenario runner's --out folder, the suspect that tires on a foot chase, the bot that drives the patrol car after a fleeing car
## (the pursuit module's ChaseDriver), and the officer's aim at a target. Everything the demos do goes through the same public
## calls a player's keys reach; the helpers only replace the hands.

const ChaseDriver := preload("res://scripts/pursuit/chase_driver.gd")

var main: Node
var scenario_name := "demo"
var log_lines: Array[String] = []

var follow: Node3D               ## the patrol car drives up behind this car (steer_towards + cruise by the gap)
var follow_hold := 18.0
var follow_max := 45.0
var chaser: ChaseDriver
var tired: CharacterBody3D           ## a suspect whose run is slowed (the foot chase would never close otherwise)
var tired_factor := 0.8
var aim_target: Node3D               ## the officer's camera follows the chest of this node
var run_to: Node3D                   ## the officer runs after this node, along the path he ran (fences and corners are passed where he passed)
var _trail: Array[Vector3] = []
var _trail_index := 0
var _trail_timer := 0.0
var _stuck_timer := 0.0
var _stuck_from := Vector3.ZERO
var _detour := 0.0                   # seconds left of a sidestep around something in the way
var _detour_dir := Vector3.ZERO
var _detour_side := 1.0
var _run_timer := 0.0
var _out_dir := ""


func _init() -> void:
	process_physics_priority = 100   # after Npc / Vehicle physics, so the velocity scaling sees this frame's result


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	_out_dir = args[i + 1] if i >= 0 and i + 1 < args.size() else ProjectSettings.globalize_path("user://scenario_shots")
	DirAccess.make_dir_recursive_absolute(_out_dir)


# --- waiting --------------------------------------------------------------------------------------------------------------

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Waits until cond is true; false after `timeout` seconds. The demo goes on either way and says so in the log.
func until(cond: Callable, timeout: float, what := "") -> bool:
	var left := timeout
	while left > 0.0:
		if cond.call():
			return true
		await get_tree().process_frame
		left -= get_process_delta_time()
	var ok: bool = cond.call()
	if not ok and not what.is_empty():
		note("timeout waiting for " + what)
	return ok


func note(text: String) -> void:
	log_lines.append(text)
	print("DEMO ", scenario_name, ": ", text)


## Where everything is (debug line for the demo logs).
func where() -> String:
	var director: Node = main.hooks.director
	var text := "patrol %s %.0f mph" % [str(main.patrol_vehicle.global_position.snapped(Vector3.ONE * 0.1)), main.patrol_vehicle.speed_mph()]
	if director.scene != null and director.scene.get("car") != null and is_instance_valid(director.scene.car):
		text += ", scene car %s %.0f mph" % [str(director.scene.car.global_position.snapped(Vector3.ONE * 0.1)), director.scene.car.speed_mph()]
	return text + ", officer %s" % str(main.player.global_position.snapped(Vector3.ONE * 0.1))


## Screenshot named after the step (folder: the runner's --out).
func snap(label: String) -> void:
	if OS.get_cmdline_user_args().has("--noshots"):   # clean frame-time measurement: screenshots cause hitches
		return
	if DisplayServer.get_name() == "headless":
		note("shot " + label + " (headless): " + where())
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s_%s.png" % [_out_dir, scenario_name, label])
	note("shot " + label + ": " + where())


# --- driving the patrol car after a car ---------------------------------------------------------------------------------

## Drives the patrol car towards `target` and holds `hold` metres behind it (never faster than max_mph).
func follow_car(target: Node3D, hold := 18.0, max_mph := 45.0) -> void:
	follow = target
	follow_hold = hold
	follow_max = max_mph


func stop_follow(brake := 0.7) -> void:
	follow = null
	main.patrol_vehicle.set_cruise_mph(-1.0)
	main.patrol_vehicle.set_controls(0.0, 0.0, brake)


## The bot follows the fleeing car's route (the module's ChaseDriver). mode: ChaseDriver.Mode.FOLLOW / PIT / STOP.
func chase_car(gap := 16.0) -> void:
	chaser = ChaseDriver.new()
	chaser.attach(main.patrol_vehicle, World.road_graph)
	chaser.target = Pursuit.target
	chaser.target_driver = Pursuit.driver
	chaser.gap = gap


func stop_chase_car() -> void:
	if chaser != null:
		chaser.mode = ChaseDriver.Mode.STOP
		main.patrol_vehicle.set_controls(0.0, 0.0, 1.0)
	chaser = null


# --- the officer on foot ------------------------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if follow != null and is_instance_valid(follow):
		var car: Vehicle = main.patrol_vehicle
		var gap := distance_to_car(follow)
		var theirs: float = float(follow.call("speed_mph")) if follow.has_method("speed_mph") else 0.0
		car.steer_towards(follow.global_position)
		car.set_cruise_mph(clampf(theirs + (gap - follow_hold) * 0.45, 0.0, follow_max))
	if chaser != null and is_instance_valid(chaser.target):
		if Pursuit.driver != null:
			chaser.target_driver = Pursuit.driver
		chaser.update(dt)
	if tired != null and is_instance_valid(tired):
		tired.velocity.x *= tired_factor
		tired.velocity.z *= tired_factor
	_run_timer -= dt
	var officer: Node3D = main.player
	if run_to != null and is_instance_valid(run_to):
		_follow_trail(dt, officer)
	elif not _trail.is_empty():
		_trail.clear()
		_trail_index = 0
	if aim_target != null and is_instance_valid(aim_target):
		var chest := aim_target.global_position + Vector3(0.0, 1.1, 0.0)
		var dir: Vector3 = (chest - officer.camera.global_position).normalized()
		officer.call("force_look", atan2(-dir.x, -dir.z), asin(dir.y))


## The officer follows the breadcrumbs of the runner (positions every 0.2 s); close behind him he goes straight at him.
func _follow_trail(dt: float, officer: Node3D) -> void:
	_trail_timer -= dt
	if _trail_timer <= 0.0:
		_trail_timer = 0.2
		var here := run_to.global_position
		if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(here) > 0.4:
			_trail.append(here)
	while _trail_index < _trail.size() - 1 and _flat(officer.global_position, _trail[_trail_index]) < 1.3:
		_trail_index += 1
	if _run_timer > 0.0:
		return
	_run_timer = 0.2
	var target := run_to.global_position
	if _flat(officer.global_position, target) > 5.0 and not _trail.is_empty():
		target = _trail[mini(_trail_index + 1, _trail.size() - 1)]
	# wedged against a car or a fence: a short sidestep, then on again (alternating sides)
	_stuck_timer += 0.2
	if _detour > 0.0:
		_detour -= 0.2
		target = officer.global_position + _detour_dir * 3.0
	elif _stuck_timer >= 1.0:
		if _flat(officer.global_position, _stuck_from) < 0.25 and _flat(officer.global_position, target) > 2.5:
			var to := target - officer.global_position
			to.y = 0.0
			_detour_dir = to.normalized().cross(Vector3.UP) * _detour_side
			_detour_side = -_detour_side
			_detour = 1.2
		_stuck_timer = 0.0
		_stuck_from = officer.global_position
	officer.call("walk_to", target, true)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func distance_to(node: Node3D) -> float:
	var d: Vector3 = node.global_position - main.player.global_position
	d.y = 0.0
	return d.length()


func distance_to_car(node: Node3D) -> float:
	var d: Vector3 = node.global_position - main.patrol_vehicle.global_position
	d.y = 0.0
	return d.length()
