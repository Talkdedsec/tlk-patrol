extends RefCounted
## Shared list of driven vehicles (ambient traffic, suspect, units, player) for proximity queries,
## plus junction reservations used by the stop-sign logic.

const Adapters := preload("res://scripts/pursuit/adapters.gd")

static var entries: Array = []        # [{node: Node3D, kind: StringName}]
static var reservations: Dictionary = {}  # node id -> {who: Node3D, until: float}


static func add(v: Node3D, kind: StringName = &"civil") -> void:
	for e: Dictionary in entries:
		if e.node == v:
			e.kind = kind
			return
	entries.append({"node": v, "kind": kind})


static func remove(v: Node3D) -> void:
	for i in range(entries.size() - 1, -1, -1):
		if entries[i].node == v:
			entries.remove_at(i)


static func prune() -> void:
	for i in range(entries.size() - 1, -1, -1):
		if not is_instance_valid(entries[i].node):
			entries.remove_at(i)


static func kind_of(v: Node3D) -> StringName:
	for e: Dictionary in entries:
		if e.node == v:
			return e.kind
	return &""


static func now() -> float:
	return float(Engine.get_physics_frames()) / 60.0


## Nearest vehicle ahead of `me` inside a lane window.
## lateral: window centre, metres to the right of my heading line; window: half width.
## Returns {found, gap (bumper to bumper, m), speed (other's speed along my heading, m/s), node}.
static func nearest_ahead(me: Node3D, fwd: Vector3, max_dist: float, lateral: float, window: float) -> Dictionary:
	var right := fwd.cross(Vector3.UP)
	var my_pos := me.global_position
	var my_half := Adapters.half_size(me)
	var best := {"found": false, "gap": INF, "speed": 0.0, "node": null}
	for e: Dictionary in entries:
		var other: Node3D = e.node
		if other == me or not is_instance_valid(other):
			continue
		var r := other.global_position - my_pos
		r.y = 0.0
		var along := r.dot(fwd)
		if along <= 0.0 or along > max_dist + 8.0:
			continue
		if absf(r.dot(right) - lateral) > window:
			continue
		var gap: float = along - my_half.y - Adapters.half_size(other).y
		if gap < float(best.gap):
			best = {"found": true, "gap": gap, "speed": Adapters.velocity(other).dot(fwd), "node": other}
	return best


## True when no vehicle sits in the lane strip `lateral` (m right of my heading) between `back` m behind and `ahead` m in front.
static func lane_free(me: Node3D, fwd: Vector3, lateral: float, back: float, ahead: float, window := 2.0) -> bool:
	var right := fwd.cross(Vector3.UP)
	var my_pos := me.global_position
	for e: Dictionary in entries:
		var other: Node3D = e.node
		if other == me or not is_instance_valid(other):
			continue
		var r := other.global_position - my_pos
		r.y = 0.0
		var along := r.dot(fwd)
		if along < -back or along > ahead:
			continue
		if absf(r.dot(right) - lateral) < window:
			return false
	return true


## Any vehicle (other than `me`) with its centre within `radius` of `centre`.
static func occupied(centre: Vector3, radius: float, me: Node3D) -> bool:
	for e: Dictionary in entries:
		var other: Node3D = e.node
		if other == me or not is_instance_valid(other):
			continue
		var d := other.global_position - centre
		d.y = 0.0
		if d.length() < radius:
			return true
	return false


## A fast vehicle heading for `centre` from within `range_m` (cross-traffic threat for red-light running).
static func cross_threat(centre: Vector3, range_m: float, me: Node3D) -> bool:
	var my_fwd := -me.global_transform.basis.z
	my_fwd.y = 0.0
	my_fwd = my_fwd.normalized()
	for e: Dictionary in entries:
		var other: Node3D = e.node
		if other == me or not is_instance_valid(other):
			continue
		var d := centre - other.global_position
		d.y = 0.0
		var dist := d.length()
		if dist > range_m or dist < 0.5:
			continue
		var vel := Adapters.velocity(other)
		if vel.length() > 2.5 and vel.normalized().dot(d / dist) > 0.5 and absf(vel.normalized().dot(my_fwd)) < 0.6:
			return true
	return false


static func reserve(node_id: StringName, who: Node3D, seconds: float) -> void:
	reservations[node_id] = {"who": who, "until": now() + seconds}


static func release(node_id: StringName, who: Node3D) -> void:
	var r: Variant = reservations.get(node_id)
	if r != null and r.who == who:
		reservations.erase(node_id)


static func reserved_by_other(node_id: StringName, me: Node3D) -> bool:
	var r: Variant = reservations.get(node_id)
	if r == null:
		return false
	if r.who == me:
		return false
	if not is_instance_valid(r.who) or float(r.until) < now():
		reservations.erase(node_id)
		return false
	return true
