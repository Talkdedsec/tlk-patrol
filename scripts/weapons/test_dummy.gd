extends StaticBody3D
## Placeholder capsule target for the test range. Mimics the NPC hooks Weapons looks for: group "npc",
## apply_weapon_hit(info), is_downed(). Falls forward over about 0.6 s when its health runs out
## (stagger 70 ms, kneel 130-200 ms, fall 200 ms).

signal downed_changed

@export var height := 1.75
@export var radius := 0.3
@export var max_hp := 100.0

var hp := 100.0
var hits := 0
var downed := false
var last_part := ""
var _body: MeshInstance3D
var _material: StandardMaterial3D
var _base_color := Color("C8641E")
var _fall_axis := Vector3.RIGHT
var _fall_start := Basis.IDENTITY


func _ready() -> void:
	add_to_group("npc")
	hp = max_hp
	var shape := CollisionShape3D.new()
	shape.name = "Hitbox"
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	shape.shape = capsule
	shape.position.y = height * 0.5
	add_child(shape)
	_body = MeshInstance3D.new()
	_body.name = "Body"
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color
	mesh.material = _material
	_body.mesh = mesh
	_body.position.y = height * 0.5
	add_child(_body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.32
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("E0B48C")
	sphere.material = skin
	head.mesh = sphere
	head.position.y = height - 0.1
	add_child(head)


func is_downed() -> bool:
	return downed


func apply_weapon_hit(info: Dictionary) -> Dictionary:
	var just_downed := false
	if not downed:
		hits += 1
		hp = maxf(hp - float(info["damage"]), 0.0)
		last_part = String(info["part"])
		just_downed = hp <= 0.0
		_flash(just_downed)
		if just_downed:
			downed = true
			_fall(info.get("dir", Vector3.FORWARD))
			downed_changed.emit()
	return {"downed": just_downed, "lethal": just_downed, "hp": hp}


func _flash(lethal: bool) -> void:
	_material.albedo_color = Color.WHITE
	var tween := create_tween()
	tween.tween_property(_material, "albedo_color", Color("5A5060") if lethal else _base_color, 0.15)


func _fall(shot_dir: Vector3) -> void:
	var flat := Vector3(shot_dir.x, 0.0, shot_dir.z)
	_fall_axis = Vector3.RIGHT
	if flat.length() > 0.01:
		_fall_axis = flat.normalized().cross(Vector3.UP)     # tip over away from the shooter
	_fall_start = transform.basis
	var tween := create_tween()
	tween.tween_method(_set_fall_angle, 0.0, PI * 0.5, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _set_fall_angle(angle: float) -> void:
	transform.basis = Basis(_fall_axis, -angle) * _fall_start
