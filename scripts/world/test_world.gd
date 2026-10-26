extends Node3D
## Test scene for the world module: builds the city and offers a free-fly camera.
## Keys: WASD move, Shift fast, RMB drag look, F5/F6 time -/+ 1 h, F7 weather toggle, F8 teleport to next spawn,
## F9 toggle the test patrol car lights.

const SPAWN_ORDER := ["hoover_st", "western_ave", "davidson_blvd", "parking_lot", "kiln_rd", "highway", "route_7"]

var camera: Camera3D
var car: Node3D
var yaw := 0.0
var pitch := -0.15
var _spawn_i := 0
var _els_on := false
var _els_lights: Array[OmniLight3D] = []


func _ready() -> void:
	World.build(self)
	camera = Camera3D.new()
	camera.far = 3500.0
	camera.near = 0.1
	camera.fov = 70.0
	add_child(camera)
	World.lighting.focus_node = camera
	_teleport("hoover_st")
	if OS.get_cmdline_user_args().has("--fps-test"):
		_fps_test()
	if OS.get_cmdline_user_args().has("--print-stats"):
		print("WORLD built in %d ms, nodes: %d, lamps: %d" % [World.build_time_ms, get_tree().get_node_count(), World.lighting._lamps.size()])


func _teleport(spawn: String) -> void:
	var t := World.spawn_point(spawn)
	var p := t.origin + Vector3(0, 2.2, 0) + t.basis * Vector3(0, 0, 9.0)
	camera.global_position = p
	yaw = t.basis.get_euler().y
	pitch = -0.12
	_apply_camera()
	if car != null:
		car.queue_free()
	car = make_test_car()
	add_child(car)
	car.global_transform = t


func _apply_camera() -> void:
	camera.rotation = Vector3(pitch, yaw, 0.0)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir.z -= 1.0
	if Input.is_key_pressed(KEY_S): dir.z += 1.0
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_key_pressed(KEY_E): dir.y += 1.0
	if Input.is_key_pressed(KEY_Q): dir.y -= 1.0
	var speed := 40.0 if Input.is_key_pressed(KEY_SHIFT) else 8.0
	camera.global_position += camera.global_transform.basis * dir * speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.003
		pitch = clampf(pitch - event.relative.y * 0.003, -1.4, 1.4)
		_apply_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5: World.set_time(World.lighting.hours - 1.0)
			KEY_F6: World.set_time(World.lighting.hours + 1.0)
			KEY_F7: World.set_weather("Cloudy" if World.lighting.weather == "Clear" else "Clear")
			KEY_F8:
				_spawn_i = (_spawn_i + 1) % SPAWN_ORDER.size()
				_teleport(SPAWN_ORDER[_spawn_i])
			KEY_F9: set_els(not _els_on)


## Placeholder patrol car (box) used to check headlight / ELS light levels.
func make_test_car() -> Node3D:
	var n := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 1.5, 5.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#0E1319")
	mat.roughness = 0.5
	box.material = mat
	mesh.mesh = box
	mesh.position = Vector3(0, 0.95, 0)
	n.add_child(mesh)
	for x in [-0.7, 0.7]:
		var hl := Lighting.make_headlight()
		hl.position = Vector3(x, 0.75, -2.5)
		n.add_child(hl)
	_els_lights.clear()
	for i in 2:
		var l := Lighting.make_els_light(Color("#FF1030") if i == 0 else Color("#1040FF"))
		l.position = Vector3(-0.5 if i == 0 else 0.5, 2.3, 0.0)
		l.visible = false
		n.add_child(l)
		_els_lights.append(l)
	return n


## Applies a scene preset: time/weather/lamps, camera, fov and the test car at the preset's car spot.
func show_preset(preset_name: String) -> void:
	var info := World.apply_scene_preset(preset_name)
	if info.is_empty():
		return
	camera.fov = info.get("fov", 70.0)
	camera.global_transform = World.camera_preset(preset_name)
	yaw = camera.rotation.y
	pitch = camera.rotation.x
	if car != null:
		car.queue_free()
		car = null
	if info.has("car"):
		car = make_test_car()
		add_child(car)
		car.global_transform = ScenePresets.car_transform(preset_name)
		set_els(info.get("els", false))


func set_els(on: bool) -> void:
	_els_on = on
	for l in _els_lights:
		l.visible = on


## Runs 240 frames per spot and prints frame time, draw calls and objects (non-headless only).
func _fps_test() -> void:
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	World.set_time(21.0)
	for spot in SPAWN_ORDER:
		_teleport(spot)
		for i in 60:
			await get_tree().process_frame
		var ms := 0.0
		for i in 180:
			await get_tree().process_frame
			ms += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()) + RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
		print("FPSTEST %-14s gpu+cpu %.2f ms  fps %d  draws %d  objs %d  prims %d" % [spot, ms / 180.0, Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()
