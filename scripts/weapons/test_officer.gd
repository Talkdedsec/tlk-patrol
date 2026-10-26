extends CharacterBody3D
## Minimal third-person officer used only by the weapon test range. It implements the contract Weapons expects from
## the real Officer: signals fire_requested / aim_changed / draw_requested / reload_requested, get_muzzle_transform(),
## set_camera_kick(), and an over-the-shoulder camera whose distance shrinks by 1.6x while aiming.

signal fire_requested
signal aim_changed(aiming: bool)
signal draw_requested
signal reload_requested
signal weapon_cycle_requested(direction: int)

const RUN_SPEED := 5.0
const SENSITIVITY := 0.0025
const FOLLOW_DISTANCE := 3.2        # tuned follow camera 3-4.5 m
const AIM_RATIO := 1.6              # tuned aim camera is 1.55-1.6x closer
const RELOAD_HOLD := 0.4
const SHOULDER := Vector3(0.45, 0.2, 0.0)

var camera: Camera3D
var kick_pitch := 0.0
var kick_yaw := 0.0
var _yaw := 0.0
var _pitch := -0.05
var _aim_t := 0.0
var _aiming := false
var _pivot: Node3D
var _visual: Node3D
var _muzzle: Marker3D
var _reload_held := 0.0
var _reload_sent := false
var _turn_accum := 0.0


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	_visual = Node3D.new()
	add_child(_visual)
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.3
	mesh.height = 1.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("1F2A44")
	mesh.material = material
	body.mesh = mesh
	body.position.y = 0.9
	_visual.add_child(body)
	var gun := MeshInstance3D.new()
	var gun_mesh := BoxMesh.new()
	gun_mesh.size = Vector3(0.06, 0.1, 0.35)
	gun.mesh = gun_mesh
	gun.position = Vector3(0.28, 1.3, -0.45)
	_visual.add_child(gun)
	_muzzle = Marker3D.new()
	_muzzle.name = "Muzzle"
	_muzzle.position = Vector3(0.28, 1.3, -0.65)
	_visual.add_child(_muzzle)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0.0, 1.6, 0.0)
	add_child(_pivot)
	camera = Camera3D.new()
	camera.fov = 70.0
	_pivot.add_child(camera)
	camera.make_current()
	_apply_look()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_aim_camera() -> Camera3D:
	return camera


func get_muzzle_transform() -> Transform3D:
	return _muzzle.global_transform


func get_collision_rids() -> Array[RID]:
	return [get_rid()]


## Camera kick offset in radians; Weapons passes the recovering value every frame.
func set_camera_kick(pitch: float, yaw: float) -> void:
	kick_pitch = pitch
	kick_yaw = yaw
	_apply_look()


## Points the camera so its centre ray passes through `point` (used by tests and scenario setup).
func look_at_point(point: Vector3) -> void:
	for i in 6:
		var cam_pos := _pivot.global_transform * (SHOULDER + Vector3(0.0, 0.0, _distance()))
		var dir := (point - cam_pos).normalized()
		_yaw = atan2(-dir.x, -dir.z)
		_pitch = asin(dir.y)
		_apply_look()
		_pivot.force_update_transform()


func _distance() -> float:
	return lerpf(FOLLOW_DISTANCE, FOLLOW_DISTANCE / AIM_RATIO, _aim_t)


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= motion.relative.x * SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * SENSITIVITY, -1.2, 0.8)
		_turn_accum += absf(motion.relative.x) * SENSITIVITY
		_apply_look()
	elif event.is_action_pressed("close_menu"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				else Input.MOUSE_MODE_CAPTURED
	elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	elif event.is_action_pressed("fire"):
		fire_requested.emit()
	elif event.is_action_pressed("aim"):
		_aiming = true
		aim_changed.emit(true)
	elif event.is_action_released("aim"):
		_aiming = false
		aim_changed.emit(false)
	elif event.is_action_pressed("draw_weapon"):
		draw_requested.emit()
	elif event.is_action_pressed("weapon_next"):
		weapon_cycle_requested.emit(1)
	elif event.is_action_pressed("weapon_prev"):
		weapon_cycle_requested.emit(-1)


func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Basis(Vector3.UP, _yaw) * Vector3(input_dir.x, 0.0, input_dir.y)
	velocity.x = wish.x * RUN_SPEED
	velocity.z = wish.z * RUN_SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	if _aiming or wish.length() > 0.1:
		_visual.rotation.y = lerp_angle(_visual.rotation.y, _yaw if _aiming else atan2(-wish.x, -wish.z), 12.0 * delta)
	var turn_rate := rad_to_deg(_turn_accum) / maxf(delta, 0.001)
	_turn_accum = 0.0
	Weapons.set_movement(Vector2(velocity.x, velocity.z).length(), turn_rate)


func _process(delta: float) -> void:
	_aim_t = move_toward(_aim_t, 1.0 if _aiming else 0.0, delta / 0.2)
	_apply_look()
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("reload"):
		_reload_held += delta
		if _reload_held >= RELOAD_HOLD and not _reload_sent:
			_reload_sent = true
			reload_requested.emit()
	else:
		_reload_held = 0.0
		_reload_sent = false


func _apply_look() -> void:
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	camera.position = SHOULDER + Vector3(0.0, 0.0, _distance())
	camera.rotation = Vector3(kick_pitch, kick_yaw, 0.0)
