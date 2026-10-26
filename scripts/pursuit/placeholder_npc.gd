extends Node3D
## Capsule stand-in for the real Npc (same command names: walk_to, flee_from, stop, go_down, cuff, surrender).
## Used only when scripts/characters/npc.gd is unavailable.

signal state_changed(state: StringName)
signal arrived

const FLEE_SPEED := 4.57
const WALK_SPEED := 1.4

var kind := "civilian"
var state: StringName = &"idle"
var _target := Vector3.ZERO
var _has_target := false
var _speed := WALK_SPEED
var _body: Node3D


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var col := Color("8a2f3c")
	if kind == "sheriff":
		col = Color("b9a77d")
	elif kind == "police":
		col = Color("1f2a44")
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.45
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	cap.material = mat
	mi.mesh = cap
	mi.position.y = 0.85
	_body.add_child(mi)
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.15
	sph.height = 0.3
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color("d9b08c")
	sph.material = hm
	head.mesh = sph
	head.position.y = 1.72
	_body.add_child(head)


func _set_state(value: StringName) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(state)


func walk_to(target: Vector3, speed: float = WALK_SPEED) -> void:
	if state in [&"downed", &"cuffed"]:
		return
	_target = target
	_has_target = true
	_speed = speed
	_set_state(&"walk")


func flee_from(source: Vector3, distance: float = 40.0) -> void:
	if state in [&"downed", &"cuffed"]:
		return
	var away := global_position - source
	away.y = 0.0
	if away.length() < 0.1:
		away = -global_transform.basis.z
	_target = global_position + away.normalized() * distance
	_has_target = true
	_speed = FLEE_SPEED
	_set_state(&"flee")


func stop() -> void:
	_has_target = false
	if state == &"walk" or state == &"flee":
		_set_state(&"idle")


func surrender() -> void:
	_has_target = false
	_set_state(&"surrender")


func go_down(_kind: StringName = &"shot") -> void:
	_has_target = false
	_body.rotation_degrees.x = -88.0
	_body.position.y = 0.3
	_set_state(&"downed")


func cuff() -> void:
	_has_target = false
	if state != &"downed":
		_body.rotation_degrees.x = -88.0
		_body.position.y = 0.3
	_set_state(&"cuffed")


func _physics_process(dt: float) -> void:
	if not _has_target or not state in [&"walk", &"flee"]:
		return
	var to_t := _target - global_position
	to_t.y = 0.0
	if to_t.length() < 0.35:
		_has_target = false
		_set_state(&"idle")
		arrived.emit()
		return
	var dir := to_t.normalized()
	global_position += dir * _speed * dt
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(10.0 * dt, 1.0))
