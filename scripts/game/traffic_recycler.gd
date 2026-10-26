extends Node
## Keeps the ambient traffic alive without building vehicles while the game runs. Traffic frees a car 340 m away and builds a new one
## (Vehicles.spawn_traffic: model instance, wheels, convex hull, lights: about 15 ms between the call and the first physics frame),
## which showed as a frame-time spike about once a second at driving speed. Here the initial cars are taken over (Traffic no longer frees
## or spawns them) and a car that is far away and out of sight is moved to a free lane spot around the player instead:
## new plate, same model. Cars of calls, stops and pursuits are left alone.
## Module request (docs/api/game.md): Traffic.recycle_far_cars() and Vehicle.set_plate().

const Registry := preload("res://scripts/traffic/registry.gd")
const Route := preload("res://scripts/traffic/route.gd")

const PERIOD := 0.4
const FAR := 340.0               # m, same as Traffic.despawn_distance
const RING_MIN := 90.0           # m, same ring as Traffic's spawns
const RING_MAX := 240.0
const FORGET_META: Array[StringName] = [&"alpr_checked", &"violation", &"mdt_record", &"flees", &"alpr_force", &"call_id", &"stop_ignore", &"stop_hold"]

var focus: Node3D                ## the player (the ring is drawn around it)
var cars: Array = []             ## TrafficCar drivers that are recycled
var recycled := 0                ## count, for tests and the report

var _timer := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## Takes over the cars Traffic has just spawned: Traffic stops freeing them and stops building replacements.
func adopt_ambient() -> void:
	for driver in Traffic.cars:
		if bool(driver.owned):
			driver.set("owned", false)
			cars.append(driver)
	Traffic.ambient_target = 0


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or focus == null or not World.is_built:
		return
	_timer = PERIOD
	for i in range(cars.size() - 1, -1, -1):
		var driver: RefCounted = cars[i]
		var v: Variant = driver.get("vehicle")
		if not is_instance_valid(v):
			cars.remove_at(i)
			continue
		if _recyclable(v as Vehicle) and _recycle(driver, v as Vehicle):
			return   # one car per tick: the work is spread over frames


func _recyclable(v: Vehicle) -> bool:
	if v.has_meta("stop_hold") or v.has_meta("call_id") or v == TrafficStop.vehicle or v == Pursuit.target:
		return false
	if not Traffic.is_managed(v):
		return false   # Pursuit released it
	var d := v.global_position - focus.global_position
	d.y = 0.0
	return d.length() > FAR and not _in_view(v.global_position)


func _in_view(pos: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.is_position_in_frustum(pos)


## Moves the car to a free lane spot in the ring around the focus. false when no spot was found this time.
func _recycle(driver: RefCounted, v: Vehicle) -> bool:
	var graph: RoadGraph = World.road_graph
	var origin := focus.global_position
	for _attempt in 14:
		var edge: Dictionary = Traffic._pick_edge(graph)
		if edge.is_empty() or float(edge["length"]) < 30.0:
			continue
		var forward := true if bool(edge["oneway"]) else _rng.randf() < 0.5
		var s := _rng.randf_range(12.0, float(edge["length"]) - 12.0)
		var lane := _rng.randi() % maxi(int(edge["lanes"]), 1)
		var pt: Dictionary = graph.point_on_edge(edge, s)
		var dir: Vector3 = pt["dir"] if forward else -(pt["dir"] as Vector3)
		var pos: Vector3 = (pt["pos"] as Vector3) + dir.cross(Vector3.UP) * Route.lane_offset(edge, lane) + Vector3(0.0, 0.45, 0.0)
		var d := Vector2(pos.x - origin.x, pos.z - origin.z).length()
		if d < RING_MIN or d > RING_MAX or _in_view(pos) or Registry.occupied(pos, 10.0, v):
			continue
		v.teleport(Transform3D(Basis.looking_at(dir, Vector3.UP), pos))
		v.linear_velocity = dir * float(edge["limit_mph"]) * 0.44704 * 0.8
		v.set_handbrake(false)
		for meta_name in FORGET_META:
			if v.has_meta(meta_name):
				v.remove_meta(meta_name)
		_replate(v)
		driver.set("route", null)
		driver.set("s_now", 0.0)
		driver.set("pull_over_cmd", false)
		driver.set("enabled", true)
		recycled += 1
		return true
	return false


## A new plate, so the same car does not hit the plate reader twice under one number.
func _replate(v: Vehicle) -> void:
	var plate: String = Vehicles.random_plate()
	var plates: Variant = Vehicles.get("_plates")
	if plates is Dictionary:
		(plates as Dictionary).erase(v.plate)
		(plates as Dictionary)[plate] = v
	v.plate = plate
	for node_name in ["Plate_Rear", "Plate_Front"]:
		var label := v.model.get_node_or_null(node_name + "/PlateText") as Label3D
		if label != null:
			label.text = plate


## Removes every recycled car (screenshots without traffic).
func clear() -> void:
	for driver in cars:
		var v: Variant = driver.get("vehicle")
		if is_instance_valid(v):
			Traffic.release(v as Node3D)
			Registry.remove(v as Node3D)
			(v as Node).queue_free()
	cars.clear()
