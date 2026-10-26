extends "res://scripts/pursuit/suspect_driver.gd"
## Bot that drives a pursuing car along the suspect's route (test scene, AI patrol units).
## FOLLOW keeps a gap, PIT lines the front corner up on the suspect's rear corner, STOP brakes.

enum Mode { FOLLOW, PIT, STOP }

var mode: int = Mode.FOLLOW
var target: Node3D                 # the suspect's vehicle
var target_driver: RefCounted      # its LaneDriver (route source)
var gap := 16.0                    # FOLLOW: centre-to-centre distance, m
var pit_side := 1.0                # +1: line up on the suspect's right rear, -1: left rear
var max_speed := 48.0              # m/s


func attach(v: Node3D, g: Object) -> void:
	super.attach(v, g)
	headway = 0.3
	min_gap = 2.5
	a_brake = 5.0


func update(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	super.update(dt)


func _flat_gap() -> float:
	var d := target.global_position - vehicle.global_position
	d.y = 0.0
	return d.length()


func _speed_cap() -> float:
	var tv := Adapters.speed_ms(target)
	match mode:
		Mode.FOLLOW:
			return clampf(tv + (_flat_gap() - gap) * 0.6, 0.0, max_speed)
		Mode.PIT:
			var hs := Adapters.half_size(target)
			var hp := Adapters.half_size(vehicle)
			var d := _flat_gap()
			return clampf(tv + clampf((d - (0.85 * hs.y + hp.y)) * 0.5, -3.0, 2.0), 0.0, max_speed)
	return 0.0


func _update_shift(_dt_: float, _pos: Vector3, _fwd: Vector3, _v: float) -> void:
	shift_target = 0.0
	if mode == Mode.PIT and target_driver != null:
		var hs := Adapters.half_size(target)
		var hp := Adapters.half_size(vehicle)
		shift_target = float(target_driver.get("shift")) - pit_side * (hs.x + hp.x - 0.15)


func _follow_limit(fwd: Vector3, v: float) -> float:
	if mode == Mode.PIT and _flat_gap() < 18.0:
		return 1000.0
	return super._follow_limit(fwd, v)


## Same legs as the suspect (own lane), so the bot drives the suspect's roads instead of cutting corners.
func _extend() -> void:
	if target_driver == null or target_driver.get("route") == null:
		super._extend()
		return
	var their: Array = (target_driver.get("route") as RefCounted).get("legs")
	if their.is_empty():
		super._extend()
		return
	var mine: Array = route.legs
	var last: Dictionary = mine[mine.size() - 1]
	var idx := -1
	for i in their.size():
		if their[i].edge.id == last.edge.id and their[i].fwd == last.fwd:
			idx = i
	if idx < 0:
		# off the suspect's route: re-plan from the suspect's current roads
		route.legs = []
		for leg: Dictionary in their.slice(maxi(their.size() - 3, 0)):
			route.legs.append(Route.make_leg(leg.edge, leg.fwd, _pick_lane(leg.edge)))
		route.rebuild()
		s_now = route.closest_s(vehicle.global_position, 0.0, true)
		return
	var added := false
	for j in range(idx + 1, their.size()):
		route.legs.append(Route.make_leg(their[j].edge, their[j].fwd, _pick_lane(their[j].edge)))
		added = true
	if added:
		route.rebuild()
