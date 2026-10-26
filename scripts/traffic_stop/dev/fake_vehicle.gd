extends Node3D
## Dev stand-in for the Vehicle class (docs/api/vehicles.md): box body, kinematic motion and the same control API
## (set_controls, set_throttle, set_steer: -1 left .. +1 right, set_brake_pedal), speed_mph(), seat_transform(),
## enter_transform(), open_driver_door(), set_handbrake(). With ai_enabled the car cruises at cruise_mph by itself.

var plate: String = "KEA-9291"
var display_name: String = "Halvorsen Ranger SUV"
var type_id: StringName = &"fake"
var is_police := false
var driver: Node = null
var body_color := Color("5C7A66")
var ai_enabled := false
var cruise_mph := 15.0
var speed := 0.0  # m/s
var throttle_in := 0.0
var steer_in := 0.0
var brake_in := 0.0
var handbrake := false
var headlights_on := false
var door_open := false


func _ready() -> void:
	add_to_group("vehicles")
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.9, 1.3, 4.6)
	var material := StandardMaterial3D.new()
	material.albedo_color = body_color
	box.material = material
	body.mesh = box
	body.position.y = 0.85
	add_child(body)
	var cabin := MeshInstance3D.new()
	var cabin_box := BoxMesh.new()
	cabin_box.size = Vector3(1.7, 0.6, 2.2)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = body_color.darkened(0.5)
	cabin_box.material = glass
	cabin.mesh = cabin_box
	cabin.position = Vector3(0.0, 1.8, 0.2)
	add_child(cabin)


func _physics_process(delta: float) -> void:
	if ai_enabled:
		var wanted := cruise_mph * 0.44704
		throttle_in = clampf((wanted - speed) * 0.4, 0.0, 0.6)
		brake_in = clampf((speed - wanted) * 0.4, 0.0, 1.0)
		steer_in = 0.0
	if handbrake:
		brake_in = 1.0
		throttle_in = 0.0
	speed = maxf(speed + (throttle_in * 4.0 - brake_in * 9.0 - 0.15) * delta, 0.0)
	if speed < 0.02 and brake_in > 0.5:
		speed = 0.0
	rotate_y(-steer_in * minf(speed, 8.0) * 0.12 * delta)
	global_position += -global_transform.basis.z * speed * delta


func set_controls(throttle: float, steer: float, brake: float) -> void:
	throttle_in = throttle
	steer_in = steer
	brake_in = brake


func set_throttle(value: float) -> void:
	throttle_in = value


func set_steer(value: float) -> void:
	steer_in = value


func set_brake_pedal(value: float) -> void:
	brake_in = value


func set_handbrake(on: bool) -> void:
	handbrake = on


func speed_mph() -> float:
	return speed / 0.44704


func speed_ms() -> float:
	return speed


func set_headlights(on: bool) -> void:
	headlights_on = on


func set_driver(node: Node) -> void:
	driver = node


func open_driver_door() -> void:
	door_open = true


func close_driver_door() -> void:
	door_open = false


func seat_transform(_seat: StringName) -> Transform3D:
	return Transform3D(global_transform.basis, global_transform * Vector3(-0.4, 0.4, 0.1))


## Ground point beside the driver door.
func enter_transform(_seat: StringName) -> Transform3D:
	return Transform3D(global_transform.basis, global_transform * Vector3(-1.6, 0.0, -0.4))
