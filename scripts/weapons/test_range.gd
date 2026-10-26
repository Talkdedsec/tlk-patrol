extends Node3D
## Weapon test range: ground, backstop, cover blocks, placeholder capsule targets at 8-40 m, the HUD and a test officer.
## WASD move, mouse look, LMB fire, RMB aim, 5 draw/holster, wheel switch weapon, hold R reload, F4 HUD debug line.
## Open with: araclar/godot.sh res://scenes/weapons/test_range.tscn

const TestOfficer := preload("res://scripts/weapons/test_officer.gd")
const TestDummy := preload("res://scripts/weapons/test_dummy.gd")
const HUD_PATH := "res://scripts/hud/hud.gd"
const TARGETS := [Vector3(0.45, 0.0, -8.0), Vector3(-3.0, 0.0, -14.0), Vector3(4.0, 0.0, -20.0),
		Vector3(0.45, 0.0, -27.0), Vector3(-5.0, 0.0, -34.0), Vector3(2.0, 0.0, -40.0)]

var officer: CharacterBody3D
var targets: Array[Node3D] = []


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_targets()
	officer = TestOfficer.new()
	officer.name = "Officer"
	add_child(officer)
	if ResourceLoader.exists(HUD_PATH):
		var hud_script := load(HUD_PATH) as GDScript
		if hud_script != null:
			var hud: Node = hud_script.new()
			hud.name = "Hud"
			add_child(hud)
	Weapons.bind_officer(officer)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("8FA3B8")
	sky_material.sky_horizon_color = Color("B9C4CF")
	sky_material.ground_horizon_color = Color("B9C4CF")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	collision.shape = box
	collision.position.y = -0.5
	ground.add_child(collision)
	var plane := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(200.0, 200.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("6C7078")
	plane_mesh.material = material
	plane.mesh = plane_mesh
	ground.add_child(plane)
	add_child(ground)
	_add_block("Backstop", Vector3(40.0, 6.0, 1.0), Vector3(0.0, 3.0, -60.0), Color("8A7A66"))
	_add_block("CoverLow", Vector3(2.5, 1.1, 0.6), Vector3(-2.0, 0.55, -4.0), Color("5E6672"))
	_add_block("CoverHigh", Vector3(1.0, 2.2, 3.0), Vector3(6.0, 1.1, -12.0), Color("5E6672"))


func _add_block(block_name: String, size: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = block_name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	body.position = at
	add_child(body)


func _build_targets() -> void:
	for i in TARGETS.size():
		var dummy := TestDummy.new()
		dummy.name = "Target%d" % (i + 1)
		dummy.position = TARGETS[i]
		add_child(dummy)
		targets.append(dummy)
