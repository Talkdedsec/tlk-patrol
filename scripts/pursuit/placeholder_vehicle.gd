extends Node3D
## Kinematic stand-in for the real Vehicle (box car, no collision response) used when Vehicles.spawn is unavailable
## and in unit tests. Mirrors the Vehicle control API: set_controls(throttle, steer, brake) with steer +1 = right.
## Rear-corner PIT API (pit_push / pit_spin) matches Vehicle: side -1 = left rear struck, +1 = right rear struck.

signal crashed(strength: float)

const MPH := 0.44704

## Line segments (Vector2 pairs, XZ plane) cars cannot cross; used by the test world for guard rails.
static var rails: Array = []

var type_id: StringName = &"civ_sedan"
var plate := ""
var team: StringName = &"civil"
var unit_number := ""
var paint := Color(0, 0, 0, 0)
var extents := Vector3(0.95, 0.75, 2.4)
var wheelbase := 2.9
var max_lock := 0.55
var top_ms := 50.0
var accel_ms2 := 5.3
var max_brake_ms2 := 12.0
var vel := Vector3.ZERO
var driver: Node3D = null
var is_police := false
var headlights_on := false
var spun_out := false
var smoking := 0.0
var scuffs := 0

var _throttle := 0.0
var _brake := 0.0
var _steer := 0.0
var _steer_angle := 0.0
var _spin_rate := 0.0
var _push_yaw := 0.0
var _handbrake := false
var _lamps: Array[MeshInstance3D] = []
var _bar: Array[MeshInstance3D] = []
var _emergency := false
var _t := 0.0
var _smoke: CPUParticles3D
var _skid_prev := Vector3.ZERO
var _skid_have := false


func _ready() -> void:
	is_police = team == &"police"
	_build()


func _build() -> void:
	var col := paint
	if col.a == 0.0:
		col = Color("8f959c")
		var id := String(type_id)
		if id.contains("ranger"):
			col = Color("c9a24a")
		elif id.contains("pickup"):
			col = Color("d8d2c4")
		elif id.contains("van"):
			col = Color("e4e4e4")
		elif id.contains("hatch"):
			col = Color("3d6b4a")
		elif is_police:
			col = Color("15161a")
	var hw := extents.x
	var hl := extents.z
	_box(Vector3(hw * 2.0, 0.75, hl * 2.0), Vector3(0, 0.62, 0), col)
	_box(Vector3(hw * 1.7, 0.62, hl * 1.05), Vector3(0, 1.28, hl * 0.12), col.darkened(0.15))
	_box(Vector3(hw * 1.72, 0.3, hl * 0.95), Vector3(0, 1.42, hl * 0.12), Color("1b2430"))
	if is_police:
		_box(Vector3(hw * 2.02, 0.45, hl * 0.62), Vector3(0, 0.66, 0.0), Color("e9ecef"))
	for sx in [-1.0, 1.0]:
		for sz in [-0.62, 0.62]:
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.36
			cyl.bottom_radius = 0.36
			cyl.height = 0.28
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color("0b0b0d")
			cyl.material = wm
			w.mesh = cyl
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx * hw, 0.36, sz * hl)
			add_child(w)
	for sx in [-0.62, 0.62]:
		_lamps.append(_lamp(Vector3(sx * hw, 0.7, -hl), Color("fff1c0"), false))
		_box_emissive(Vector3(0.38, 0.18, 0.08), Vector3(sx * hw, 0.8, hl), Color("ff1c1c"), 1.2)
	if is_police:
		for i in 2:
			var m := _box_emissive(Vector3(hw * 0.8, 0.14, 0.34), Vector3((-0.5 if i == 0 else 0.5) * hw, 1.62, -0.25),
				Color("ff1030") if i == 0 else Color("1a45ff"), 0.0)
			_bar.append(m)
		if unit_number != "":
			var label := Label3D.new()
			label.text = unit_number
			label.font_size = 96
			label.pixel_size = 0.006
			label.rotation_degrees = Vector3(-90, 0, 0)
			label.position = Vector3(0, 1.45, 0.9)
			label.modulate = Color("e9ecef")
			add_child(label)
	set_headlights(headlights_on)


func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	return mi


func _box_emissive(size: Vector3, pos: Vector3, color: Color, energy: float) -> MeshInstance3D:
	var mi := _box(size, pos, color)
	var mat := (mi.mesh as BoxMesh).material as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mi


func _lamp(pos: Vector3, color: Color, on: bool) -> MeshInstance3D:
	return _box_emissive(Vector3(0.4, 0.16, 0.08), pos, color, 2.0 if on else 0.0)


# --- Vehicle-compatible API --------------------------------------------------------------------------------------

func set_throttle(value: float) -> void:
	_throttle = clampf(value, 0.0, 1.0)


func set_brake_pedal(value: float) -> void:
	_brake = clampf(value, 0.0, 1.0)


func set_steer(value: float) -> void:
	_steer = clampf(value, -1.0, 1.0)


func set_controls(throttle: float, steer: float, brake_pedal: float) -> void:
	set_throttle(throttle)
	set_steer(steer)
	set_brake_pedal(brake_pedal)


func set_handbrake(on: bool) -> void:
	_handbrake = on


func set_headlights(on: bool) -> void:
	headlights_on = on
	for l in _lamps:
		var mat := (l.mesh as BoxMesh).material as StandardMaterial3D
		mat.emission_energy_multiplier = 2.5 if on else 0.0


func set_emergency_lights(on: bool) -> void:
	_emergency = on
	if not on:
		for m in _bar:
			((m.mesh as BoxMesh).material as StandardMaterial3D).emission_energy_multiplier = 0.0


func set_els_source(_source: Callable) -> void:
	pass


func speed_ms() -> float:
	return vel.length()


func speed_mph() -> float:
	return vel.length() / MPH


func forward_speed_ms() -> float:
	return vel.dot(-global_transform.basis.z)


func set_driver(node: Node3D) -> void:
	driver = node


func open_driver_door() -> void:
	pass


func close_driver_door() -> void:
	pass


func enter_transform(_seat: StringName) -> Transform3D:
	var p := global_transform * Vector3(-extents.x - 0.55, 0.0, -0.3)
	var inward := global_position - p
	inward.y = 0.0
	return Transform3D(Basis.looking_at(inward.normalized(), Vector3.UP), p)


func seat_transform(_seat: StringName) -> Transform3D:
	return global_transform


func teleport(t: Transform3D) -> void:
	global_transform = t
	vel = Vector3.ZERO


func start_smoke(seconds: float) -> void:
	smoking = maxf(smoking, seconds)
	if _smoke == null:
		_smoke = CPUParticles3D.new()
		_smoke.amount = 28
		_smoke.lifetime = 2.4
		_smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_smoke.emission_sphere_radius = 0.35
		_smoke.direction = Vector3.UP
		_smoke.spread = 25.0
		_smoke.initial_velocity_min = 1.2
		_smoke.initial_velocity_max = 2.2
		_smoke.gravity = Vector3(0, 0.6, 0)
		_smoke.scale_amount_min = 0.7
		_smoke.scale_amount_max = 1.6
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 0.7
		sm.radial_segments = 8
		sm.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.92, 0.92, 0.92, 0.55)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.material = mat
		_smoke.mesh = sm
		_smoke.position = Vector3(0, 1.0, -extents.z * 0.8)
		add_child(_smoke)
	_smoke.emitting = true


## Rear-corner shove (continuous PIT contact): dv in m/s.
func pit_push(side: float, dv: float) -> void:
	var s := signf(side) if side != 0.0 else 1.0
	_push_yaw = clampf(_push_yaw - s * dv * 0.7, -0.8, 0.8)
	vel += global_transform.basis.x * (-s) * dv * 0.4


## Contact visual without any impulse (smoke now, skid marks come from the slide): the PIT contact look for fast cars.
func pit_scuff(_side: float, seconds: float) -> void:
	scuffs += 1
	start_smoke(seconds)


func pit_spin(side: float, strength := 1.0) -> void:
	var s := signf(side) if side != 0.0 else 1.0
	spun_out = true
	_spin_rate = -s * 5.2 * strength
	vel += global_transform.basis.x * (-s) * 2.0 * strength
	_throttle = 0.0
	_brake = 1.0
	start_smoke(9.0)


func recover() -> void:
	spun_out = false
	_spin_rate = 0.0


# --- simulation --------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _emergency and not _bar.is_empty():
		var phase := int(_t * 7.0) % 2
		for i in _bar.size():
			var on := (i == phase)
			((_bar[i].mesh as BoxMesh).material as StandardMaterial3D).emission_energy_multiplier = 4.0 if on else 0.1
	if smoking > 0.0:
		smoking -= delta
		if smoking <= 0.0 and _smoke != null:
			_smoke.emitting = false


func _physics_process(dt: float) -> void:
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var v_f := vel.dot(fwd)
	var lateral := vel - fwd * v_f
	lateral.y = 0.0
	if spun_out:
		_spin_rate *= exp(-1.7 * dt)
		rotate_y(_spin_rate * dt)
		vel = vel.move_toward(Vector3.ZERO, 5.0 * dt)
	else:
		var a := _throttle * accel_ms2 * clampf(1.0 - absf(v_f) / top_ms, 0.0, 1.0)
		var decel := 0.35 + 0.0016 * v_f * absf(v_f) + _brake * max_brake_ms2
		if _handbrake:
			decel += 8.0
		a -= signf(v_f) * decel
		var new_vf := v_f + a * dt
		if signf(new_vf) != signf(v_f) and (_brake > 0.01 or _throttle < 0.05 or _handbrake):
			new_vf = 0.0
		new_vf = maxf(new_vf, 0.0)
		var target_angle := _steer * max_lock / (1.0 + pow(absf(new_vf) / 22.0, 2.0))
		_steer_angle = move_toward(_steer_angle, target_angle, 2.4 * dt)
		var yaw_rate := -new_vf * tan(_steer_angle) / wheelbase
		var lim := 9.0 / maxf(absf(new_vf), 3.0)
		yaw_rate = clampf(yaw_rate, -lim, lim) + _push_yaw
		_push_yaw *= exp(-1.4 * dt)
		rotate_y(yaw_rate * dt)
		lateral *= exp(-8.0 * dt)
		var nf := -global_transform.basis.z
		nf.y = 0.0
		vel = nf.normalized() * new_vf + lateral
	global_position += vel * dt
	_collide_rails()
	_skid(dt)


func _collide_rails() -> void:
	if rails.is_empty():
		return
	var p := Vector2(global_position.x, global_position.z)
	var radius := 1.7 if spun_out else extents.x + 0.15
	for seg in rails:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var c := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(c)
		if d < radius:
			var n2 := (p - c).normalized() if d > 0.001 else Vector2((b - a).y, -(b - a).x).normalized()
			var n := Vector3(n2.x, 0.0, n2.y)
			global_position += n * (radius - d)
			var vn := vel.dot(n)
			if vn < 0.0:
				if spun_out:
					vel -= n * vn * 1.15
					vel *= 0.55
				else:
					# glance off: slide along the rail and straighten up
					vel -= n * vn
					var tang := Vector3(-n.z, 0.0, n.x)
					var cur := -global_transform.basis.z
					if tang.dot(cur) < 0.0:
						tang = -tang
					rotate_y(clampf(cur.signed_angle_to(tang, Vector3.UP), -0.1, 0.1))
				crashed.emit(absf(vn))
			p = Vector2(global_position.x, global_position.z)


func _skid(_dt: float) -> void:
	var sliding := spun_out and vel.length() > 3.0
	if not sliding:
		_skid_have = false
		return
	var vs: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Vehicles")
	if vs == null or not vs.has_method("add_skid"):
		return
	var rear := global_position + global_transform.basis.z * extents.z * 0.5
	if _skid_have and rear.distance_to(_skid_prev) > 1.0:
		vs.call("add_skid", _skid_prev, rear)
		_skid_prev = rear
	elif not _skid_have:
		_skid_prev = rear
		_skid_have = true
