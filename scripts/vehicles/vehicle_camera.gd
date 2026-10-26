class_name VehicleCamera
extends Node3D
## Third-person chase camera for a Vehicle: behind and above, constant distance,
## yaw lags the heading (so turns show the car slightly from the side), and it orbits to the front/side quarter
## when the vehicle is almost stopped. Add it to the scene, then call follow(vehicle).

@export var distance := 6.3           # metres between the camera and the car's rear bumper
@export var height := 2.9
@export var look_height := 1.5
@export var fov := 58.0               # vertical field of view in degrees
@export var yaw_follow := 3.2         # 1/s, larger = tighter
@export var drift_blend := 0.35       # how much the velocity direction pulls the camera at speed
@export var still_orbit_deg := 150.0  # orbit angle used when the vehicle stands still
@export var still_delay := 1.4        # seconds of standstill before the orbit starts

## Named presets: &"pursuit" is the default (pursuit, directly behind); &"chase_offset" is a wide
## camera: further back, higher and about 30 degrees to the right of the car.
const PRESETS := {
	&"pursuit": {"distance": 5.0, "height": 3.5, "look_height": 1.2, "look_yaw": 0.0},
	&"traffic_stop": {"distance": 5.4, "height": 3.8, "look_height": 1.5, "look_yaw": 0.0},
	&"chase_offset": {"distance": 8.0, "height": 4.2, "look_height": 1.5, "look_yaw": 0.55},
}

var target: Vehicle
var camera: Camera3D
var hold_look_yaw := false             # true: apply_preset keeps look_yaw and the standstill orbit is off
var look_yaw := 0.0                   # extra yaw (radians) a player can add with the mouse
var _yaw := 0.0
var _orbit := 0.0
var _still := 0.0


func _ready() -> void:
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera"
		add_child(camera)
	camera.fov = fov
	camera.far = 1500.0


func apply_preset(preset_name: StringName) -> void:
	var p: Dictionary = PRESETS.get(preset_name, PRESETS[&"pursuit"])
	distance = p["distance"]
	height = p["height"]
	look_height = p["look_height"]
	if not hold_look_yaw:
		look_yaw = p["look_yaw"]


func follow(v: Vehicle, snap_now := true) -> void:
	target = v
	if snap_now:
		snap()


func make_current() -> void:
	camera.current = true


func snap() -> void:
	if target == null:
		return
	var f := -target.global_transform.basis.z
	_yaw = atan2(f.x, f.z)
	_orbit = 0.0
	_still = 0.0
	_place()


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var f := -target.global_transform.basis.z
	var desired := atan2(f.x, f.z)
	var v := target.linear_velocity
	v.y = 0.0
	var speed := v.length()
	if speed > 8.0 and target.forward_speed_ms() > 0.0:
		desired = lerp_angle(desired, atan2(v.x, v.z), drift_blend * clampf((speed - 8.0) / 10.0, 0.0, 1.0))
	_yaw = lerp_angle(_yaw, desired, 1.0 - exp(-yaw_follow * delta))
	if speed < 0.8:
		_still += delta
	else:
		_still = 0.0
	if _still > still_delay and not hold_look_yaw:
		_orbit = move_toward(_orbit, deg_to_rad(still_orbit_deg), 1.1 * delta)
	elif speed > 2.0:
		_orbit = move_toward(_orbit, 0.0, 3.0 * delta)
	_place()


func _place() -> void:
	var yaw := _yaw + _orbit + look_yaw
	var dir := Vector3(sin(yaw), 0.0, cos(yaw))
	var base := target.global_position
	global_position = base - dir * (distance + target.rear_extent) + Vector3(0.0, height, 0.0)
	var focus := base + Vector3(0.0, look_height, 0.0)
	look_at(focus, Vector3.UP)
	camera.fov = fov
