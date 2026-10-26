extends Node3D
## Dev stand-in for the Officer: walks with WASD when on foot, "enters" and "exits" the patrol car.
## Implements the hooks Adapters looks for: in_vehicle, exit_vehicle(), enter_vehicle(v), set_flashlight(on).

var in_vehicle := true
var vehicle: Node3D
var flashlight_on := false
var walk_speed := 3.5
var _body: MeshInstance3D


func _ready() -> void:
	add_to_group("player")
	_body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 1.8
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("A8946A")
	capsule.material = material
	_body.mesh = capsule
	_body.position.y = 0.9
	add_child(_body)
	visible = false


func _physics_process(delta: float) -> void:
	if in_vehicle:
		if vehicle != null:
			global_position = vehicle.global_position
		return
	var dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	global_position += Vector3(dir.x, 0.0, dir.y) * walk_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("exit_vehicle") and in_vehicle and vehicle != null and vehicle.call("speed_mph") < 2.0:
		exit_vehicle()


func exit_vehicle() -> void:
	if not in_vehicle or vehicle == null:
		return
	in_vehicle = false
	visible = true
	global_position = (vehicle.call("enter_transform", &"driver") as Transform3D).origin


func enter_vehicle(target: Node3D) -> void:
	vehicle = target
	in_vehicle = true
	visible = false


func is_in_vehicle() -> bool:
	return in_vehicle


func set_flashlight(on: bool) -> void:
	flashlight_on = on
