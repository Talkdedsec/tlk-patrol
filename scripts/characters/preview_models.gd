extends Node3D
## Dev preview: lines up the character models for screenshots (front/back/side via --setup args in shot.gd).

const MODELS := [
	"res://assets/models/characters/officer_police.glb",
	"res://assets/models/characters/officer_sheriff.glb",
	"res://assets/models/characters/civilian.glb",
]
var view_yaw := 160.0


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9AA6B2")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("B9C4CF")
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var x := -1.2
	for path: String in MODELS:
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		inst.position.x = x
		add_child(inst)
		x += 1.2
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, -4.2)
	cam.fov = 40
	add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	cam.make_current()
