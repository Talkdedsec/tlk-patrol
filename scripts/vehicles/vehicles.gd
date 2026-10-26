extends Node
## Vehicles autoload: type registry, spawning, traffic helpers, plate generation, persistent skid marks.
## Owner: vehicles session. API: docs/api/vehicles.md.

signal vehicle_spawned(vehicle: Vehicle)
signal vehicle_removed(vehicle: Vehicle)

const MODEL_DIR := "res://assets/models/vehicles/"
const SKID_CAPACITY := 1400
const CIV_COLORS: Array[Color] = [
	Color("c8cdd2"), Color("1d1f24"), Color("7d1f22"), Color("2c4a7a"), Color("d8d2c4"), Color("e0b737"),
	Color("3d6b4a"), Color("8a8f96"), Color("5b3a29"), Color("b3b9bf"),
]

## Node that receives skid marks (a scene may set it; defaults to this autoload).
var skid_parent: Node
var types: Dictionary = {}
var all: Array[Vehicle] = []
var _plates: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _skid_mm: MultiMesh
var _skid_index := 0


func _ready() -> void:
	_rng.randomize()
	_register_builtin()


func _register_builtin() -> void:
	# accel/brake/top speeds are tuned values for police vehicles; civilians are slower.
	var police := {"police": true, "accel_mph_s": 10.6, "top_mph": 112.0, "brake_mph_s": 28.0}
	register_type(&"sheriff_pickup", police.merged({
		"name": "General T-150 Sheriff", "model": MODEL_DIR + "sheriff_pickup.glb", "mass": 2400.0, "traffic": false}))
	register_type(&"sheriff_pickup_black", police.merged({
		"name": "General T-150 (dark)", "model": MODEL_DIR + "sheriff_pickup.glb", "mass": 2400.0, "traffic": false,
		"tail_scale": 0.55, "colors": {"Paint": Color("0b0c10"), "Band": Color("0b0c10")}}))
	register_type(&"patrol_sedan", police.merged({
		"name": "Crusader patrol sedan", "model": MODEL_DIR + "patrol_sedan.glb", "mass": 1900.0, "traffic": false}))
	register_type(&"patrol_sedan_unmarked", police.merged({
		"name": "Crusader unmarked", "model": MODEL_DIR + "patrol_sedan_unmarked.glb", "mass": 1900.0, "traffic": false}))
	register_type(&"patrol_suv", police.merged({
		"name": "General patrol SUV", "model": MODEL_DIR + "patrol_suv.glb", "mass": 2300.0, "traffic": false}))
	register_type(&"patrol_suv_214", police.merged({
		"name": "General sheriff SUV (214)", "model": MODEL_DIR + "patrol_suv_214.glb", "mass": 2300.0, "traffic": false}))
	register_type(&"ranger_suv", {
		"name": "Halvorsen Ranger SUV", "model": MODEL_DIR + "ranger_suv.glb", "mass": 2200.0, "accel_mph_s": 7.5,
		"top_mph": 100.0, "brake_mph_s": 24.0, "traffic": true, "weight": 2.0,
		"colors": {"Paint": Color("68796c"), "Band": Color("68796c"), "Roof": Color("14151a")}})
	register_type(&"ranger_suv_wood", {
		"name": "Halvorsen Ranger SUV (wood)", "model": MODEL_DIR + "ranger_suv.glb", "mass": 2200.0,
		"accel_mph_s": 11.0, "top_mph": 118.0, "brake_mph_s": 24.0, "traffic": false,
		"colors": {"Paint": Color("c9a24a"), "Band": Color("6a4a2c"), "Roof": Color("c9a24a")}})
	register_type(&"civ_sedan", {"name": "Sedan", "model": MODEL_DIR + "civ_sedan.glb", "mass": 1500.0,
		"accel_mph_s": 8.0, "top_mph": 105.0, "brake_mph_s": 26.0, "traffic": true, "weight": 4.0})
	register_type(&"civ_hatchback", {"name": "Arden Compact", "model": MODEL_DIR + "civ_hatchback.glb", "mass": 1150.0,
		"accel_mph_s": 7.5, "top_mph": 98.0, "brake_mph_s": 26.0, "traffic": true, "weight": 3.0})
	register_type(&"civ_pickup", {"name": "Pickup", "model": MODEL_DIR + "civ_pickup.glb", "mass": 2100.0,
		"accel_mph_s": 7.0, "top_mph": 100.0, "brake_mph_s": 24.0, "traffic": true, "weight": 2.0})
	register_type(&"civ_wagon", {"name": "Station wagon", "model": MODEL_DIR + "civ_wagon.glb", "mass": 1700.0,
		"accel_mph_s": 7.0, "top_mph": 98.0, "brake_mph_s": 25.0, "traffic": true, "weight": 2.0,
		"colors": {"Paint": Color("6c7178")}})
	register_type(&"civ_van", {"name": "Van", "model": MODEL_DIR + "civ_van.glb", "mass": 2400.0,
		"accel_mph_s": 5.5, "top_mph": 90.0, "brake_mph_s": 22.0, "traffic": true, "weight": 1.0})
	register_type(&"civ_boxtruck", {"name": "Box truck", "model": MODEL_DIR + "civ_boxtruck.glb", "mass": 4200.0,
		"accel_mph_s": 4.0, "top_mph": 75.0, "brake_mph_s": 18.0, "traffic": true, "weight": 1.0})


func register_type(id: StringName, definition: Dictionary) -> void:
	types[id] = definition


func has_type(id: StringName) -> bool:
	return types.has(id)


func type_ids() -> Array:
	return types.keys()


func traffic_type_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in types:
		if bool(types[id].get("traffic", false)):
			out.append(id)
	return out


## Spawns a vehicle. `xform` is the global transform of the car's ground-level origin (centre of the wheelbase).
## options: plate (String), paint (Color for the "Paint" material), colors (material name -> Color), headlights (bool).
func spawn(type_id: StringName, xform: Transform3D, parent: Node = null, options := {}) -> Vehicle:
	if not types.has(type_id):
		push_error("Vehicles.spawn: unknown type %s" % type_id)
		return null
	var def: Dictionary = (types[type_id] as Dictionary).duplicate(true)
	var colors: Dictionary = (def.get("colors", {}) as Dictionary).duplicate()
	if options.has("paint"):
		colors["Paint"] = options["paint"]
	if options.has("colors"):
		colors.merge(options["colors"], true)
	def["colors"] = colors
	var v := Vehicle.new()
	v.plate = String(options.get("plate", random_plate()))
	_plates[v.plate] = v
	v.setup(type_id, def)
	v.name = "%s_%s" % [type_id, v.plate]
	var host: Node = parent
	if host == null:
		host = get_tree().current_scene if get_tree().current_scene != null else self
	host.add_child(v)
	v.global_transform = xform
	if options.has("headlights"):
		v.set_headlights(bool(options["headlights"]))
	all.append(v)
	v.tree_exited.connect(_on_vehicle_exited.bind(v))
	vehicle_spawned.emit(v)
	return v


func _on_vehicle_exited(v: Vehicle) -> void:
	all.erase(v)
	_plates.erase(v.plate)
	vehicle_removed.emit(v)


## Random civilian vehicle (weighted by "weight") in a random colour; the Ranger keeps its two-tone scheme.
func spawn_traffic(xform: Transform3D, parent: Node = null, type_id: StringName = &"") -> Vehicle:
	var id := type_id if type_id != &"" else random_traffic_type()
	var options := {}
	var pick: Color = CIV_COLORS[_rng.randi() % CIV_COLORS.size()]
	if id == &"ranger_suv":
		options["paint"] = pick
		options["colors"] = {"Band": pick}
	elif id != &"civ_boxtruck":
		options["paint"] = pick
	return spawn(id, xform, parent, options)


func random_traffic_type() -> StringName:
	var ids := traffic_type_ids()
	var total := 0.0
	for id in ids:
		total += float(types[id].get("weight", 1.0))
	var r := _rng.randf() * total
	for id in ids:
		r -= float(types[id].get("weight", 1.0))
		if r <= 0.0:
			return id
	return ids[0]


## Plate format: three letters, dash, four digits (e.g. TAY-6023). Unique among live vehicles.
func random_plate() -> String:
	var letters := "ABCDEFGHJKLMNPRSTVWXYZ"
	for _try in 50:
		var p := "%s%s%s-%04d" % [letters[_rng.randi() % letters.length()], letters[_rng.randi() % letters.length()],
			letters[_rng.randi() % letters.length()], _rng.randi() % 10000]
		if not _plates.has(p):
			return p
	return "XXX-0000"


## Called by Vehicle.set_plate to keep the plate lookup in step.
func update_plate(v: Vehicle, old_plate: String) -> void:
	if _plates.get(old_plate) == v:
		_plates.erase(old_plate)
	_plates[v.plate] = v


func find_by_plate(p: String) -> Vehicle:
	var v: Variant = _plates.get(p.to_upper())
	return v as Vehicle if is_instance_valid(v) else null


# --- persistent skid marks (ring buffer MultiMesh) -------------------------------------------

func add_skid(from: Vector3, to: Vector3) -> void:
	if _skid_mm == null:
		_make_skid_layer()
	var d := to - from
	var length := d.length()
	if length < 0.05:
		return
	var z := d / length
	var x := z.cross(Vector3.UP).normalized()
	var b := Basis(x * 0.2, Vector3.UP, z * (length + 0.05))
	_skid_mm.set_instance_transform(_skid_index, Transform3D(b, (from + to) * 0.5 + Vector3(0, 0.02, 0)))
	_skid_index = (_skid_index + 1) % SKID_CAPACITY


func _make_skid_layer() -> void:
	_skid_mm = MultiMesh.new()
	_skid_mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.025, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	_skid_mm.mesh = quad
	_skid_mm.instance_count = SKID_CAPACITY
	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -100, 0))
	for i in SKID_CAPACITY:
		_skid_mm.set_instance_transform(i, hidden)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SkidMarks"
	mmi.multimesh = _skid_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 4000.0
	var host: Node = skid_parent if skid_parent != null else self
	host.add_child(mmi)
