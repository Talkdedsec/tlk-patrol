extends Node3D
## Dev viewer: shows one vehicle glb (or several with --model a,b,c) from an orbit camera.
## Args (after --): --model name[,name] --yaw 35 --pitch 15 --dist 7 --night 0|1 --paint #rrggbb --cells 0|1

const MODEL_DIR := "res://assets/models/vehicles/"


func _ready() -> void:
	var args := _args()
	var night := String(args.get("night", "0")) == "1"
	_environment(night)
	var names: PackedStringArray = String(args.get("model", "patrol_sedan")).split(",")
	var x := 0.0
	for n in names:
		var scene := load(MODEL_DIR + n + ".glb") as PackedScene
		if scene == null:
			push_error("missing model " + n)
			continue
		var inst := scene.instantiate() as Node3D
		inst.position.x = x
		add_child(inst)
		x += 6.0
		if args.has("paint"):
			_paint(inst, Color(String(args["paint"])))
		if String(args.get("cells", "0")) == "1":
			_cells(inst)
	var cam := Camera3D.new()
	cam.fov = float(args.get("fov", "40"))
	add_child(cam)
	var yaw := deg_to_rad(float(args.get("yaw", "35")))
	var pitch := deg_to_rad(float(args.get("pitch", "15")))
	var dist := float(args.get("dist", "8"))
	var target := Vector3((x - 6.0) * 0.5, 0.8, 0.0)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.look_at(target)
	cam.current = true


func _paint(root: Node, color: Color) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			if mat != null and mat.resource_name == "Paint":
				var c := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				c.albedo_color = color
				m.set_surface_override_material(s, c)


func _cells(root: Node) -> void:
	for mi in root.find_children("ELS_CELL_*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var idx := int(m.name.get_slice("_", 2))
		var c := Color(1, 0.05, 0.05) if (idx % 10) < 5 else Color(0.1, 0.3, 1.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c * 0.4
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 3.0
		m.material_override = mat


func _environment(night: bool) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	if night:
		sky_material.sky_top_color = Color("05070d")
		sky_material.sky_horizon_color = Color("141a26")
		sky_material.ground_horizon_color = Color("141a26")
		env.ambient_light_energy = 0.4
	else:
		sky_material.sky_top_color = Color("8FA3B8")
		sky_material.sky_horizon_color = Color("B9C4CF")
		sky_material.ground_horizon_color = Color("B9C4CF")
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	sun.light_energy = 0.15 if night else 1.0
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("3b3d42")
	ground.material_override = gm
	add_child(ground)


func _args() -> Dictionary:
	var d := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i] == "--":
			i += 1
		elif a[i].begins_with("--") and i + 1 < a.size():
			d[a[i].substr(2)] = a[i + 1]
			i += 2
		else:
			i += 1
	return d
