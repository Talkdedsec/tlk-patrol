extends Node3D
## Placeholder stage for the traffic stop / MDT / calls modules: a straight road, a patrol car (player vehicle), an ambient
## car ahead and a stand-in officer. Args after "--": --auto (run the scripted end-to-end check and quit), --hud (add the HUD).

const FakeVehicle := preload("res://scripts/traffic_stop/dev/fake_vehicle.gd")
const StagePlayer := preload("res://scripts/traffic_stop/dev/stage_player.gd")
const E2E := preload("res://scripts/traffic_stop/dev/e2e.gd")

var patrol: Node3D
var target: Node3D
var player: Node3D
var camera: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_environment()
	_road()
	patrol = FakeVehicle.new()
	patrol.plate = "1ADAM12"
	patrol.display_name = "Patrol pickup"
	patrol.is_police = true
	patrol.body_color = Color("1B1D22")
	patrol.add_to_group("player_vehicle")
	patrol.add_to_group("police")
	add_child(patrol)
	target = FakeVehicle.new()
	target.position = Vector3(0.0, 0.0, -25.0)
	target.ai_enabled = true
	target.cruise_mph = 14.0
	add_child(target)
	player = StagePlayer.new()
	player.vehicle = patrol
	add_child(player)
	camera = Camera3D.new()
	add_child(camera)
	camera.make_current()
	if args.has("--hud"):
		add_child((load("res://scripts/hud/hud.gd") as GDScript).new())
	if args.has("--auto"):
		var test := E2E.new()
		test.stage = self
		add_child(test)


func _process(_delta: float) -> void:
	var focus: Node3D = player if not player.in_vehicle else patrol
	var desired := focus.global_position + Vector3(4.0, 5.5, 10.0)
	camera.global_position = camera.global_position.lerp(desired, 0.1)
	camera.look_at(focus.global_position + Vector3(0.0, 1.0, -8.0))


func _environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0A0C12")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("3A4254")
	environment.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	sun.light_energy = 0.5
	add_child(sun)


func _road() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 400.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("1C2420")
	plane.material = material
	ground.mesh = plane
	ground.position = Vector3(0.0, -0.01, -120.0)
	add_child(ground)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 400.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, -120.0)
	add_child(floor_body)
	var road := MeshInstance3D.new()
	var strip := PlaneMesh.new()
	strip.size = Vector2(9.0, 400.0)
	var asphalt := StandardMaterial3D.new()
	asphalt.albedo_color = Color("34373C")
	strip.material = asphalt
	road.mesh = strip
	road.position = Vector3(1.8, 0.0, -120.0)
	add_child(road)
