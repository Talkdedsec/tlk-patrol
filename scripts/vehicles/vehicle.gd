class_name Vehicle
extends VehicleBody3D
## Drivable vehicle (Jolt + VehicleBody3D): arcade driving model tuned for a heavy, grounded feel,
## hinged doors, lights, ELS cell/light integration, PIT spin-out API, smoke and skid marks.
## Spawn through Vehicles.spawn(); API in docs/api/vehicles.md.

signal door_changed(door: StringName, open: bool)
signal driver_changed(driver: Node3D)
signal collided(other: Node, speed_mph: float)

const MPH := 2.2369363
const DOOR_KEYS: Array[StringName] = [&"FL", &"FR", &"RL", &"RR"]
const DOOR_OPEN_DEG := 68.0
const DOOR_TIME := 0.38
const GRAVITY := 9.8

var type_id: StringName = &""
var display_name := ""
var plate := ""
var is_police := false
var def: Dictionary = {}
var driver: Node3D = null
var headlights_on := false
var model: Node3D

# Tuning (filled from the type definition)
var accel_ms2 := 5.0          # full-throttle acceleration below the knee, m/s^2
var knee_ms := 38.0           # speed where the engine force starts to fade, m/s
var top_ms := 50.0            # speed where the engine force is nearly gone, m/s
var max_brake_ms2 := 12.5     # deceleration at brake=1 (hard braking, 25-30 mph/s)
var reverse_ms2 := 2.5
var coast_ms2 := 1.3          # rolling resistance + engine braking with the pedal released (about 3 mph/s with drag)
var drag_coef := 0.57         # 0.5 * rho * Cd * A
var lat_grip := 8.5          # lateral acceleration used to limit the steering angle at speed
var max_lock := 0.62          # steering angle at standstill, rad
var steer_rate := 4.0         # rad/s

var _throttle := 0.0
var _brake := 0.0
var _steer := 0.0
var _handbrake := false
var _cruise_mph := -1.0
var _wheelbase := 3.0
var _wheel_nodes: Dictionary = {}
var _rear_slip_timer := 0.0
var _base_rear_slip := 1.35
var _gear := 1
var _rpm := 900.0
var _braking_lights := false
var _door_target: Dictionary = {}
var _door_prog: Dictionary = {}
var _doors: Dictionary = {}
var _lamps: Dictionary = {}
var _lamp_base: Dictionary = {}
var _spots: Array[SpotLight3D] = []
var _els_cells: Array[MeshInstance3D] = []
var _els_mats: Array[StandardMaterial3D] = []
var _els_last: Array[Color] = []
var _els_base: Array[Color] = []
var _advisor_light: OmniLight3D
var _tail_decal: Decal
var _tail_omni: OmniLight3D
var _scuff_time := 0.0
var _scuff_side := 0.0
var _els_lights: Array = []  # [OmniLight3D, PackedInt32Array indices]
var _els_source := Callable()
var _tr_cells: Array[MeshInstance3D] = []
var _tr_mats: Array[StandardMaterial3D] = []
var _tr_last: Array[Color] = []
var _traffic_source := Callable()
var _smoke: CPUParticles3D
var _tire_smoke: CPUParticles3D
var _smoke_time := 0.0
var _skid_prev: Dictionary = {}
var _engine_players: Array[AudioStreamPlayer3D] = []
var _skid_player: AudioStreamPlayer3D
var _engine_sound := false
var _seat_nodes: Dictionary = {}
var _time := 0.0
var _prev_speed := 0.0
var rear_extent := 2.4   # metres from the origin to the rear bumper (+Z)
var front_extent := 2.4  # metres from the origin to the front bumper
var roof_height := 1.5


# --- construction ---------------------------------------------------------------------------

func setup(type: StringName, definition: Dictionary) -> void:
	type_id = type
	def = definition
	display_name = String(def.get("name", type))
	is_police = bool(def.get("police", false))
	mass = float(def.get("mass", 1800.0))
	accel_ms2 = float(def.get("accel_mph_s", 10.0)) * 0.44704
	top_ms = float(def.get("top_mph", 112.0)) / MPH
	knee_ms = top_ms * float(def.get("knee", 0.78))
	max_brake_ms2 = float(def.get("brake_mph_s", 28.0)) * 0.44704
	coast_ms2 = float(def.get("coast_mph_s", 2.9)) * 0.44704
	drag_coef = float(def.get("drag", 0.57)) * mass / 1800.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = float(def.get("angular_damp", 0.4))
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, float(def.get("com_y", 0.55)), 0.0)
	var packed := load(String(def["model"])) as PackedScene
	model = packed.instantiate() as Node3D
	model.name = "Model"
	add_child(model)
	_apply_colors(def.get("colors", {}))
	_build_wheels()
	_build_collision()
	_collect_nodes()
	_build_lights()
	_build_tail_glow()
	_build_fx()
	for k in DOOR_KEYS:
		_door_target[k] = false
		_door_prog[k] = 0.0
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _ready() -> void:
	set_physics_process(true)
	set_process(true)


func _apply_colors(colors: Dictionary) -> void:
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null and colors.has(mat.resource_name):
				var c := mat.duplicate() as StandardMaterial3D
				c.albedo_color = colors[mat.resource_name]
				m.set_surface_override_material(s, c)


## Re-tint one of the named paint materials (Paint, Roof, Band, Box) on this vehicle.
func set_paint(material_name: String, color: Color) -> void:
	_apply_colors({material_name: color})


func _build_wheels() -> void:
	var sag := 0.05
	var rest := 0.12
	var front_z := 0.0
	var rear_z := 0.0
	for key in [&"FL", &"FR", &"RL", &"RR"]:
		var mesh := model.get_node_or_null("Wheel_" + String(key)) as MeshInstance3D
		if mesh == null:
			push_error("Vehicle %s: missing Wheel_%s" % [type_id, key])
			continue
		var aabb := mesh.mesh.get_aabb()
		var radius := aabb.size.y * 0.5
		var hub := mesh.position
		var w := VehicleWheel3D.new()
		w.name = "WheelNode_" + String(key)
		w.position = hub + Vector3(0.0, rest - sag, 0.0)
		w.wheel_radius = radius
		w.wheel_rest_length = rest
		w.suspension_travel = 0.22
		w.suspension_stiffness = 4.05 / sag
		w.suspension_max_force = mass * GRAVITY * 1.2
		w.damping_compression = 1.0
		w.damping_relaxation = 1.35
		w.wheel_friction_slip = 1.5 if String(key).begins_with("F") else _base_rear_slip
		w.wheel_roll_influence = 0.2
		w.use_as_steering = String(key).begins_with("F")
		w.use_as_traction = not String(key).begins_with("F")
		add_child(w)
		mesh.owner = null  # the glb scene owns it; reparenting under a node outside that scene would warn
		mesh.reparent(w, false)
		mesh.transform = Transform3D.IDENTITY
		_wheel_nodes[key] = w
		if String(key) == "FL":
			front_z = hub.z
		if String(key) == "RL":
			rear_z = hub.z
	_wheelbase = absf(front_z - rear_z)
	if _wheelbase < 1.0:
		_wheelbase = 3.0


## Convex body shapes and extents are built once per model file and shared by every spawn (building one costs ~15 ms).
static var _shape_cache: Dictionary = {}


func _build_collision() -> void:
	var body_mesh := model.get_node_or_null("Body") as MeshInstance3D
	if body_mesh == null:
		return
	var key := String(def["model"])
	if not _shape_cache.has(key):
		var box := body_mesh.mesh.get_aabb()
		# convex hull of the body vertices above the sills (nothing may reach below the wheels' contact height)
		var pts := PackedVector3Array()
		for s in body_mesh.mesh.get_surface_count():
			var arr := body_mesh.mesh.surface_get_arrays(s)
			for p: Vector3 in arr[Mesh.ARRAY_VERTEX]:
				if p.y >= 0.2:
					pts.append(p)
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		_shape_cache[key] = {"shape": shape, "rear": box.end.z, "front": -box.position.z, "roof": box.end.y}
	var cached: Dictionary = _shape_cache[key]
	rear_extent = cached["rear"]
	front_extent = cached["front"]
	roof_height = cached["roof"]
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	cs.shape = cached["shape"]
	add_child(cs)


func _collect_nodes() -> void:
	for k in DOOR_KEYS:
		var d := model.get_node_or_null("Door_" + String(k)) as Node3D
		if d != null:
			_doors[k] = d
	for n in ["Seat_Driver", "Seat_Passenger", "Enter_Driver", "Enter_Passenger", "Cam_Target"]:
		var node := model.get_node_or_null(n) as Node3D
		if node != null:
			_seat_nodes[n] = node
	for i in 8:
		var tc := model.get_node_or_null("ELS_TRAFFIC_%d" % i) as MeshInstance3D
		if tc == null:
			break
		var tm := (tc.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		tc.material_override = tm
		_tr_cells.append(tc)
		_tr_mats.append(tm)
		_tr_last.append(Color(0, 0, 0, 0))
	if _tr_cells.size() > 0:
		_advisor_light = OmniLight3D.new()
		_advisor_light.position = (_tr_cells[0].position + _tr_cells[_tr_cells.size() - 1].position) * 0.5 + Vector3(0, 0.3, -0.2)
		_advisor_light.light_color = Color(1.0, 0.62, 0.1)
		_advisor_light.omni_range = 7.0
		_advisor_light.omni_attenuation = 1.5
		_advisor_light.light_energy = 0.0
		_advisor_light.visible = false
		add_child(_advisor_light)
	var cells: Dictionary = {}
	for mi in model.find_children("ELS_CELL_*", "MeshInstance3D", true, false):
		cells[int(String(mi.name).get_slice("_", 2))] = mi
	var highest := -1
	for i in cells:
		highest = maxi(highest, int(i))
	_els_cells.resize(highest + 1)
	_els_mats.resize(highest + 1)
	_els_last.resize(highest + 1)
	_els_base.resize(highest + 1)
	for i in cells:
		var cell: MeshInstance3D = cells[i]
		var mat := (cell.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		mat.emission_enabled = false
		cell.material_override = mat
		_els_cells[i] = cell
		_els_mats[i] = mat
		_els_last[i] = Color(0, 0, 0, 0)
		_els_base[i] = mat.albedo_color


func _build_lights() -> void:
	for n in ["Headlight_L", "Headlight_R", "Taillight_L", "Taillight_R", "BrakeLight_L", "BrakeLight_R", "BrakeLight_High"]:
		var node := model.get_node_or_null(n) as MeshInstance3D
		if node == null:
			continue
		var mat := (node.mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
		node.material_override = mat
		if def.has("tail_scale") and n.begins_with("Taillight"):
			node.scale = Vector3.ONE * float(def["tail_scale"])
		_lamps[n] = mat
		_lamp_base[n] = mat.albedo_color
	for n in ["Headlight_L", "Headlight_R"]:
		var node := model.get_node_or_null(n) as Node3D
		if node == null:
			continue
		var spot := SpotLight3D.new()
		spot.name = "Spot_" + n
		spot.position = node.position + Vector3(0, 0.0, -0.1)
		spot.spot_range = 14.0
		spot.spot_angle = 45.0
		spot.spot_attenuation = 1.0
		spot.light_energy = 10.0
		spot.light_color = Color(1.0, 0.96, 0.86)
		spot.rotation_degrees.x = -3.0
		spot.visible = false
		add_child(spot)
		_spots.append(spot)
	# ground wash: one soft single-colour blob (Decal) and a weak omni per side, so red and blue never blend
	if _els_cells.size() > 0:
		var sides := [
			PackedInt32Array([0, 1, 2, 3, 4]) if _els_cells[0] != null else PackedInt32Array([10, 11, 12, 13, 14]),
			PackedInt32Array([5, 6, 7, 8, 9]) if _els_cells.size() > 9 and _els_cells[5] != null else PackedInt32Array([15, 16, 17, 18, 19]),
		]
		for k in 2:
			var g: PackedInt32Array = sides[k]
			var pos := Vector3.ZERO
			var n := 0
			for i in g:
				if i < _els_cells.size() and _els_cells[i] != null:
					pos += _els_cells[i].position
					n += 1
			if n == 0:
				continue
			var c := pos / n
			var side_x := -1.0 if k == 0 else 1.0
			var decal := Decal.new()
			decal.size = Vector3(5.5, 0.6, 5.5)
			decal.position = Vector3(side_x * maxf(absf(c.x) * 1.7, 1.0), 0.1, c.z * 0.3)
			decal.texture_albedo = _blob_texture()
			decal.texture_emission = _blob_texture(true)
			decal.albedo_mix = 0.8
			decal.emission_energy = 0.0
			decal.upper_fade = 0.4
			decal.lower_fade = 0.4
			decal.visible = false
			add_child(decal)
			var omni := OmniLight3D.new()
			omni.position = Vector3(side_x * maxf(absf(c.x) * 1.7, 1.0), 0.8, c.z * 0.3)
			omni.omni_range = 5.0
			omni.omni_attenuation = 2.0
			omni.light_energy = 0.0
			omni.visible = false
			add_child(omni)
			_els_lights.append([omni, g, decal])


func _build_tail_glow() -> void:
	if not _lamps.has("Taillight_L"):
		return
	_tail_decal = Decal.new()
	_tail_decal.size = Vector3(4.5, 0.6, 4.5)
	_tail_decal.position = Vector3(0, 0.1, rear_extent + 1.2)
	_tail_decal.texture_albedo = _blob_texture()
	_tail_decal.texture_emission = _blob_texture(true)
	_tail_decal.albedo_mix = 0.8
	_tail_decal.upper_fade = 0.4
	_tail_decal.lower_fade = 0.4
	_tail_decal.visible = false
	add_child(_tail_decal)
	_tail_omni = OmniLight3D.new()
	_tail_omni.position = Vector3(0, 0.6, rear_extent + 0.4)
	_tail_omni.light_color = Color(1.0, 0.05, 0.04)
	_tail_omni.omni_range = 4.0
	_tail_omni.omni_attenuation = 2.0
	_tail_omni.light_energy = 0.0
	_tail_omni.visible = false
	add_child(_tail_omni)


static var _blob_tex: Dictionary = {}


## Soft radial blob: the albedo texture fades by alpha, the emission texture (alpha is ignored there) fades to black.
static func _blob_texture(emission := false) -> GradientTexture2D:
	if not _blob_tex.has(emission):
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		if emission:
			grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.3, 0.3, 0.3, 1), Color(0, 0, 0, 1)])
		else:
			grad.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0)])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 128
		tex.height = 128
		_blob_tex[emission] = tex
	return _blob_tex[emission]


func _build_fx() -> void:
	_smoke = _make_smoke(Color(0.92, 0.92, 0.94, 0.55), 1.6, 0.45, 3.2)
	_smoke.position = Vector3(0, 0.8, -1.9)
	add_child(_smoke)
	_tire_smoke = _make_smoke(Color(0.85, 0.85, 0.87, 0.4), 0.9, 0.3, 1.6)
	_tire_smoke.position = Vector3(0, 0.25, 1.4)
	add_child(_tire_smoke)
	var plate_nodes := {"Plate_Rear": 0.0, "Plate_Front": PI}
	for n in plate_nodes:
		var pn := model.get_node_or_null(n) as Node3D
		if pn == null:
			continue
		var label := Label3D.new()
		label.name = "PlateText"
		label.text = plate
		label.font_size = 52
		label.pixel_size = 0.0011
		label.modulate = Color(0.1, 0.12, 0.2)
		label.outline_size = 0
		label.position = Vector3(0, 0, 0.0075 if n == "Plate_Rear" else -0.0075)
		label.rotation.y = plate_nodes[n]
		pn.add_child(label)


func _make_smoke(color: Color, life: float, size: float, spread: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.amount = 36
	p.lifetime = life * 1.6
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 0.5, 0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.2
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	sm.material = mat
	p.mesh = sm
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.r, color.g, color.b, color.a))
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	return p


# --- public control API ---------------------------------------------------------------------

## Throttle -1..1 (negative = reverse / brake while still rolling forward).
func set_throttle(value: float) -> void:
	_throttle = clampf(value, -1.0, 1.0)


## Brake pedal 0..1 (1 = hard braking, about 28 mph/s). Named *_pedal because VehicleBody3D already owns set_brake().
func set_brake_pedal(value: float) -> void:
	_brake = clampf(value, 0.0, 1.0)


## All three driver inputs at once: throttle -1..1, steer -1 (left)..1 (right), brake 0..1.
func set_controls(throttle: float, steer: float, brake_pedal: float) -> void:
	set_throttle(throttle)
	set_steer(steer)
	set_brake_pedal(brake_pedal)


## Steering -1 (left) .. +1 (right).
func set_steer(value: float) -> void:
	_steer = clampf(value, -1.0, 1.0)


func set_handbrake(on: bool) -> void:
	_handbrake = on


func set_headlights(on: bool) -> void:
	headlights_on = on
	for s in _spots:
		s.visible = on
	_update_lamps()


## Cruise controller for AI: holds target speed (mph) by driving throttle/brake. Pass a negative value to release.
func set_cruise_mph(mph: float) -> void:
	_cruise_mph = mph


## Sets steering so the car heads for a world point (pure pursuit style, one call per frame).
func steer_towards(world_point: Vector3) -> void:
	var local := to_local(world_point)
	var angle := atan2(local.x, -local.z)
	if local.z > 0.0:
		angle = signf(local.x) * PI * 0.5
	_steer = clampf(angle / maxf(_max_steer_at(speed_ms()), 0.05), -1.0, 1.0)


func speed_ms() -> float:
	return absf(forward_speed_ms())


func forward_speed_ms() -> float:
	return linear_velocity.dot(-global_transform.basis.z)


func speed_mph() -> float:
	return speed_ms() * MPH


func forward_speed_mph() -> float:
	return forward_speed_ms() * MPH


func rpm() -> float:
	return _rpm


func gear() -> int:
	return _gear


func is_braking() -> bool:
	return _braking_lights


## Changes the plate text at run time (plate labels and the Vehicles registry follow).
func set_plate(text: String) -> void:
	var old := plate
	plate = text
	for label in model.find_children("PlateText", "Label3D", true, false):
		(label as Label3D).text = text
	Vehicles.update_plate(self, old)


func set_driver(node: Node3D) -> void:
	if driver == node:
		return
	driver = node
	driver_changed.emit(node)


# --- doors / seats --------------------------------------------------------------------------

func has_door(key: StringName) -> bool:
	return _doors.has(key)


func set_door(key: StringName, open: bool) -> void:
	if not _doors.has(key) or _door_target[key] == open:
		return
	_door_target[key] = open
	door_changed.emit(key, open)


func toggle_door(key: StringName) -> void:
	set_door(key, not bool(_door_target.get(key, false)))


func is_door_open(key: StringName) -> bool:
	return bool(_door_target.get(key, false))


func open_driver_door() -> void:
	set_door(&"FL", true)


func close_driver_door() -> void:
	set_door(&"FL", false)


## Global transform of a seat marker (&"driver" or &"passenger").
func seat_transform(seat: StringName) -> Transform3D:
	var n := _seat_nodes.get("Seat_" + String(seat).capitalize()) as Node3D
	return n.global_transform if n != null else global_transform


## Standing point beside the door for "E Get in"; -Z of the returned basis faces the car.
func enter_transform(seat: StringName) -> Transform3D:
	var n := _seat_nodes.get("Enter_" + String(seat).capitalize()) as Node3D
	if n == null:
		return global_transform
	var p := n.global_position
	var inward := (global_transform.origin - p)
	inward.y = 0.0
	var b := Basis.looking_at(inward.normalized(), Vector3.UP) if inward.length() > 0.01 else global_transform.basis
	return Transform3D(b, p)


## Returns &"driver" / &"passenger" when `world_pos` is within `max_dist` of that door's entry point, else &"".
func seat_near(world_pos: Vector3, max_dist := 2.0) -> StringName:
	for seat in [&"driver", &"passenger"]:
		var t := enter_transform(seat)
		if t.origin.distance_to(world_pos) <= max_dist:
			return seat
	return &""


func cam_target_position() -> Vector3:
	var n := _seat_nodes.get("Cam_Target") as Node3D
	return n.global_position if n != null else global_position + Vector3(0, 1.5, 0)


# --- ELS integration ------------------------------------------------------------------------

## `source` returns a PackedColorArray with one colour per cell (black/alpha 0 = off). If the Callable takes one
## argument it receives the vehicle's time in seconds, otherwise it is called without arguments. Cell n takes
## colors[n % colors.size()]. Pass an invalid Callable to switch all cells off.
func set_els_source(source: Callable) -> void:
	_els_source = source
	if not source.is_valid():
		_els_apply(PackedColorArray())


## Drives the cells from the Els autoload (docs/api/els.md: cell_colors(Els.now())). Pass false to switch them off.
func use_els(on := true) -> void:
	if on:
		set_els_source(func() -> PackedColorArray: return Els.cell_colors(Els.now()))
		set_traffic_source(func() -> PackedColorArray: return Els.traffic_colors(Els.now()))
	else:
		set_els_source(Callable())
		set_traffic_source(Callable())


## Traffic advisor (8 amber cells ELS_TRAFFIC_0..7 behind the light bar); same Callable contract as set_els_source.
func set_traffic_source(source: Callable) -> void:
	_traffic_source = source
	if not source.is_valid():
		_traffic_apply(PackedColorArray())


func _traffic_apply(colors: PackedColorArray) -> void:
	var n := colors.size()
	for i in _tr_cells.size():
		var c := Color(0, 0, 0, 0) if n == 0 else colors[i % n]
		if c == _tr_last[i]:
			continue
		_tr_last[i] = c
		var lit := maxf(c.r, maxf(c.g, c.b)) * c.a > 0.04
		_tr_mats[i].emission_enabled = lit
		if lit:
			_tr_mats[i].emission = Color(c.r, c.g, c.b)
			_tr_mats[i].emission_energy_multiplier = 7.0 * c.a
			_tr_mats[i].albedo_color = Color(c.r, c.g, c.b) * 0.5
		else:
			_tr_mats[i].albedo_color = Color(0.29, 0.2, 0.02)
	if _advisor_light != null:
		var count := 0
		for c in _tr_last:
			if maxf(c.r, maxf(c.g, c.b)) * c.a > 0.04:
				count += 1
		_advisor_light.visible = count > 0
		_advisor_light.light_energy = 2.0 * clampf(float(count) / maxf(_tr_last.size() * 0.5, 1.0), 0.0, 1.0)


func els_cell_count() -> int:
	return _els_cells.size()


func has_lightbar() -> bool:
	return _els_cells.size() > 9 and _els_cells[0] != null


func _els_update() -> void:
	if _traffic_source.is_valid():
		_traffic_apply(_traffic_source.call() if _traffic_source.get_argument_count() == 0 else _traffic_source.call(_time))
	if not _els_source.is_valid():
		return
	var colors: PackedColorArray
	if _els_source.get_argument_count() == 0:
		colors = _els_source.call()
	else:
		colors = _els_source.call(_time)
	_els_apply(colors)


func _els_apply(colors: PackedColorArray) -> void:
	var n := colors.size()
	for i in _els_cells.size():
		if _els_cells[i] == null:
			continue
		var c := Color(0, 0, 0, 0) if n == 0 else colors[i % n]
		if c == _els_last[i]:
			continue
		_els_last[i] = c
		var mat := _els_mats[i]
		var lit := maxf(c.r, maxf(c.g, c.b)) * c.a > 0.04
		mat.emission_enabled = lit
		if lit:
			mat.emission = Color(c.r, c.g, c.b)
			mat.emission_energy_multiplier = 4.0 * c.a
			mat.albedo_color = Color(c.r, c.g, c.b) * 0.5
		else:
			mat.albedo_color = _els_base[i]
	for entry in _els_lights:
		var omni: OmniLight3D = entry[0]
		var g: PackedInt32Array = entry[1]
		var sum := Color(0, 0, 0, 0)
		var cnt := 0
		for i in g:
			if i < _els_last.size() and _els_cells[i] != null:
				var c: Color = _els_last[i]
				sum += Color(c.r * c.a, c.g * c.a, c.b * c.a, 0)
				cnt += 1
		if cnt == 0:
			continue
		var avg := sum / float(cnt) * 2.4
		var e := maxf(avg.r, maxf(avg.g, avg.b))
		var decal: Decal = entry[2]
		omni.visible = e > 0.03
		decal.visible = omni.visible
		if omni.visible:
			var hue := Color(avg.r / e, avg.g / e, avg.b / e)
			omni.light_color = hue
			omni.light_energy = minf(e, 1.5) * 0.8
			decal.modulate = Color(hue.r, hue.g, hue.b, clampf(e, 0.0, 1.0) * 0.3)
			decal.emission_energy = minf(e, 1.5) * 0.55


# --- PIT / effects --------------------------------------------------------------------------

## PIT spin-out: a push on the rear corner. `side` = -1 (left rear) or +1 (right rear), `strength` 0..1+.
## The tail is shoved sideways, the rear tyres lose grip for a moment and the car spins about 90-270 degrees.
func pit_spin(side: float, strength := 1.0) -> void:
	var s := signf(side) if side != 0.0 else 1.0
	var rear := global_transform * Vector3(s * 0.8, 0.5, _wheelbase * 0.5 + 0.9)
	var lateral := -global_transform.basis.x * s
	apply_impulse(lateral * mass * 0.7 * strength, rear - global_position)
	apply_torque_impulse(Vector3.UP * (-s) * mass * 0.9 * strength)
	_rear_slip_timer = 0.35 + 0.9 * strength
	start_smoke(9.0)


## Direct lateral shove at the rear (continuous PIT contact); impulse in m/s of velocity change.
func pit_push(side: float, dv: float) -> void:
	var s := signf(side) if side != 0.0 else 1.0
	var rear := global_transform * Vector3(s * 0.8, 0.5, _wheelbase * 0.5 + 0.9)
	apply_impulse(-global_transform.basis.x * s * mass * dv, rear - global_position)
	_rear_slip_timer = maxf(_rear_slip_timer, 0.6)


## Visual-only PIT contact: white smoke plus skid marks from the rear tyres, no impulse (so it is safe at any speed).
## `side` -1/+1 picks the left/right rear tyre, 0 both.
func pit_scuff(side: float, seconds: float) -> void:
	_scuff_time = maxf(_scuff_time, seconds)
	_scuff_side = signf(side)
	start_smoke(seconds)


func start_smoke(seconds: float) -> void:
	_smoke_time = maxf(_smoke_time, seconds)


func teleport(t: Transform3D) -> void:
	global_transform = t
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func set_engine_sound(on: bool) -> void:
	if on == _engine_sound:
		return
	_engine_sound = on
	if on and _engine_players.is_empty():
		_build_audio()
	for p in _engine_players:
		p.playing = on
	if _skid_player != null:
		_skid_player.playing = on


func _build_audio() -> void:
	var files := ["engine_idle", "engine_mid", "engine_high"]
	for f in files:
		var stream := load("res://assets/audio/engine/%s.wav" % f) as AudioStreamWAV
		if stream == null:
			continue
		stream = stream.duplicate() as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / 2
		var p := AudioStreamPlayer3D.new()
		p.stream = stream
		p.unit_size = 8.0
		p.max_distance = 120.0
		p.volume_db = -80.0
		add_child(p)
		_engine_players.append(p)
	var skid := load("res://assets/audio/engine/skid.wav") as AudioStreamWAV
	if skid != null:
		skid = skid.duplicate() as AudioStreamWAV
		skid.loop_mode = AudioStreamWAV.LOOP_FORWARD
		skid.loop_begin = 0
		skid.loop_end = skid.data.size() / 2
		_skid_player = AudioStreamPlayer3D.new()
		_skid_player.stream = skid
		_skid_player.volume_db = -80.0
		_skid_player.unit_size = 8.0
		add_child(_skid_player)


# --- simulation -----------------------------------------------------------------------------

func _max_steer_at(v: float) -> float:
	var limit := atan(_wheelbase * lat_grip / maxf(v * v, 0.01))
	return clampf(limit, 0.006, max_lock)


func _drive_force(v: float) -> float:
	var f := mass * accel_ms2
	if v > knee_ms:
		var t := clampf((v - knee_ms) / (top_ms - knee_ms), 0.0, 1.0)
		f *= 1.0 - 0.85 * t * t
	return f


func _brake_value_for(decel: float) -> float:
	# VehicleBody3D applies `brake` as an impulse of about 60 N*s/s per wheel and unit (measured), 4 wheels
	return decel * mass / 240.0


func _physics_process(delta: float) -> void:
	_time += delta
	var fwd := -global_transform.basis.z
	var v := linear_velocity.dot(fwd)
	var av := absf(v)

	var thr := _throttle
	var brk := _brake
	if _cruise_mph >= 0.0:
		var err := _cruise_mph - av * MPH
		thr = clampf(err * 0.22, 0.0, 1.0)
		brk = clampf((-err - 1.5) * 0.08, 0.0, 0.6)

	# drive / brake / reverse
	var engine := 0.0
	var brake_decel := brk * max_brake_ms2
	if thr > 0.0:
		if v < -1.0:
			brake_decel = maxf(brake_decel, thr * max_brake_ms2 * 0.6)
		else:
			engine = thr * _drive_force(maxf(v, 0.0))
	elif thr < 0.0:
		if v > 1.0:
			brake_decel = maxf(brake_decel, -thr * max_brake_ms2)
		else:
			engine = -(-thr) * mass * reverse_ms2 * (1.0 if v > -8.0 else 0.0)
	if thr == 0.0:
		# engine braking: ramps in above walking pace so the car still comes to rest without chattering
		brake_decel = maxf(brake_decel, coast_ms2 * clampf(av / 1.5, 0.0, 1.0))
	if _handbrake:
		brake_decel = maxf(brake_decel, 6.0)
	engine_force = -engine * 0.5   # VehicleBody3D drives toward +Z for positive force; our nose is -Z. Two wheels share it
	brake = _brake_value_for(brake_decel)
	_braking_lights = brk > 0.05 or (thr < 0.0 and v > 1.0) or _handbrake


	# steering: speed limited lock, rate limited
	var lock := _max_steer_at(av)
	steering = clampf(move_toward(steering, -_steer * lock, steer_rate * delta), -lock, lock)

	# PIT: temporarily slippery rear tyres
	if _rear_slip_timer > 0.0:
		_rear_slip_timer -= delta
	for key in [&"RL", &"RR"]:
		var w := _wheel_nodes.get(key) as VehicleWheel3D
		if w != null:
			w.wheel_friction_slip = 0.32 if _rear_slip_timer > 0.0 else _base_rear_slip

	_scuff_time = maxf(_scuff_time - delta, 0.0)
	_update_gearbox(av)
	_update_skid(av)
	_prev_speed = av * MPH


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# aerodynamic drag (the project's default damping is disabled in setup())
	var v := state.linear_velocity
	var sp := v.length()
	if sp > 0.5:
		state.linear_velocity = v - v / sp * minf(drag_coef * sp * sp / mass * state.step, sp)


func _update_gearbox(av: float) -> void:
	var mph := av * MPH
	var limits := [0.0, 20.0, 36.0, 54.0, 75.0]
	var g := 1
	for i in range(1, limits.size()):
		if mph >= limits[i]:
			g = i + 1
	_gear = clampi(g, 1, 5)
	var target: float
	if mph <= 1.0:
		target = 850.0 + absf(_throttle) * 1500.0
	elif _gear < 5:
		var lo: float = limits[_gear - 1]
		var hi: float = limits[_gear]
		target = lerpf(1800.0, 4600.0, clampf((mph - lo) / (hi - lo), 0.0, 1.0))
	else:
		# 5th gear: about 3300 rpm at 75 mph, 4000 at 85 and 4400 at 120 mph
		target = 3300.0 + clampf((mph - 75.0) / 10.0, 0.0, 1.0) * 700.0 + maxf(mph - 85.0, 0.0) * 11.4
	_rpm = lerpf(_rpm, clampf(target + absf(_throttle) * 300.0, 800.0, 6800.0), 0.2)


func _update_skid(av: float) -> void:
	var slipping := false
	for key in [&"RL", &"RR"]:
		var w := _wheel_nodes.get(key) as VehicleWheel3D
		if w == null:
			continue
		var forced: bool = _scuff_time > 0.0 and av > 1.0 and (_scuff_side == 0.0 or (key == &"RR") == (_scuff_side > 0.0))
		var skidding: bool = w.is_in_contact() and (forced or (w.get_skidinfo() < 0.6 and av > 3.0))
		if skidding:
			slipping = true
			var p := w.global_position - global_transform.basis.y * w.wheel_radius * 0.95
			if _skid_prev.has(key) and (_skid_prev[key] as Vector3).distance_to(p) > 0.35:
				Vehicles.add_skid(_skid_prev[key], p)
				_skid_prev[key] = p
			elif not _skid_prev.has(key):
				_skid_prev[key] = p
		else:
			_skid_prev.erase(key)
	_tire_smoke.emitting = slipping and (av > 5.0 or _scuff_time > 0.0)
	if _skid_player != null:
		_skid_player.volume_db = -6.0 if slipping else -80.0


func _process(delta: float) -> void:
	for k in DOOR_KEYS:
		if not _doors.has(k):
			continue
		var target := 1.0 if _door_target[k] else 0.0
		var p: float = _door_prog[k]
		if p != target:
			p = move_toward(p, target, delta / DOOR_TIME)
			_door_prog[k] = p
			var ang := deg_to_rad(DOOR_OPEN_DEG) * smoothstep(0.0, 1.0, p)
			(_doors[k] as Node3D).rotation.y = -ang if String(k).ends_with("L") else ang
	if _smoke_time > 0.0:
		_smoke_time -= delta
		_smoke.emitting = true
	elif _smoke.emitting:
		_smoke.emitting = false
	_update_lamps()
	_els_update()
	if _engine_sound and not _engine_players.is_empty():
		_update_engine_audio()


func _update_lamps() -> void:
	var braking := _braking_lights
	var tail_e := (0.3 if headlights_on else 0.0) + (2.6 if braking else 0.0)
	for n in _lamps:
		var mat: StandardMaterial3D = _lamps[n]
		var on := false
		var energy := 0.0
		var col := Color(1, 1, 1)
		if n.begins_with("Headlight"):
			on = headlights_on
			energy = 6.0
			col = Color(1.0, 0.97, 0.88)
		elif n.begins_with("Taillight"):
			on = tail_e > 0.0
			energy = tail_e
			col = Color(1.0, 0.05, 0.04)
		else:
			on = braking
			energy = 3.2
			col = Color(1.0, 0.04, 0.03)
		mat.emission_enabled = on
		if on:
			mat.emission = col
			mat.emission_energy_multiplier = energy
			mat.albedo_color = col * clampf(energy * 0.12, 0.12, 0.6)
		else:
			mat.albedo_color = _lamp_base[n]
	if _tail_decal != null:
		var glow := (0.25 if headlights_on else 0.0) + (0.75 if braking else 0.0)
		_tail_decal.visible = glow > 0.0
		_tail_omni.visible = glow > 0.0
		_tail_decal.modulate = Color(1.0, 0.05, 0.04, glow * 0.45)
		_tail_decal.emission_energy = glow * 0.8
		_tail_omni.light_energy = glow * 0.7


func _update_engine_audio() -> void:
	var r := _rpm
	var weights := [
		clampf(1.0 - (r - 900.0) / 1800.0, 0.0, 1.0),
		clampf(1.0 - absf(r - 3000.0) / 2000.0, 0.0, 1.0),
		clampf((r - 3500.0) / 2500.0, 0.0, 1.0),
	]
	var base := [1000.0, 3000.0, 5200.0]
	for i in _engine_players.size():
		var p := _engine_players[i]
		p.pitch_scale = clampf(r / base[i], 0.5, 2.2)
		var load_boost := 0.0 if _throttle > 0.1 else -4.0
		p.volume_db = -80.0 if weights[i] < 0.01 else linear_to_db(weights[i]) + load_boost - 4.0


func _on_body_entered(other: Node) -> void:
	var s := _prev_speed
	if s > 8.0:
		collided.emit(other, s)
