extends "res://scripts/traffic/lane_driver.gd"
## Fleeing driver: starts at city speeds (20-30 mph), slows at junctions and bends,
## mixes with traffic (follows or overtakes through the oncoming lane), then escalates towards 100+ mph on
## rural roads and highways. Eases off when the player is more than 460 ft behind.

## TODO(tahmin): escalation timing (city speeds for about 20 s, 90+ mph on the beltway 10-25 s later).
const ESC_START := 14.0
const ESC_RAMP := 30.0
const GAP_CAP_FT := 460.0
const KIND_K := {"residential": 0.5, "industrial": 0.6, "arterial": 0.7, "ramp": 0.5, "rural": 1.2, "highway": 0.72, "lot": 0.3}

var player: Node3D
var t_since := 0.0
var escalation := 0.0
var max_speed_ms := 110.0 * MPH
var speed_override_mph := -1.0   # scripted: fixed target speed (scenarios)
var blocked_edges: Dictionary = {}
var wobble := 1.0

var _wobble_t := 0.0
var _overtake_t := 0.0
var _overtake_cd := 0.0


func attach(v: Node3D, g: Object) -> void:
	super.attach(v, g)
	headway = 0.4
	min_gap = 3.2
	a_brake = 5.0
	a_lat = 6.0
	max_speed_ms = minf(max_speed_ms, top_speed * 0.96)


func update(dt: float) -> void:
	t_since += dt
	escalation = clampf((t_since - ESC_START) / ESC_RAMP, 0.0, 1.0)
	_wobble_t -= dt
	if _wobble_t <= 0.0:
		wobble = rng.randf_range(0.93, 1.05)
		_wobble_t = rng.randf_range(4.0, 9.0)
	_overtake_cd = maxf(_overtake_cd - dt, 0.0)
	super.update(dt)


func _speed_cap() -> float:
	if speed_override_mph >= 0.0:
		return speed_override_mph * MPH
	var edge := current_edge()
	if edge.is_empty():
		return 12.0
	var limit := float(edge.limit_mph)
	var k: float = KIND_K.get(String(edge.kind), 0.6)
	var cap := limit * 0.95 * (1.0 + k * escalation) * MPH
	if escalation > 0.3:
		cap *= wobble
	cap = minf(cap, max_speed_ms)
	if player != null and is_instance_valid(player):
		var d := vehicle.global_position - player.global_position
		d.y = 0.0
		if d.length() > GAP_CAP_FT * 0.3048:
			cap = minf(cap, maxf(Adapters.speed_ms(player) + 4.0, 12.0))
	return cap


func _edge_weight(edge: Dictionary, node_id: StringName, base: float) -> float:
	if blocked_edges.has(int(edge.id)):
		return base * 0.02
	var far: StringName = edge.b if edge.a == node_id else edge.a
	if (graph.nodes[far].edges as Array).size() <= 1:
		base *= 0.1
	return base * (1.0 + escalation * float(edge.limit_mph) / 35.0)


## The suspect does not obey signs: it rolls through controlled junctions at about 20 mph and brakes only for
## cross traffic that is about to enter.
func _node_rule(n: Dictionary, _v: float) -> Dictionary:
	var node: Dictionary = graph.nodes[n.node]
	if String(node.control) == "none":
		return {"stop": false, "v": -1.0}
	var centre: Vector3 = node.pos
	var cap := 9.0
	if Registry.cross_threat(centre, 45.0, vehicle):
		cap = 2.5
	return {"stop": false, "v": cap}


func _update_shift(dt: float, _pos: Vector3, fwd: Vector3, v: float) -> void:
	var edge := current_edge()
	if edge.is_empty():
		shift_target = 0.0
		return
	var lane_w := Route.lane_width(edge)
	if absf(shift_target) < 0.1:
		var b := Registry.nearest_ahead(vehicle, fwd, 50.0, -shift, 2.0)
		if bool(b.found) and _overtake_cd <= 0.0 and float(b.gap) < maxf(14.0, v * 1.5) and float(b.speed) < v - 3.0:
			if Registry.lane_free(vehicle, fwd, -lane_w, 12.0, 80.0 + v * 2.0):
				shift_target = lane_w
				_overtake_t = 4.0
	else:
		_overtake_t -= dt
		var head_on := Registry.nearest_ahead(vehicle, fwd, 70.0, -shift, 2.0)
		var abort := bool(head_on.found) and float(head_on.speed) < -2.0 and float(head_on.gap) < 60.0
		if abort or _overtake_t <= 0.0 or Registry.lane_free(vehicle, fwd, 0.0, 9.0, 16.0):
			if _overtake_t < 3.2 or abort:
				shift_target = 0.0
				_overtake_cd = 2.5
