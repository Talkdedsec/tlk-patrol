extends Node
## Player seat controller: "E Get in" prompt, door + sit animation, drive input, chase camera, car-only HUD panels,
## ELS shortcuts, mouse release for the ELS panel, and the HUD feed (minimap, street, dials).
## Modes: FOOT -> ENTERING -> DRIVING -> EXITING -> FOOT. API and key list: docs/api/game.md.

signal mode_changed(new_mode: int)

enum Mode { FOOT, ENTERING, DRIVING, EXITING }

const DriveInput := preload("res://scripts/game/drive_input.gd")
const GameInput := preload("res://scripts/game/game_input.gd")
const HudFeed := preload("res://scripts/game/hud_feed.gd")

const ENTER_RANGE := 6.0        # "E  Get in" shows and works from here (the prompt stays up at about 5 m)
const SEAT_DROP := 0.28         # TODO(tahmin): the seat marker sits on the cushion, the sit animation origin is the floor under the hip
const SEAT_FORWARD := 0.1       # TODO(tahmin): moves the hands closer to the wheel (the sit pose has the hips 0.26 m behind its origin)
const WALK_TIMEOUT := 2.5
const EXIT_MAX_MPH := 4.0
const MDT_REACH := 6.0           # m from the patrol car where Tab still opens the MDT on foot
const MOUSE_LOOK := 0.003
const LOOK_RETURN_DELAY := 1.2

var mode: int = Mode.FOOT
var officer: Officer
var vehicle: Vehicle
var camera: VehicleCamera
var hud                          ## HUD node (scripts/hud/hud.gd)
var hooks: Node                  ## game_hooks.gd, for the debug ALPR key
var scripted_drive := false      ## true: the keyboard is ignored, a scenario drives the car (cruise / steer_towards)

var _drive := DriveInput.new()
var _feed := HudFeed.new()
var _token := 0
var _frozen := false
var _saved_layer := 0
var _saved_mask := 0
var _prompt_mine := false
var _headlight_mode := -1        # -1 automatic (on at night), 0 forced off, 1 forced on
var _headlight_timer := 0.0
var _look_idle := 0.0
var _exit_wait := -1.0           # >= 0: braking to a stop, then getting out (Pursuit / TrafficStop asked for the exit)


func is_driving() -> bool:
	return mode == Mode.DRIVING


func is_on_foot() -> bool:
	return mode == Mode.FOOT


# --- enter / exit -------------------------------------------------------------------------------------------------

## Walks to the driver door, opens it, sits down and starts driving. instant = skip the animation (shots, scenarios).
func enter(target: Node3D, instant := false) -> void:
	var car := target as Vehicle
	if mode != Mode.FOOT or car == null or officer == null:
		return
	if car.driver != null and car.driver != officer:
		return
	mode = Mode.ENTERING
	mode_changed.emit(mode)
	_token += 1
	var token := _token
	vehicle = car
	officer.input_enabled = false
	officer.stop_scripted()
	if Weapons.equipped != &"":
		Weapons.holster(true)
	_set_prompt("")
	if not instant:
		await _walk_to_door(car, token)
		if token != _token:
			return
		car.open_driver_door()
		await _wait(0.18)
		if token != _token:
			return
		_freeze_officer(true)
		var length := officer.play_action(&"enter_vehicle")
		_glide(officer.global_transform, func() -> Transform3D: return _seat_xform(car), length * 0.3, length * 0.55, token)
		await _wait(length)
		if token != _token:
			return
		car.close_driver_door()
	else:
		_freeze_officer(true)
	_sit(car)


func _sit(car: Vehicle) -> void:
	officer.global_transform = _seat_xform(car)
	officer.play_action(&"sit_drive")
	car.set_driver(officer)
	officer.set("in_vehicle", true)
	_drive.reset()
	car.set_handbrake(false)
	car.set_engine_sound(true)
	if camera != null:
		camera.look_yaw = 0.0
		camera.follow(car)
		camera.make_current()
	_look_idle = 0.0
	if hud != null:
		hud.set_vehicle_hud(true)
	mode = Mode.DRIVING
	mode_changed.emit(mode)


## Other modules (Pursuit when the suspect bails, TrafficStop) ask the officer to get out: the car brakes to a stop
## first, then the officer gets out (the F key refuses instead while the car is moving).
func request_exit() -> void:
	if mode != Mode.DRIVING or vehicle == null:
		return
	if vehicle.speed_mph() <= EXIT_MAX_MPH:
		exit()
		return
	_exit_wait = 0.0
	vehicle.set_cruise_mph(-1.0)


## Gets out beside the driver door. Only below EXIT_MAX_MPH.
func exit() -> void:
	if mode != Mode.DRIVING or vehicle == null or officer == null:
		return
	if vehicle.speed_mph() > EXIT_MAX_MPH:
		if hud != null:
			hud.show_toast("Stop the car first", 1.5)
		return
	_exit_wait = -1.0
	mode = Mode.EXITING
	if Mdt.is_open:
		Mdt.close()
	mode_changed.emit(mode)
	_token += 1
	var token := _token
	var car := vehicle
	officer.set("in_vehicle", false)
	_drive.park(car)
	Els.release(&"ah")
	if hud != null:
		hud.set_vehicle_hud(false)
	car.open_driver_door()
	var length := officer.play_action(&"exit_vehicle")
	_glide(officer.global_transform, func() -> Transform3D: return _door_xform(car), length * 0.25, length * 0.7, token)
	await _wait(length)
	if token != _token:
		return
	var door := _door_xform(car)
	officer.release_action()
	_freeze_officer(false)
	officer.global_transform = door
	officer.input_enabled = true
	var forward := -car.global_transform.basis.z
	officer.force_look(atan2(-forward.x, -forward.z), Officer.DEFAULT_PITCH)
	officer.camera.make_current()
	car.set_driver(null)
	mode = Mode.FOOT
	mode_changed.emit(mode)
	await _wait(1.2)
	if mode == Mode.FOOT and is_instance_valid(car) and car.driver == null:
		car.close_driver_door()
		car.set_engine_sound(false)


func _walk_to_door(car: Vehicle, token: int) -> void:
	var door := car.enter_transform(&"driver")
	var target := Vector3(door.origin.x, officer.global_position.y, door.origin.z)
	var distance := Vector2(target.x - officer.global_position.x, target.z - officer.global_position.z).length()
	if distance > 0.35:
		var done := [false]
		var on_arrived := func() -> void: done[0] = true
		officer.arrived.connect(on_arrived, CONNECT_ONE_SHOT)
		officer.walk_to(target, distance > 1.5)
		var elapsed := 0.0
		while not done[0] and elapsed < WALK_TIMEOUT and token == _token:
			await get_tree().physics_frame
			elapsed += get_physics_process_delta_time()
		if officer.arrived.is_connected(on_arrived):
			officer.arrived.disconnect(on_arrived)
		officer.stop_scripted()
	if token == _token:
		officer.velocity = Vector3.ZERO
		officer.rotation.y = door.basis.get_euler().y   # the door transform faces the car


func _seat_xform(car: Vehicle) -> Transform3D:
	var b := car.global_transform.basis.orthonormalized()
	return Transform3D(b, car.seat_transform(&"driver").origin - b.y * SEAT_DROP - b.z * SEAT_FORWARD)


func _door_xform(car: Vehicle) -> Transform3D:
	var door := car.enter_transform(&"driver")
	return Transform3D(Basis(Vector3.UP, door.basis.get_euler().y), door.origin + Vector3(0.0, 0.03, 0.0))


## Moves the officer from `from` to a (live) target transform: wait `delay`, then ease over `duration`.
func _glide(from: Transform3D, target: Callable, delay: float, duration: float, token: int) -> void:
	var step := func(t: float) -> void:
		if token != _token or officer == null or not is_instance_valid(officer):
			return
		var to: Transform3D = target.call()
		officer.global_transform = Transform3D(from.basis.orthonormalized().slerp(to.basis.orthonormalized(), t), from.origin.lerp(to.origin, t))
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_method(step, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _freeze_officer(on: bool) -> void:
	if on == _frozen:
		return
	_frozen = on
	if on:
		_saved_layer = officer.collision_layer
		_saved_mask = officer.collision_mask
		officer.collision_layer = 0
		officer.collision_mask = 0
		officer.velocity = Vector3.ZERO
		officer.set_physics_process(false)
	else:
		officer.collision_layer = _saved_layer
		officer.collision_mask = _saved_mask
		officer.set_physics_process(true)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# --- per frame ----------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if _exit_wait >= 0.0 and mode == Mode.DRIVING:
		_exit_wait += delta
		vehicle.set_cruise_mph(-1.0)
		vehicle.set_controls(0.0, 0.0, 1.0)
		vehicle.set_handbrake(vehicle.speed_mph() < 12.0)
		if vehicle.speed_mph() <= EXIT_MAX_MPH or _exit_wait > 9.0:
			if _exit_wait > 9.0:
				vehicle.linear_velocity = Vector3.ZERO
			exit()
		return
	if scripted_drive:
		return
	if mode == Mode.DRIVING:
		_drive.apply(vehicle, delta)
	elif vehicle.driver == null:
		_drive.park(vehicle)


func _process(delta: float) -> void:
	if officer == null or not is_instance_valid(officer):
		return
	match mode:
		Mode.DRIVING:
			officer.global_transform = _seat_xform(vehicle)
			_update_headlights(delta)
			_update_look(delta)
		Mode.FOOT, Mode.EXITING:
			_update_prompt()
			if mode == Mode.FOOT and Mdt.is_open and not at_terminal():
				Mdt.close()
	_feed_hud(delta)


func _feed_hud(delta: float) -> void:
	_feed.hud = hud
	if mode == Mode.DRIVING and vehicle != null:
		var forward := -vehicle.global_transform.basis.z
		_feed.update(delta, vehicle.global_position, atan2(-forward.x, -forward.z), vehicle, _drive.throttle)
	else:
		_feed.update(delta, officer.global_position, officer.yaw, null, 0.0)


func _update_look(delta: float) -> void:
	if camera == null:
		return
	_look_idle += delta
	if _look_idle > LOOK_RETURN_DELAY:
		camera.look_yaw = lerp_angle(camera.look_yaw, 0.0, 1.0 - exp(-2.5 * delta))


func _update_headlights(delta: float) -> void:
	if _headlight_mode != -1:
		return
	_headlight_timer -= delta
	if _headlight_timer > 0.0:
		return
	_headlight_timer = 1.0
	var night: bool = World.lighting != null and World.lighting.is_night()
	if night != vehicle.headlights_on:
		vehicle.set_headlights(night)


# --- "E  Get in" prompt -------------------------------------------------------------------------------------------

func _near_door() -> bool:
	if vehicle == null or not is_instance_valid(vehicle) or officer == null:
		return false
	if mode == Mode.FOOT and not officer.input_enabled:
		return false   # (the prompt also shows while getting out: it stays up during the exit)
	return officer.global_position.distance_to(vehicle.enter_transform(&"driver").origin) <= ENTER_RANGE


func _update_prompt() -> void:
	_set_prompt("E  Get in" if _near_door() else "")


## The HUD arbitrates the prompts (game_hud.gd): Pursuit and TrafficStop prompts win over this one.
func _set_prompt(text: String) -> void:
	if hud == null:
		return
	if hud.has_method("set_prompt_from"):
		hud.set_prompt_from(&"seat", text)
		return
	if text.is_empty():
		if _prompt_mine:
			hud.set_prompt("")
			_prompt_mine = false
	else:
		hud.set_prompt(text)
		_prompt_mine = true


## Getting in is allowed unless another prompt owns the E key (cuff, talk, process) or a panel is open.
func _get_in_allowed() -> bool:
	if Mdt.is_open or TrafficStop.dialog_open:
		return false
	if hud != null and hud.has_method("prompt_text"):
		var shown: String = hud.prompt_text()
		return shown.is_empty() or shown == "E  Get in"
	return true


# --- input --------------------------------------------------------------------------------------------------------

## Tab opens the MDT only at the terminal: seated in the patrol car (it can still be driven) or standing next to it.
## Runs before the Mdt autoload's own handler (scene nodes get input first).
func _input(event: InputEvent) -> void:
	if officer == null or Mdt.is_open or not (event is InputEventKey):
		return
	if event.pressed and not event.echo and event.is_action("toggle_mdt") and not at_terminal():
		get_viewport().set_input_as_handled()
		if hud != null and not TrafficStop.dialog_open:
			hud.show_toast("The MDT is in the patrol car", 1.5)


## True where the MDT can be used: in the car, or within MDT_REACH of it.
func at_terminal() -> bool:
	if mode == Mode.DRIVING or mode == Mode.ENTERING:
		return true
	return vehicle != null and is_instance_valid(vehicle) and officer != null \
		and officer.global_position.distance_to(vehicle.global_position) <= MDT_REACH


func _unhandled_input(event: InputEvent) -> void:
	if officer == null:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == GameInput.FREE_MOUSE_KEY:
		toggle_mouse()
		return
	if mode == Mode.FOOT:
		if event.is_action_pressed("interact") and _near_door() and _get_in_allowed():
			enter(vehicle)
	elif mode == Mode.DRIVING:
		_driving_input(event)


func _driving_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and camera != null:
			camera.look_yaw -= event.relative.x * MOUSE_LOOK
			_look_idle = 0.0
	elif event.is_action_pressed("close_menu"):
		toggle_mouse()
	elif event.is_action_pressed("exit_vehicle"):
		exit()
	elif event.is_action_pressed("els_lights"):
		Els.set_lights(not Els.lights_on)
	elif event.is_action_pressed("els_siren"):
		next_siren()
	elif event.is_action_pressed("headlights"):
		_headlight_mode = 0 if vehicle.headlights_on else 1
		vehicle.set_headlights(_headlight_mode == 1)
	elif event.is_action_pressed("horn"):
		Els.press(&"ah")
	elif event.is_action_released("horn"):
		Els.release(&"ah")
	elif event.is_action_pressed("debug_alpr") and hooks != null and hooks.has_method("force_alpr_hit"):
		hooks.call("force_alpr_hit")


## Minimap: yellow destination marker + highlighted street of the assigned call, orange diamond on a marked car.
func set_destination(pos: Vector3, street := "") -> void:
	_feed.set_destination(pos, street)


func clear_destination() -> void:
	_feed.clear_destination()


func set_target_marker(target: Node3D) -> void:
	_feed.target_vehicle = target


## Frees the mouse (cursor visible, ELS panel clickable) or captures it again.
func toggle_mouse() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Next siren tone in the ELS order, after the last one everything is switched off (same cycle as the HUD debug key F5).
func next_siren() -> void:
	var tones: Array = Els.SIRENS.keys()
	var i := tones.find(Els.siren_tone)
	Els.set_siren(&"" if i == tones.size() - 1 else tones[i + 1])
