extends Node3D
## Vehicle test bench: straight road, drivable vehicle with chase camera, ELS test patterns and headless measurements.
##
## Keys: W/S gas/brake+reverse, A/D steer, Space handbrake, H headlights, F driver door, G all doors,
## L ELS test pattern, P PIT spin, Tab next vehicle, N day/night, R reset.
## Command line (after --): --type id  --night 1  --measure 1  --preset name

const SCENE_TYPES: Array[StringName] = [
	&"sheriff_pickup", &"patrol_sedan", &"patrol_sedan_unmarked", &"patrol_suv", &"patrol_suv_214", &"ranger_suv", &"civ_sedan",
	&"civ_hatchback", &"civ_wagon", &"civ_pickup", &"civ_van", &"civ_boxtruck",
]

var vehicle: Vehicle
var cam: VehicleCamera
var night := false
var els_on := false
var _type_index := 0
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial
var _hud: Label
var _throttle_ramp := 0.0
var _brake_ramp := 0.0
var _steer_ramp := 0.0
var _args := {}


func _ready() -> void:
	_args = _parse_args()
	Vehicles.skid_parent = self
	night = String(_args.get("night", "0")) == "1"
	_build_world()
	var type := StringName(_args.get("type", "sheriff_pickup"))
	_type_index = maxi(SCENE_TYPES.find(type), 0)
	cam = VehicleCamera.new()
	add_child(cam)
	cam.apply_preset(StringName(_args.get("cam", "pursuit")))
	_spawn(type)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_color_override("font_color", Color.WHITE)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 6)
	add_child(_hud)
	_set_night(night)
	if String(_args.get("measure", "0")) == "1":
		_hud.visible = false
		await _run_measure()
		get_tree().quit()
		return
	if _args.has("preset"):
		preset(String(_args["preset"]))


func _spawn(type: StringName) -> void:
	var old_t := Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0))
	if vehicle != null:
		old_t = Transform3D(Basis(Vector3.UP, vehicle.rotation.y), vehicle.global_position + Vector3(0, 0.2, 0))
		vehicle.queue_free()
		await get_tree().process_frame
	vehicle = Vehicles.spawn(type, old_t, self)
	vehicle.set_headlights(night)
	vehicle.set_engine_sound(String(_args.get("sound", "0")) == "1")
	cam.follow(vehicle)
	cam.make_current()
	_apply_els()


func _apply_els() -> void:
	if get_tree().root.has_node("Els") and String(_args.get("fake_els", "0")) != "1":
		Els.set_stage(3)
		Els.set_lights(els_on)
		vehicle.use_els(true)
	else:
		vehicle.set_els_source(_els_source() if els_on else Callable())


func _els_source() -> Callable:
	if get_tree().root.has_node("Els") and get_node("/root/Els").has_method("cell_colors") and String(_args.get("fake_els", "0")) != "1":
		return func() -> PackedColorArray: return Els.cell_colors(Els.now())
	return Callable(self, "_fake_els")


## Placeholder pattern used until the Els autoload provides cell_colors(): alternating red/blue halves.
func _fake_els(t: float) -> PackedColorArray:
	var out := PackedColorArray()
	var phase := int(t * 7.0) % 4
	for i in 10:
		var left := i < 5
		var on := (phase == 0 or phase == 1) if left else (phase == 2 or phase == 3)
		out.append(Color(1.0, 0.05, 0.05) if (left and on) else (Color(0.1, 0.3, 1.0) if (not left and on) else Color(0, 0, 0, 0)))
	return out


func _build_world() -> void:
	_sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	_sun.shadow_enabled = true
	add_child(_sun)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	cs.shape = box
	cs.position.y = -1.0
	floor_body.add_child(cs)
	add_child(floor_body)
	_add_box(Vector3(0, -0.02, 0), Vector3(4000, 0.02, 4000), Color("4d5a3a"))
	_add_box(Vector3(0, 0.0, 0), Vector3(9, 0.03, 4000), Color("34363b"))
	for z in range(-1900, 1900, 8):
		_add_box(Vector3(0, 0.035, z), Vector3(0.14, 0.01, 4.0), Color("d9b21c"))
		_add_box(Vector3(0.45, 0.035, z), Vector3(0.14, 0.01, 4.0), Color("d9b21c"))
	for z in range(-1900, 1900, 3):
		_add_box(Vector3(-4.3, 0.035, z), Vector3(0.14, 0.01, 2.0), Color("e8e8e8"))
		_add_box(Vector3(4.3, 0.035, z), Vector3(0.14, 0.01, 2.0), Color("e8e8e8"))
	for z in range(-1900, 1900, 30):
		_add_box(Vector3(-6.0, 0.9, z), Vector3(0.12, 1.8, 0.12), Color("5c4a32"))
		_add_box(Vector3(6.0, 0.9, z), Vector3(0.12, 1.8, 0.12), Color("5c4a32"))
	for i in 6:
		_add_box(Vector3(6.5 + i * 2.0, 1.0, 20 + i * 14), Vector3(1.6, 2.0, 1.6), Color("6b4a3a"))


func _add_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	mi.material_override = m
	mi.position = pos
	add_child(mi)


func _set_night(on: bool) -> void:
	night = on
	if on:
		_sky_mat.sky_top_color = Color("04060b")
		_sky_mat.sky_horizon_color = Color("1b1612")
		_sky_mat.ground_horizon_color = Color("1b1612")
		_sky_mat.ground_bottom_color = Color("08090c")
		_sun.light_energy = 0.04
		_env.ambient_light_energy = 0.35
	else:
		_sky_mat.sky_top_color = Color("8FA3B8")
		_sky_mat.sky_horizon_color = Color("B9C4CF")
		_sky_mat.ground_horizon_color = Color("B9C4CF")
		_sun.light_energy = 1.0
		_env.ambient_light_energy = 1.0
	if vehicle != null:
		vehicle.set_headlights(on)


func _physics_process(delta: float) -> void:
	if vehicle == null or String(_args.get("measure", "0")) == "1":
		return
	var up := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var down := Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	_throttle_ramp = move_toward(_throttle_ramp, 1.0 if up else 0.0, 3.0 * delta)
	var fwd := vehicle.forward_speed_ms()
	var want_brake := down and fwd > 1.0
	_brake_ramp = move_toward(_brake_ramp, 1.0 if want_brake else 0.0, 2.2 * delta)
	var reverse := down and fwd <= 1.0
	_steer_ramp = move_toward(_steer_ramp, float(int(right) - int(left)), 5.0 * delta)
	vehicle.set_controls(-1.0 if reverse else _throttle_ramp, _steer_ramp, _brake_ramp)
	vehicle.set_handbrake(Input.is_physical_key_pressed(KEY_SPACE))
	_hud.text = "%s  %03d mph  gear %d  %4d rpm   [H]lights [F]door [G]doors [L]ELS [P]PIT [Tab]vehicle [N]ight [R]eset" % [
		vehicle.display_name, int(vehicle.speed_mph()), vehicle.gear(), int(vehicle.rpm())]


func _unhandled_key_input(event: InputEvent) -> void:
	var e := event as InputEventKey
	if e == null or not e.pressed or e.echo or vehicle == null:
		return
	match e.physical_keycode:
		KEY_H:
			vehicle.set_headlights(not vehicle.headlights_on)
		KEY_F:
			vehicle.toggle_door(&"FL")
		KEY_G:
			var open := not vehicle.is_door_open(&"FL")
			for k in Vehicle.DOOR_KEYS:
				vehicle.set_door(k, open)
		KEY_L:
			els_on = not els_on
			_apply_els()
		KEY_P:
			vehicle.pit_spin(1.0, 1.0)
		KEY_TAB:
			_type_index = (_type_index + 1) % SCENE_TYPES.size()
			_spawn(SCENE_TYPES[_type_index])
		KEY_N:
			_set_night(not night)
		KEY_R:
			vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)))


## Screenshot presets used by scripts/dev/shot.gd via vehicle_shot_setup.gd.
func preset(name: String) -> void:
	match name:
		"els_night":
			_set_night(true)
			els_on = true
			_apply_els()
			vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)))
		"doors":
			for k in Vehicle.DOOR_KEYS:
				vehicle.set_door(k, true)
		"lineup":
			# every vehicle type in a row (civilians in random colours), static camera; args: --yaw --dist
			vehicle.queue_free()
			vehicle = null
			cam.target = null
			var x := 0.0
			for t in SCENE_TYPES:
				var xf := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, 0.1, 30.0))
				var v: Vehicle = Vehicles.spawn_traffic(xf, self, t) if String(t).begins_with("civ") or t == &"ranger_suv" else Vehicles.spawn(t, xf, self, {"headlights": night})
				if t == &"patrol_suv" or t == &"patrol_sedan" or t == &"sheriff_pickup":
					v.set_door(&"FL", true)
				x -= 6.2
			var yaw := deg_to_rad(float(_args.get("yaw", "30")))
			var dist := float(_args.get("dist", "34"))
			var mid := Vector3(float(_args.get("mid", str(x * 0.5 + 3.0))), 1.0, 30.0)
			cam.camera.global_position = mid + Vector3(sin(yaw), 0.0, cos(yaw)) * dist + Vector3(0, 9, 0)
			cam.camera.look_at(mid, Vector3.UP)
			cam.set_process(false)
		"pit":
			vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)))
			vehicle.linear_velocity = Vector3(0, 0, -22.0)
			vehicle.pit_spin(1.0, 1.0)


# --- headless measurements ------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _reset_car(speed_mph := 0.0) -> void:
	vehicle.set_controls(0, 0, 0)
	vehicle.set_cruise_mph(-1.0)
	vehicle.teleport(Transform3D(Basis.IDENTITY, Vector3(0, 0.25 if speed_mph == 0.0 else 0.0, 0)))
	vehicle.linear_velocity = Vector3(0, 0, -speed_mph / Vehicle.MPH)
	await _frames(90 if speed_mph == 0.0 else 2)


func _run_measure() -> void:
	var only := String(_args.get("tests", "accel,brake,turn,pit,coast,spawn,scuff")).split(",")
	await _frames(120)
	print("MEASURE type=%s mass=%.0f ride_y=%.3f" % [vehicle.type_id, vehicle.mass, vehicle.global_position.y])
	# acceleration
	if only.has("accel"):
		await _measure_accel()
	if only.has("brake"):
		await _measure_brake()
	if only.has("turn"):
		await _measure_turn()
	if only.has("pit"):
		await _measure_pit()
	if only.has("coast"):
		await _measure_coast()
	if only.has("spawn"):
		await _measure_spawn()
	if only.has("scuff"):
		await _measure_scuff()
	print("MEASURE els cells=%d lightbar=%s" % [vehicle.els_cell_count(), vehicle.has_lightbar()])


func _measure_accel() -> void:
	await _reset_car(0.0)
	var t := 0.0
	var t12 := -1.0
	var t60 := -1.0
	var t92 := -1.0
	var top := 0.0
	vehicle.set_throttle(1.0)
	var steps := 60 * 45
	for i in steps:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		var s := vehicle.speed_mph()
		top = maxf(top, s)
		if t12 < 0.0 and s >= 12.0:
			t12 = t
		if t60 < 0.0 and s >= 60.0:
			t60 = t
		if t92 < 0.0 and s >= 92.0:
			t92 = t
	print("MEASURE accel 0-12=%.2fs 0-60=%.2fs 12-92=%.2fs top=%.1f mph final=%.1f" % [t12, t60, t92 - t12, top, vehicle.speed_mph()])


func _measure_brake() -> void:
	for b in [0.45, 1.0]:
		await _reset_car(90.0)
		vehicle.set_brake_pedal(b)
		var tb := 0.0
		var t80 := -1.0
		var t20 := -1.0
		for i in 60 * 10:
			await get_tree().physics_frame
			tb += 1.0 / 60.0
			var s := vehicle.speed_mph()
			if t80 < 0.0 and s <= 80.0:
				t80 = tb
			if t20 < 0.0 and s <= 20.0:
				t20 = tb
				break
		print("MEASURE brake pedal=%.2f decel 80->20 mph = %.1f mph/s" % [b, 60.0 / maxf(t20 - t80, 0.01)])
	vehicle.set_brake_pedal(0.0)


func _measure_turn() -> void:
	for mph in [12.0, 20.0, 40.0, 60.0, 80.0, 100.0]:
		await _reset_car(mph)
		vehicle.set_cruise_mph(mph)
		vehicle.set_steer(1.0)
		await _frames(150)
		var w := absf(vehicle.angular_velocity.y)
		var v := vehicle.linear_velocity.length()
		print("MEASURE turn at %.0f mph (held right): speed=%.1f mph radius=%.1f m lat=%.2f g yaw_rate_sign=%s tilt=%.1f deg" % [
			mph, v * Vehicle.MPH, v / maxf(w, 0.001), v * w / 9.8, "right(ok)" if vehicle.angular_velocity.y < 0.0 else "LEFT(wrong)",
			rad_to_deg(acos(clampf(vehicle.global_transform.basis.y.y, -1, 1)))])
		vehicle.set_steer(0.0)
	vehicle.set_cruise_mph(-1.0)


func _measure_pit() -> void:
	for strength in [0.3, 0.6, 1.0]:
		await _reset_car(60.0)
		vehicle.set_throttle(0.25)
		var yaw0 := vehicle.rotation.y
		var total := 0.0
		var prev := yaw0
		vehicle.pit_spin(1.0, strength)
		for i in 60 * 5:
			await get_tree().physics_frame
			var y := vehicle.rotation.y
			total += wrapf(y - prev, -PI, PI)
			prev = y
		print("MEASURE pit strength=%.1f total yaw=%.0f deg speed after 5 s=%.0f mph" % [strength, rad_to_deg(total), vehicle.speed_mph()])


func _parse_args() -> Dictionary:
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


func _measure_coast() -> void:
	for mph in [20.0, 60.0, 100.0]:
		await _reset_car(mph)
		vehicle.set_throttle(0.0)
		var s0 := vehicle.speed_mph()
		await _frames(120)
		print("MEASURE coast from %.0f mph: %.1f mph/s (throttle released, 2 s average)" % [mph, (s0 - vehicle.speed_mph()) / 2.0])


func _measure_spawn() -> void:
	var times: Array[String] = []
	var last: Vehicle
	for i in 4:
		var t0 := Time.get_ticks_usec()
		last = Vehicles.spawn(&"civ_sedan", Transform3D(Basis.IDENTITY, Vector3(20.0 + i * 6.0, 0.2, 0)), self)
		times.append("%.1f" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var old := last.plate
	last.set_plate("ABC-1234")
	var label := last.get_node("Model/Plate_Rear/PlateText") as Label3D
	print("MEASURE spawn ms (first builds the shared shape): %s; set_plate: label=%s lookup=%s old_gone=%s" % [
		", ".join(times), label.text, Vehicles.find_by_plate("ABC-1234") == last, Vehicles.find_by_plate(old) == null])


func _measure_scuff() -> void:
	await _reset_car(100.0)
	vehicle.set_cruise_mph(100.0)
	vehicle.pit_scuff(1.0, 3.0)
	await _frames(60)
	var smoke_on: bool = vehicle.get("_smoke").emitting
	await _frames(120)
	print("MEASURE scuff at 100 mph: smoke=%s speed=%.0f mph tilt=%.1f deg yaw_change=%.1f deg" % [smoke_on, vehicle.speed_mph(),
		rad_to_deg(acos(clampf(vehicle.global_transform.basis.y.y, -1, 1))), rad_to_deg(absf(vehicle.rotation.y))])
