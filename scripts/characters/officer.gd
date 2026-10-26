class_name Officer
extends CharacterBody3D
## Player officer: WASD movement, mouse look, over-the-shoulder camera, RMB aim camera, weapon stance/animation API.
##
## Weapon rules (ammo, damage, hit tests) belong to the Weapons autoload. This class emits the input signals and exposes
## the pose/camera API (draw_weapon, holster_weapon, notify_shot, get_aim_ray, muzzle_transform).
## With auto_visuals = true (default) the officer reacts to its own input so it works without the Weapons autoload.

signal fire_requested
signal aim_changed(aiming: bool)
signal draw_requested
signal reload_requested
signal weapon_state_changed(state: StringName)
signal arrived                   # walk_to() / walk_path() reached the last target
signal walk_blocked              # no progress for WALK_STUCK_TIME seconds; scripted walk cancelled

const MODELS := {
	"police": "res://assets/models/characters/officer_police.glb",
	"sheriff": "res://assets/models/characters/officer_sheriff.glb",
}

# Speeds (m/s). RUN = 15 ft/s from the FOOT CHASE distance series. The others are estimates.
const RUN_SPEED := 4.57
const WALK_SPEED := 1.7          # TODO(tahmin): no walk speed measured; Shift held = walk
const READY_SPEED := 2.4         # TODO(tahmin): walking with a drawn weapon
const AIM_SPEED := 1.7           # TODO(tahmin): moving while aiming
const ACCELERATION := 28.0
const GRAVITY := 20.0
const TURN_RATE := 12.0

# Camera: follow boy ≈360 px, aim boy ≈570 px at 1080p -> aim camera ≈1.58x closer.
const CAMERA_FOV := 65.0
const FOLLOW_DISTANCE := 4.2
const AIM_DISTANCE := FOLLOW_DISTANCE / 1.58
const FOLLOW_SHOULDER := 0.60    # camera sits right of the head (player appears left of centre)
const AIM_SHOULDER := 0.42
const PIVOT_HEIGHT := 1.65
const DEFAULT_PITCH := -0.12
# weapon -> [aim-in seconds, aim-out seconds]; pistol 2,617->3,0 s / 10,783->11,0 s; rifle 19,983->20,267 / 21,75->21,917; shotgun estimated
const AIM_TIMES := {
	&"pistol": [0.38, 0.22], &"taser": [0.38, 0.22], &"rifle": [0.285, 0.167], &"shotgun": [0.30, 0.20],
}
# weapon -> [camera kick (deg, look up), recovery seconds]; -26/-21/-23 px at 65° over 1080 px
const RECOIL := {
	&"pistol": [1.56, 0.20], &"taser": [1.56, 0.20], &"rifle": [1.26, 0.10], &"shotgun": [1.38, 0.13],
}
const WALK_ARRIVE_DISTANCE := 0.3
const WALK_STUCK_TIME := 2.0
const WALK_STUCK_PROGRESS := 0.4     # metres the body must move within WALK_STUCK_TIME (detours count as progress)
const RELOAD_HOLD := 0.5         # TODO(tahmin): "hold R reload" hold time

@export var model_kind: String = "police"
@export var capture_mouse: bool = true
@export var make_camera_current: bool = true
@export var auto_visuals: bool = true
@export var mouse_sensitivity: float = 0.0025
@export var input_enabled: bool = true
## Run speed with a drawn weapon (not aiming). The officer runs with the pistol out at ≈4.5 m/s.
## Set to READY_SPEED (2.4) for a slower "tactical" walk.
@export var armed_run_speed: float = 4.5

var rig: CharacterRig
var camera: Camera3D
var yaw: float = 0.0
var pitch: float = DEFAULT_PITCH

var _pivot: Node3D
var _arm: SpringArm3D
var _aim_blend: float = 0.0
var _aiming: bool = false
var _recoil: float = 0.0
var _recoil_rate: float = 0.0
var _reload_held: float = -1.0
var _selected_weapon: StringName = &"pistol"
var _force_aim: bool = false
var _hold_camera: bool = false
var _cam_weapon: StringName = &"pistol"
var _forced_input: Vector2 = Vector2.ZERO     # camera-relative scripted move input (x right, y back like WASD)
var _forced_run: bool = true
var _walk_target: Vector3 = Vector3.ZERO
var _walking_to: bool = false
var _walk_path: Array[Vector3] = []
var _arrive_radius: float = WALK_ARRIVE_DISTANCE
var _walk_anchor: Vector3 = Vector3.INF
var _walk_stuck: float = 0.0
var _walk_time: float = 0.0
var _walk_budget: float = 0.0
## weapon id -> [camera kick degrees (look up), recovery seconds]; edit with set_recoil()
var recoil_table: Dictionary = RECOIL.duplicate(true)


func _ready() -> void:
	collision_layer = 1 << 1
	floor_snap_length = StepUp.STEP_HEIGHT + 0.1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	rig = CharacterRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.setup(MODELS.get(model_kind, MODELS["police"]))
	rig.weapon_state_changed.connect(func(state: StringName) -> void: weapon_state_changed.emit(state))

	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	_pivot.top_level = true
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.spring_length = FOLLOW_DISTANCE
	_arm.margin = 0.12
	_arm.add_excluded_object(get_rid())
	_arm.position.x = FOLLOW_SHOULDER
	_pivot.add_child(_arm)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = CAMERA_FOV
	camera.near = 0.05
	_arm.add_child(camera)
	if make_camera_current:
		camera.make_current()
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_camera(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= motion.relative.x * mouse_sensitivity
		pitch = clampf(pitch - motion.relative.y * mouse_sensitivity, -1.2, 1.0)
	elif event.is_action_pressed("close_menu"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("fire") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if rig.weapon_state == &"ready" or rig.weapon_state == &"aiming":
			fire_requested.emit()
			if auto_visuals:
				notify_shot()
	elif event.is_action_pressed("draw_weapon"):
		draw_requested.emit()
		if auto_visuals:
			if rig.is_armed():
				holster_weapon()
			else:
				draw_weapon(_selected_weapon)
	elif event.is_action_pressed("reload"):
		_reload_held = 0.0
	elif event.is_action_released("reload"):
		_reload_held = -1.0


func _physics_process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	var scripted := _walking_to or _forced_input != Vector2.ZERO
	if scripted:
		input_dir = _forced_input
	elif input_enabled and not rig.is_full_active():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var state := rig.weapon_state
	var strafing := state in [&"raising", &"aiming", &"lowering"] or (_aiming and state == &"reloading")
	var walk_modifier := (scripted and not _forced_run) or (not scripted and Input.is_key_pressed(KEY_SHIFT))
	var speed := RUN_SPEED
	if strafing:
		speed = AIM_SPEED
	elif walk_modifier:
		speed = READY_SPEED if rig.is_armed() else WALK_SPEED
	elif rig.is_armed():
		speed = armed_run_speed
	var wish := Basis(Vector3.UP, yaw) * Vector3(input_dir.x, 0.0, input_dir.y)
	if _walking_to:
		var to_target := _walk_target - global_position
		to_target.y = 0.0
		var radius := _arrive_radius if _walk_path.is_empty() else maxf(_arrive_radius, 0.6)
		if to_target.length() <= radius:
			wish = Vector3.ZERO
			if _walk_path.is_empty():
				_walking_to = false
				arrived.emit()
			else:
				_walk_target = _walk_path.pop_front()
				_walk_anchor = Vector3.INF
				_walk_stuck = 0.0
				_reset_walk_budget()
		else:
			_walk_time += delta
			if _walk_time > _walk_budget:
				_walk_stuck = WALK_STUCK_TIME
			wish = StepUp.steer(self, to_target.normalized())
			if _walk_anchor == Vector3.INF or global_position.distance_to(_walk_anchor) > WALK_STUCK_PROGRESS:
				_walk_anchor = global_position
				_walk_stuck = 0.0
			else:
				_walk_stuck += delta
				if _walk_stuck >= WALK_STUCK_TIME:
					_walking_to = false
					_walk_path.clear()
					wish = Vector3.ZERO
					walk_blocked.emit()
	var target := wish * speed
	velocity.x = move_toward(velocity.x, target.x, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCELERATION * delta)
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	StepUp.step_up(self, delta)
	move_and_slide()

	var face_camera := strafing or _aiming
	if face_camera:
		rotation.y = lerp_angle(rotation.y, yaw, minf(TURN_RATE * delta, 1.0))
	elif wish.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-wish.x, -wish.z), minf(TURN_RATE * delta, 1.0))
	var local_velocity := global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	rig.set_motion(local_velocity, face_camera)


func _process(delta: float) -> void:
	_update_aim(delta)
	if _reload_held >= 0.0:
		_reload_held += delta
		if _reload_held >= RELOAD_HOLD:
			_reload_held = -1.0
			reload_requested.emit()
			if auto_visuals:
				rig.reload()
	if _recoil > 0.0:
		_recoil = maxf(_recoil - _recoil_rate * delta, 0.0)
	rig.set_aim_pitch(pitch + _recoil)
	_update_camera(delta)


func _update_aim(delta: float) -> void:
	var weapon := rig.weapon
	var want := (_force_aim or (input_enabled and Input.is_action_pressed("aim"))) and rig.is_armed() and weapon != &""
	var state := rig.weapon_state
	if want and state == &"ready":
		rig.set_aiming(true)
	elif not want and (state == &"aiming" or state == &"raising"):
		rig.set_aiming(false)
	var now_aiming := want and rig.weapon_state in [&"raising", &"aiming", &"reloading"]
	if now_aiming != _aiming:
		_aiming = now_aiming
		aim_changed.emit(_aiming)
	if weapon != &"":
		_cam_weapon = weapon
	var camera_on := _aiming or _hold_camera
	var times: Array = AIM_TIMES.get(_cam_weapon, [0.3, 0.2])
	var duration: float = times[0] if camera_on else times[1]
	var step := delta / maxf(duration, 0.001)
	_aim_blend = move_toward(_aim_blend, 1.0 if camera_on else 0.0, step)   # linear: constant-rate transitions


func _update_camera(_delta: float) -> void:
	_pivot.global_position = global_position + Vector3(0.0, PIVOT_HEIGHT, 0.0)
	_pivot.rotation = Vector3(pitch + _recoil, yaw, 0.0)
	_arm.spring_length = lerpf(FOLLOW_DISTANCE, AIM_DISTANCE, _aim_blend)
	_arm.position.x = lerpf(FOLLOW_SHOULDER, AIM_SHOULDER, _aim_blend)


# --- API for the Weapons module ---------------------------------------------------------------------------------
func set_loadout(ids: Array) -> void:
	rig.set_loadout(ids)
	if not ids.is_empty():
		_selected_weapon = StringName(ids[0])


func select_weapon(id: StringName) -> void:
	_selected_weapon = id


func draw_weapon(id: StringName = &"") -> bool:
	if id != &"":
		_selected_weapon = id
	return rig.draw(_selected_weapon)


func holster_weapon() -> bool:
	return rig.holster()


## Call when a shot actually leaves the weapon: recoil animation + camera kick.
func notify_shot() -> void:
	if not rig.fire():
		return
	var info: Array = recoil_table.get(rig.weapon, [1.4, 0.15])
	_recoil = deg_to_rad(float(info[0]))
	_recoil_rate = _recoil / maxf(float(info[1]), 0.01)
	if rig.weapon == &"shotgun":
		get_tree().create_timer(0.35).timeout.connect(func() -> void: rig.pump())


func is_aiming() -> bool:
	return _aiming


func weapon_state() -> StringName:
	return rig.weapon_state


## World-space ray through the crosshair (screen centre): {origin, direction}.
func get_aim_ray() -> Dictionary:
	return {"origin": camera.global_position, "direction": -camera.global_transform.basis.z}


func muzzle_transform() -> Transform3D:
	return rig.muzzle_transform()


func play_action(anim_name: StringName) -> float:
	return rig.play_full(anim_name)


func release_action() -> void:
	rig.release_full()


# --- scripted control (scenarios) -----------------------------------------------------------------------------------
## Enters / leaves the aim stance and camera without RMB (OR-ed with the real RMB while input_enabled).
func force_aim(on: bool) -> void:
	_force_aim = on


## Keeps the aim camera (zoom + shoulder offset) open although the aim stance ended: the arm lowers at 10.1 s
## but the camera only pulls back at 10.78-11.0 s. hold_aim_camera(false) starts the pull-back (0.22 s pistol, linear).
func hold_aim_camera(on: bool) -> void:
	_hold_camera = on


## Scripted WASD-style input relative to the camera yaw: direction.x right, direction.y back (so forward = Vector2(0, -1)).
## run = true uses the run gait (RUN_SPEED), false the walk gait. Vector2.ZERO stops.
func force_move(direction: Vector2, run: bool = true) -> void:
	_walking_to = false
	_forced_input = direction.limit_length(1.0)
	_forced_run = run


## Walks (or runs) to a world position, then emits `arrived`. The body turns toward the target.
## arrive_radius: distance (m) at which the target counts as reached. Low obstacles (curbs up to StepUp.STEP_HEIGHT) are
## climbed, taller ones are steered around; `walk_blocked` fires when the body moves less than 0.4 m in 2 s.
func walk_to(world_position: Vector3, run: bool = false, arrive_radius: float = WALK_ARRIVE_DISTANCE) -> void:
	_walk_path.clear()
	_walk_target = world_position
	_arrive_radius = arrive_radius
	_walk_anchor = Vector3.INF
	_walk_stuck = 0.0
	_reset_walk_budget()
	_walking_to = true
	_forced_input = Vector2.ZERO
	_forced_run = run


func _reset_walk_budget() -> void:
	_walk_time = 0.0
	var flat := _walk_target - global_position
	flat.y = 0.0
	_walk_budget = flat.length() / WALK_SPEED * 2.0 + 5.0   # generous: detours around cars still fit


## Waypoint walk (e.g. around a vehicle to its door): `arrived` fires at the last point (intermediate points use >= 0.6 m).
func walk_path(points: Array, run: bool = false, arrive_radius: float = WALK_ARRIVE_DISTANCE) -> void:
	if points.is_empty():
		return
	var rest: Array[Vector3] = []
	for point: Vector3 in points:
		rest.append(point)
	var first: Vector3 = rest.pop_front()
	walk_to(first, run, arrive_radius)
	_walk_path = rest


func stop_scripted() -> void:
	_walking_to = false
	_walk_path.clear()
	_forced_input = Vector2.ZERO


## Sets the camera look (radians). pitch > 0 looks up.
func force_look(new_yaw: float, new_pitch: float) -> void:
	yaw = new_yaw
	pitch = clampf(new_pitch, -1.2, 1.0)


## Replaces the camera kick of one weapon id: degrees (look up) and recovery seconds. Used by Weapons.officer_recoil.
func set_recoil(weapon_id: StringName, kick_degrees: float, recover_seconds: float) -> void:
	recoil_table[weapon_id] = [kick_degrees, recover_seconds]


func reset_recoil() -> void:
	recoil_table = RECOIL.duplicate(true)
