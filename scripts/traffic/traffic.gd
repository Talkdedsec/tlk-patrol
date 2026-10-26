extends Node
## Traffic autoload: ambient civilian cars on the road graph (lane keeping, signals, stop signs, limits, siren yield).
## API: docs/api/traffic.md. Reads World.road_graph through scripts/pursuit/adapters.gd.

const TrafficCar := preload("res://scripts/traffic/traffic_car.gd")
const Registry := preload("res://scripts/traffic/registry.gd")
const Route := preload("res://scripts/traffic/route.gd")
const Adapters := preload("res://scripts/pursuit/adapters.gd")

signal car_spawned(vehicle: Node3D)
signal car_despawned(vehicle: Node3D)

var enabled := true
var max_cars := 40
var spawn_min := 90.0            # ring (m) around the focus where new cars appear
var spawn_max := 240.0
var despawn_distance := 340.0
var focus_node: Node3D           # usually the player's vehicle (Pursuit sets it); falls back to the officer / camera
var siren_source: Node3D         # vehicle whose siren traffic yields to
var ambient_target := 0
## What happens to an ambient car that is far away and out of sight: &"free" (free it, a new one is built later) or
## &"recycle" (move it to a free lane spot in the ring around the focus: no model/physics build, no frame spike).
var despawn_mode: StringName = &"free"
var recycled := 0                # count of recycled cars (tests, reports)
var cars: Array = []             # TrafficCar drivers (ambient and adopted)
var zones: Array = []            # [{pos, radius, mode}] mode: slow | closed

var _rng := RandomNumberGenerator.new()
var _spawn_t := 0.0
var _edge_weights: Array[float] = []
var _edge_total := 0.0
var _graph_id := 0


func _ready() -> void:
	_rng.randomize()


## Density 0..1 of max_cars.
func set_density(d: float) -> void:
	ambient_target = roundi(clampf(d, 0.0, 1.0) * float(max_cars))


func density() -> float:
	return float(ambient_target) / float(maxi(max_cars, 1))


## Fills the network with `count` ambient cars right now (and keeps that many afterwards). Returns the spawned count.
func spawn_ambient(count: int) -> int:
	ambient_target = clampi(count, 0, max_cars)
	var made := 0
	var guard := 0
	while _owned_count() < ambient_target and guard < ambient_target * 4:
		guard += 1
		if _spawn_one(false) != null:
			made += 1
	return made


## Frees every ambient car, except cars somebody has taken over (held for a stop, pulled over, owned = false).
func clear() -> void:
	ambient_target = 0
	for c in cars.duplicate():
		if bool(c.owned) and not _is_protected(c):
			_remove_car(c, true)


## Takes over an existing vehicle with the traffic driver (e.g. a lost suspect, a scripted car).
func adopt(vehicle: Node3D, owned := false) -> RefCounted:
	var existing := _driver_of(vehicle)
	if existing != null:
		return existing
	var g := Adapters.graph()
	if g == null:
		return null
	var car := TrafficCar.new()
	car.attach(vehicle, g)
	car.owned = owned
	car.zone_cap = Callable(self, "_zone_cap")
	cars.append(car)
	Registry.add(vehicle, &"civil")
	return car


## Stops the traffic driver on a vehicle (keeps the vehicle).
func release(vehicle: Node3D) -> void:
	var c := _driver_of(vehicle)
	if c != null:
		cars.erase(c)


func is_managed(vehicle: Node3D) -> bool:
	return _driver_of(vehicle) != null


## Traffic stop: the traffic driver leaves the car alone (TrafficStop adapters call these two).
func hold_vehicle(vehicle: Node3D) -> void:
	var c := _driver_of(vehicle)
	if c != null:
		c.enabled = false
		c.protected = true
	Adapters.park(vehicle)


func release_vehicle(vehicle: Node3D) -> void:
	if vehicle.has_method("set_handbrake"):
		vehicle.call("set_handbrake", false)
	var c := _driver_of(vehicle)
	if c != null:
		c.enabled = true
		c.pull_over_cmd = false
		c.protected = false


## The driver signals right and stops at the road edge.
func pull_over(vehicle: Node3D) -> void:
	var c := _driver_of(vehicle)
	if c == null:
		c = adopt(vehicle)
	if c != null:
		c.pull_over_cmd = true
		c.protected = true


## Slow-down / closure around a point (flares, road closed). mode: &"slow" (about 10 mph) or &"closed" (stop short).
func set_zone(position: Vector3, radius: float, mode: Variant = &"slow") -> void:
	zones.append({"pos": position, "radius": radius, "mode": StringName(String(mode))})


func clear_zones() -> void:
	zones.clear()


func limit_at(position: Vector3) -> int:
	return int(Adapters.street_at(position).limit_mph)


func _zone_cap(pos: Vector3) -> float:
	var cap := INF
	for z: Dictionary in zones:
		var d := pos.distance_to(z.pos as Vector3)
		if z.mode == &"closed":
			if d < float(z.radius) + 25.0:
				cap = minf(cap, maxf(sqrt(2.0 * 4.0 * maxf(d - float(z.radius) - 4.0, 0.0)), 0.0))
		elif d < float(z.radius) + 20.0:
			cap = minf(cap, 4.5)
	return cap


## True for cars that must not be freed or moved: held for a stop, pulled over, or carrying a stop/call meta.
func is_protected(vehicle: Node3D) -> bool:
	var c := _driver_of(vehicle)
	return c != null and _is_protected(c)


func _is_protected(c: RefCounted) -> bool:
	var v: Node3D = c.vehicle
	if v == null or not is_instance_valid(v):
		return false
	return bool(c.protected) or not bool(c.enabled) or bool(c.pull_over_cmd) \
		or bool(v.get_meta("stop_hold", false)) or v.has_meta("call_id")


## Moves far-away, out-of-sight ambient cars to free lane spots around the focus (at most `max_moves` per call) instead of
## freeing them. Protected cars (held, pulled over, suspect) stay. Returns how many cars were moved.
func recycle_far_cars(max_moves := 1, min_distance := -1.0) -> int:
	var focus := _focus()
	var far := despawn_distance if min_distance < 0.0 else min_distance
	var moved := 0
	for c in cars.duplicate():
		if moved >= max_moves:
			break
		if not bool(c.owned) or _is_protected(c) or c.vehicle == null or not is_instance_valid(c.vehicle):
			continue
		var pos: Vector3 = c.vehicle.global_position
		var dist := pos.distance_to(focus)
		if dist < far or _in_view(pos, dist):
			continue
		if _recycle_car(c, focus):
			moved += 1
	return moved


func _recycle_car(c: RefCounted, focus: Vector3) -> bool:
	var spot := {}
	for _try in 3:
		spot = _find_spot(focus, true)
		if not spot.is_empty():
			break
	if spot.is_empty():
		return false
	var v: Node3D = c.vehicle
	Adapters.teleport(v, spot.xf)
	Adapters.set_velocity(v, Vector3.ZERO)
	Adapters.set_velocity(v, (spot.dir as Vector3) * float(spot.limit) * 0.44704 * 0.8)
	c.reset_route()
	recycled += 1
	return true


func _driver_of(vehicle: Node3D) -> RefCounted:
	for c in cars:
		if c.vehicle == vehicle:
			return c
	return null


func _owned_count() -> int:
	var n := 0
	for c in cars:
		if bool(c.owned):
			n += 1
	return n


func _focus() -> Vector3:
	if focus_node != null and is_instance_valid(focus_node):
		return focus_node.global_position
	return Adapters.focus_position()


func _physics_process(dt: float) -> void:
	if not enabled:
		return
	for i in range(cars.size() - 1, -1, -1):
		var c = cars[i]
		if c.vehicle == null or not is_instance_valid(c.vehicle):
			cars.remove_at(i)
			continue
		if bool(c.vehicle.get_meta("stop_hold", false)):
			continue
		c.siren_source = siren_source
		c.update(dt)
	Registry.prune()
	_spawn_t -= dt
	if _spawn_t > 0.0:
		return
	_spawn_t = 0.5
	var focus := _focus()
	if despawn_mode == &"recycle":
		recycle_far_cars(1)
	else:
		for c in cars.duplicate():
			if bool(c.owned) and not _is_protected(c) and _should_despawn(c, focus):
				_remove_car(c, true)
	if _owned_count() < ambient_target:
		_spawn_one(true)


func _should_despawn(c: RefCounted, focus: Vector3) -> bool:
	var pos: Vector3 = c.vehicle.global_position
	var dist := pos.distance_to(focus)
	if dist < despawn_distance:
		return false
	return not _in_view(pos, dist)


func _remove_car(c: RefCounted, free_vehicle: bool) -> void:
	cars.erase(c)
	var v: Node3D = c.vehicle
	if v != null and is_instance_valid(v):
		Registry.remove(v)
		if free_vehicle:
			car_despawned.emit(v)
			v.queue_free()


func _in_view(pos: Vector3, _dist: float = 0.0) -> bool:
	var cam := Adapters.camera()
	if cam == null or not cam.is_inside_tree():
		return false
	if cam.global_position.distance_to(pos) > 260.0:   # too far to see a car pop: not "in view" for spawn/despawn purposes
		return false
	return cam.is_position_in_frustum(pos)


func _prepare_edges(g: Object) -> void:
	if _graph_id == g.get_instance_id() and not _edge_weights.is_empty():
		return
	_graph_id = g.get_instance_id()
	_edge_weights.clear()
	_edge_total = 0.0
	for e: Dictionary in g.edges:
		var w := 0.0 if String(e.kind) == "lot" else float(e.length)
		_edge_total += w
		_edge_weights.append(_edge_total)


func _pick_edge(g: Object) -> Dictionary:
	_prepare_edges(g)
	if _edge_total <= 0.0:
		return {}
	var r := _rng.randf() * _edge_total
	for i in _edge_weights.size():
		if r <= _edge_weights[i]:
			return g.edges[i]
	return g.edges[g.edges.size() - 1]


## A free lane spot {xf, dir, limit} for a car: inside the spawn ring and out of view when near_focus, else anywhere 40 m+ from the focus.
func _find_spot(focus: Vector3, near_focus: bool) -> Dictionary:
	var g := Adapters.graph()
	if g == null:
		return {}
	for _attempt in 14:
		var edge := _pick_edge(g)
		if edge.is_empty() or float(edge.length) < 30.0:
			continue
		var fwd := true if bool(edge.oneway) else _rng.randf() < 0.5
		var s := _rng.randf_range(12.0, float(edge.length) - 12.0)
		var lanes := maxi(int(edge.lanes), 1)
		var lane := _rng.randi() % lanes
		var pt: Dictionary = g.point_on_edge(edge, s)
		var dir: Vector3 = pt.dir if fwd else -(pt.dir as Vector3)
		var pos: Vector3 = pt.pos + dir.cross(Vector3.UP) * Route.lane_offset(edge, lane) + Vector3(0, 0.45, 0)
		var d := pos.distance_to(focus)
		if near_focus and (d < spawn_min or d > spawn_max):
			continue
		if d < 40.0 or _in_view(pos, d):
			continue
		if Registry.occupied(pos, 10.0, null):
			continue
		return {"xf": Transform3D(Basis.looking_at(dir, Vector3.UP), pos), "dir": dir, "limit": int(edge.limit_mph)}
	return {}


## Places one ambient car; near_focus = inside the spawn ring and out of view.
func _spawn_one(near_focus: bool) -> Node3D:
	var g := Adapters.graph()
	if g == null:
		return null
	var spot := _find_spot(_focus(), near_focus)
	if spot.is_empty():
		return null
	var v := Adapters.spawn_traffic_vehicle(spot.xf)
	if v == null:
		return null
	Adapters.set_velocity(v, (spot.dir as Vector3) * float(spot.limit) * 0.44704 * 0.8)
	var car := TrafficCar.new()
	car.attach(v, g)
	car.owned = true
	car.zone_cap = Callable(self, "_zone_cap")
	cars.append(car)
	Registry.add(v, &"civil")
	car_spawned.emit(v)
	return v
