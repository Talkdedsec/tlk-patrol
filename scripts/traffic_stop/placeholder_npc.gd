extends Node3D
## Stand-in for the characters module's Npc (capsule body). Used by Adapters.spawn_driver() when
## res://scenes/characters/npc.tscn is missing. Implements the hooks the stop flow calls:
## sit(driver), stand_up(), walk_to(pos, speed), talk(anim), set_state().

signal arrived

var state: StringName = &"idle"
var outfit: StringName = &""
var body_color := Color("D8D4CC")
var _walk: Tween


func _ready() -> void:
	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 1.75
	var material := StandardMaterial3D.new()
	material.albedo_color = body_color
	capsule.material = material
	mesh_instance.mesh = capsule
	mesh_instance.position.y = 0.88
	add_child(mesh_instance)
	add_to_group("npc")


func set_state(new_state: StringName) -> void:
	state = new_state


func sit(_driver: bool) -> void:
	state = &"seated"


func stand_up() -> void:
	state = &"idle"


func talk(_animation: StringName = &"talk_a") -> void:
	state = &"talk"


func walk_to(target: Vector3, speed: float = 1.6) -> void:
	if _walk != null and _walk.is_valid():
		_walk.kill()
	state = &"walk"
	var seconds := maxf(global_position.distance_to(target) / speed, 0.05)
	_walk = create_tween()
	_walk.tween_property(self, "global_position", target, seconds)
	_walk.tween_callback(func() -> void:
		state = &"idle"
		arrived.emit())
