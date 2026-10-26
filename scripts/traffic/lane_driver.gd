extends RefCounted
## Lane-following AI driver on the road graph. Base of ambient traffic cars and of the suspect driver.
## Works on any vehicle that offers the Vehicle control API (adapters.gd translates: throttle, brake, steering).
## Speeds are m/s internally. Subclasses override the _hooks below.

const Route := preload("res://scripts/traffic/route.gd")
const Registry := preload("res://scripts/traffic/registry.gd")
const Adapters := preload("res://scripts/pursuit/adapters.gd")

const MPH := 0.44704
const STOP_LINE := 7.5       # stop-line distance before the junction centre
const LOOKAHEAD_MIN := 5.0
const STUCK_SECONDS := 3.5

## Fixed seed for repeatable runs (tests set it); 0 = random.
static var seed_base := 0
static var _seed_n := 0

var vehicle: Node3D
var graph: Object
var route: Route
var enabled := true
var s_now := 0.0
var a_brake := 4.5           # planned braking, m/s^2 (real cars brake far less than the pedal rating while turning)
var a_lat := 4.5             # planned lateral acceleration, m/s^2
var headway := 1.1           # follow time gap, s
var min_gap := 4.0           # standstill gap, m
var wheelbase := 2.9
var max_lock := 0.55         # steering lock used to normalise the command, rad
var top_speed := 50.0        # m/s, from the vehicle when it reports one
var shift := 0.0             # lateral offset to the left of the lane, m (overtaking, yielding)
var shift_target := 0.0
var rng := RandomNumberGenerator.new()
var debug_target_speed := 0.0
var debug_brk := 0.0
var debug_thr := 0.0

var _dt := 0.016
var _thr := 0.0
var _stuck := 0.0
var _ignore_follow := 0.0
var _wait_t := 0.0
var _cleared: Dictionary = {}
var _last_steer_target := Vector3.ZERO
var _speed_i := 0.0
var _blocked_t := 0.0
var _recover_t := 0.0
var _recover_n := 0
var recovery_log: Array = []
var recoveries := 0          # stats: times the car was physically blocked and recovered
var stuck_time := 0.0        # stats: seconds spent blocked


func attach(v: Node3D, g: Object) -> void:
	vehicle = v
	graph = g
	if seed_base != 0:
		_seed_n += 1
		rng.seed = seed_base * 1000 + _seed_n
	else:
		rng.randomize()
	var wb: Variant = v.get("wheelbase")
	if typeof(wb) == TYPE_FLOAT and float(wb) > 1.0:
		wheelbase = float(wb)
	var wb2: Variant = v.get("_wheelbase")
	if typeof(wb2) == TYPE_FLOAT and float(wb2) > 1.0:
		wheelbase = float(wb2)
	var top: Variant = v.get("top_ms")
	if typeof(top) == TYPE_FLOAT and float(top) > 10.0:
		top_speed = float(top)
	var lock: Variant = v.get("max_lock")
	if typeof(lock) == TYPE_FLOAT and float(lock) > 0.1:
		max_lock = float(lock)


# --- main loop ---------------------------------------------------------------------------------------------------

func update(dt: float) -> void:
	_dt = dt
	if not enabled or vehicle == null or not is_instance_valid(vehicle) or graph == null:
		return
	var pos := vehicle.global_position
	var fwd := -vehicle.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()
	var v := Adapters.speed_ms(vehicle)
	if route == null or route.pts.size() < 2:
		_bootstrap(pos, fwd)
	if route == null or route.pts.size() < 2:
		Adapters.drive(vehicle, 0.35 if v < 8.0 else 0.0, 0.0, 0.0)
		return
	s_now = route.closest_s(pos, s_now)
	if route.last_dist > 30.0:
		_bootstrap(pos, fwd)
		if route == null:
			return
	if route.drop_passed(s_now):
		s_now = route.closest_s(pos, 0.0, true)
	_extend()
	_update_shift(dt, pos, fwd, v)
	shift = move_toward(shift, shift_target, 2.2 * dt)
	var vt := _target_speed(pos, fwd, v)
	debug_target_speed = vt
	var steer := _steer(pos, fwd, v)
	if _recover_t > 0.0:
		_recover_t -= dt
		Adapters.drive(vehicle, -0.8, 0.0, -steer)
		return
	if _blocked_t > STUCK_SECONDS:
		_blocked_t = 0.0
		_recover(pos)
		return
	if vt > 3.0 and v < 0.4:
		stuck_time += dt
	_blocked_t = _blocked_t + dt if (vt > 3.0 and v < 0.4) else maxf(_blocked_t - dt, 0.0)
	_control(v, vt, steer, dt)


## Physically blocked (curb, pole, another car): reverse out twice, then put the car back on the lane.
func _recover(pos: Vector3) -> void:
	recoveries += 1
	recovery_log.append({"pos": pos, "edge": String(current_edge().get("name", "?")), "s": s_now, "left": route.remaining(s_now), "nodes": route.upcoming_nodes(s_now, 30.0).size()})
	_recover_n += 1
	if _recover_n <= 2 and vehicle.get("reverse_ms2") != null:
		_recover_t = 1.6
		return
	_recover_n = 0
	var at := route.pos_at(s_now + 7.0) + Vector3(0, 0.45, 0)
	var dir := route.dir_at(s_now + 7.0)
	Adapters.teleport(vehicle, Transform3D(Basis.looking_at(dir, Vector3.UP), at))
	_thr = 0.0
	s_now = route.closest_s(at, s_now)
	if pos.distance_to(at) < 0.1:
		return


func current_edge() -> Dictionary:
	if route == null or route.legs.is_empty():
		return {}
	return route.legs[route.current_leg(s_now)].edge


func reset_route() -> void:
	route = null
	_cleared.clear()


# --- route -------------------------------------------------------------------------------------------------------

func _bootstrap(pos: Vector3, fwd: Vector3) -> void:
	route = null
	var near: Dictionary = graph.nearest_edge(pos)
	if near.is_empty():
		return
	var edge: Dictionary = near.edge
	if float(near.dist) > float(edge.width) * 0.5 + 28.0:
		return
	var along: Dictionary = graph.point_on_edge(edge, float(near.t) * float(edge.length))
	var forward := (along.dir as Vector3).dot(fwd) >= 0.0
	if bool(edge.get("oneway", false)):
		forward = true
	route = Route.new()
	route.legs.append(Route.make_leg(edge, forward, _pick_lane(edge)))
	route.rebuild()
	_extend()
	s_now = route.closest_s(pos, 0.0, true)
	_cleared.clear()


func _extend() -> void:
	var guard := 0
	while (route.remaining(s_now) < 260.0 or route.legs.size() < 3) and guard < 6:
		guard += 1
		var next_leg := _choose_next(route.legs[route.legs.size() - 1])
		if next_leg.is_empty():
			break
		route.add_leg(next_leg)


func _pick_lane(edge: Dictionary) -> int:
	return maxi(int(edge.lanes) - 1, 0)


## Weight of continuing onto `edge` from the arrival heading; 0 = never. Subclasses scale it.
func _edge_weight(_edge: Dictionary, _node_id: StringName, base: float) -> float:
	return base


func _choose_next(prev: Dictionary) -> Dictionary:
	var node_id: StringName = prev.to
	var arrive: Vector3 = -(graph.direction_from(prev.edge, node_id) as Vector3)
	var options: Array = []
	var weights: Array[float] = []
	var total := 0.0
	for n: Dictionary in graph.neighbors(node_id):
		var edge: Dictionary = n.edge
		if int(edge.id) == int(prev.edge.id):
			continue
		var out_dir: Vector3 = graph.direction_from(edge, node_id)
		var d := arrive.dot(out_dir)
		var w := 0.0
		if d > 0.85:
			w = 3.0
		elif d > 0.3:
			w = 1.4
		elif d > -0.3:
			w = 1.6
		w = _edge_weight(edge, node_id, w)
		if w <= 0.0:
			continue
		options.append(Route.make_leg(edge, edge.a == node_id, _pick_lane(edge)))
		weights.append(w)
		total += w
	if options.is_empty():
		# dead end: turn around
		for n: Dictionary in graph.neighbors(node_id):
			return Route.make_leg(n.edge, n.edge.a == node_id, _pick_lane(n.edge))
		return {}
	var r := rng.randf() * total
	for i in options.size():
		r -= weights[i]
		if r <= 0.0:
			return options[i]
	return options[options.size() - 1]


# --- speed planning ----------------------------------------------------------------------------------------------

## Speed cap of the current road in m/s (before curves, junctions and traffic).
func _speed_cap() -> float:
	var edge := current_edge()
	return float(edge.get("limit_mph", 25)) * MPH if not edge.is_empty() else 10.0


## Junction rule for an upcoming node: {stop: bool, v: float} (v < 0 = no limit).
func _node_rule(n: Dictionary, v: float) -> Dictionary:
	var res := {"stop": false, "v": -1.0}
	var node: Dictionary = graph.nodes[n.node]
	var control: String = String(node.control)
	if control == "none":
		return res
	var key: StringName = n.node
	if _cleared.has(key):
		return res
	var ds: float = float(n.dist) - STOP_LINE
	var must_stop := false
	var dir: Vector3 = route.dir_at(s_now + float(n.dist) - 4.0)
	match control:
		"signal":
			var st := Adapters.signal_state(key, dir)
			if st == &"red":
				must_stop = true
			elif st == &"yellow":
				must_stop = ds > v * v / (2.0 * 3.5) + 2.0
		"all_way":
			must_stop = true
		"minor_stop":
			must_stop = _is_minor(n)
	if not must_stop:
		return res
	res.stop = true
	if control != "signal" and ds < 1.6 and v < 0.7:
		_wait_t += _dt
		var pos3: Vector3 = (graph.nodes[key].pos as Vector3)
		var clear := not Registry.occupied(pos3, 5.5, vehicle) and not Registry.reserved_by_other(key, vehicle)
		if (_wait_t >= 1.2 and clear) or _wait_t > 9.0:
			_cleared[key] = true
			Registry.reserve(key, vehicle, 3.0)
			_wait_t = 0.0
			res.stop = false
	return res


func _is_minor(n: Dictionary) -> bool:
	var node: Dictionary = graph.nodes[n.node]
	var mine := _edge_priority(n.arrive.edge)
	var best := 0
	for eid: int in node.edges:
		best = maxi(best, _edge_priority(graph.edges[eid]))
	return mine < best


func _edge_priority(edge: Dictionary) -> int:
	var rank := {"highway": 5, "arterial": 4, "rural": 3, "industrial": 2, "residential": 2, "ramp": 2, "lot": 1}
	return int(rank.get(String(edge.kind), 2)) * 100 + int(edge.limit_mph)


func _target_speed(pos: Vector3, fwd: Vector3, v: float) -> float:
	var t := minf(_speed_cap(), top_speed * 0.97)
	var horizon := maxf(80.0, v * v / (2.0 * a_brake) + 45.0)
	t = minf(t, route.curve_limit(s_now, horizon, a_lat, a_brake))
	if route.last_dist > 4.0:
		t = minf(t, 9.0)   # off the lane (slid wide, curb): crawl back instead of ploughing on
	var seen := {}
	for n: Dictionary in route.upcoming_nodes(s_now, horizon):
		seen[n.node] = true
		var rule := _node_rule(n, v)
		if rule.stop:
			t = minf(t, sqrt(2.0 * a_brake * 0.8 * maxf(float(n.dist) - STOP_LINE - 0.4, 0.0)))
		elif float(rule.v) >= 0.0:
			t = minf(t, sqrt(float(rule.v) * float(rule.v) + 2.0 * a_brake * maxf(float(n.dist), 0.0)))
	for k: StringName in _cleared.keys():
		if not seen.has(k):
			_cleared.erase(k)
			Registry.release(k, vehicle)
	if _ignore_follow <= 0.0:
		t = minf(t, _follow_limit(fwd, v))
	else:
		_ignore_follow -= _dt
	# stuck detection: wanting to move but not moving
	if t > 3.0 and v < 0.4:
		_stuck += _dt
		if _stuck > 7.0:
			_ignore_follow = 2.0
			_stuck = 0.0
	else:
		_stuck = maxf(_stuck - _dt, 0.0)
	return maxf(t, 0.0)


func _follow_limit(fwd: Vector3, v: float) -> float:
	var h := Registry.nearest_ahead(vehicle, fwd, maxf(35.0, v * 3.5), -shift, 2.1)
	if not bool(h.found):
		return 1000.0
	var gap: float = h.gap
	if gap < 0.4:
		return 0.0
	var other_v: float = maxf(float(h.speed), 0.0)
	var desired := min_gap + v * headway
	var envelope := sqrt(other_v * other_v + 2.0 * a_brake * maxf(gap - min_gap, 0.0))
	return maxf(minf(envelope, other_v + (gap - desired) * 0.6), 0.0)


func _update_shift(_dt_: float, _pos: Vector3, _fwd: Vector3, _v: float) -> void:
	shift_target = 0.0


# --- control -----------------------------------------------------------------------------------------------------

func _steer(pos: Vector3, fwd: Vector3, v: float) -> float:
	var ld := clampf(v * 0.4 + 4.0, 4.0, 26.0)
	var ts := s_now + ld
	var tp := route.pos_at(ts)
	if absf(shift) > 0.01:
		var td := route.dir_at(ts)
		tp -= td.cross(Vector3.UP).normalized() * shift
	_last_steer_target = tp
	var to_t := tp - pos
	to_t.y = 0.0
	var dist := maxf(to_t.length(), 0.1)
	var cr := fwd.cross(to_t)
	var alpha := atan2(cr.y, fwd.dot(to_t))
	var angle := atan(2.0 * wheelbase * sin(alpha) / dist)
	var lock := max_lock / (1.0 + pow(v / 24.0, 2.0))
	return clampf(angle / maxf(lock, 0.05), -1.0, 1.0)


func _control(v: float, vt: float, steer_left: float, dt: float) -> void:
	var err := vt - v
	var thr := 0.0
	var brk := 0.0
	# integral term removes the steady-state speed error against drag and slopes
	_speed_i = clampf(_speed_i + err * 0.25 * dt, 0.0, 0.7) if vt > 1.0 else 0.0
	if err > 0.1:
		thr = clampf(err * 0.4 + _speed_i, 0.0, 1.0)
	elif err > -0.3 and vt > 1.0:
		thr = clampf(_speed_i * 0.5, 0.0, 1.0)
	elif err < -0.5:
		brk = clampf((-err - 0.2) * 0.6, 0.0, 1.0)
	if vt < 0.25 and v < 1.2:
		brk = 1.0
		thr = 0.0
	_thr = move_toward(_thr, thr, 3.5 * dt)
	debug_brk = brk
	debug_thr = _thr
	Adapters.drive(vehicle, _thr, brk, steer_left, _last_steer_target)
