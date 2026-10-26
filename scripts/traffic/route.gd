extends RefCounted
## Lane polyline for a chain of road-graph edges ("legs"), with smoothed junction corners.
## legs[i] = {edge: Dictionary, fwd: bool, lane: int, from: StringName, to: StringName}
## lane 0 = lane next to the road centre line (same convention as World.lane_transform), driving on the right.

const BEZIER_STEPS := 8

var legs: Array = []
var pts := PackedVector3Array()
var cum := PackedFloat32Array()      # distance along the polyline at every point
var leg_end := PackedFloat32Array()  # distance at which leg i ends (the junction node)
var last_dist := 0.0                 # distance from the last closest_s() query point to the polyline


static func lane_width(edge: Dictionary) -> float:
	var lanes: int = maxi(int(edge.lanes), 1)
	return (float(edge.width) - 1.0) / maxf(float(lanes * 2), 2.0)


static func lane_offset(edge: Dictionary, lane: int) -> float:
	return lane_width(edge) * (0.5 + float(lane))


static func make_leg(edge: Dictionary, fwd: bool, lane: int) -> Dictionary:
	return {"edge": edge, "fwd": fwd, "lane": lane, "from": edge.a if fwd else edge.b, "to": edge.b if fwd else edge.a}


func add_leg(leg: Dictionary) -> void:
	legs.append(leg)
	rebuild()


func total() -> float:
	return cum[cum.size() - 1] if cum.size() > 0 else 0.0


func remaining(s: float) -> float:
	return total() - s


# --- construction -------------------------------------------------------------------------------------------------

func rebuild() -> void:
	pts = PackedVector3Array()
	cum = PackedFloat32Array()
	leg_end = PackedFloat32Array()
	if legs.is_empty():
		return
	var polys: Array = []
	for leg: Dictionary in legs:
		polys.append(_lane_poly(leg))
	# corner radius per junction (between leg i and i + 1)
	var radii: Array[float] = []
	for i in range(legs.size() - 1):
		var pa: PackedVector3Array = polys[i]
		var pb: PackedVector3Array = polys[i + 1]
		var da := _end_dir(pa)
		var db := _start_dir(pb)
		var ang := absf(da.angle_to(db))
		if ang < 0.07:
			radii.append(0.0)
			continue
		var limit_mph: float = maxf(float(legs[i].edge.limit_mph), float(legs[i + 1].edge.limit_mph))
		var base := 11.0   # tangent length of the corner curve; the apex radius is about 0.7 of it
		if limit_mph >= 55.0:
			base = 70.0
		elif limit_mph >= 40.0:
			base = 18.0
		elif limit_mph >= 30.0:
			base = 14.0
		radii.append(minf(base, 0.42 * minf(_poly_len(pa), _poly_len(pb))))
	var out := PackedVector3Array()
	var node_idx: Array[int] = []
	for i in legs.size():
		var seg: PackedVector3Array = polys[i]
		if i > 0 and radii[i - 1] > 0.0:
			seg = _trim_head(seg, radii[i - 1])
		if i < legs.size() - 1 and radii[i] > 0.0:
			seg = _trim_tail(seg, radii[i])
		if out.is_empty():
			out.append_array(seg)
		else:
			var a: Vector3 = out[out.size() - 1]
			var b: Vector3 = seg[0]
			var mid_i := out.size() - 1
			if radii[i - 1] > 0.0:
				var da2 := _end_dir(out)
				var db2 := _start_dir(seg)
				var c := _corner_control(a, da2, b, db2)
				for k in range(1, BEZIER_STEPS + 1):
					var t := float(k) / float(BEZIER_STEPS)
					var q := a * ((1.0 - t) * (1.0 - t)) + c * (2.0 * (1.0 - t) * t) + b * (t * t)
					out.append(q)
				mid_i = out.size() - 1 - BEZIER_STEPS / 2
				seg = seg.slice(1)
			else:
				if a.distance_to(b) < 0.05:
					seg = seg.slice(1)
				mid_i = out.size() - 1
			node_idx[i - 1] = mid_i
			out.append_array(seg)
		node_idx.append(out.size() - 1)
	pts = out
	cum.resize(pts.size())
	var acc := 0.0
	for i in pts.size():
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		cum[i] = acc
	leg_end.resize(legs.size())
	for i in legs.size():
		leg_end[i] = cum[mini(node_idx[i], pts.size() - 1)]


static func _lane_poly(leg: Dictionary) -> PackedVector3Array:
	var edge: Dictionary = leg.edge
	var src: PackedVector3Array = edge.points
	var p := PackedVector3Array()
	if leg.fwd:
		p = src.duplicate()
	else:
		for i in range(src.size() - 1, -1, -1):
			p.append(src[i])
	var off := lane_offset(edge, int(leg.lane))
	var out := PackedVector3Array()
	for j in p.size():
		var t: Vector3
		if j == 0:
			t = p[1] - p[0]
		elif j == p.size() - 1:
			t = p[j] - p[j - 1]
		else:
			t = (p[j] - p[j - 1]).normalized() + (p[j + 1] - p[j]).normalized()
		t.y = 0.0
		t = t.normalized()
		out.append(p[j] + t.cross(Vector3.UP) * off)
	return out


static func _poly_len(p: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i].distance_to(p[i - 1])
	return l


static func _end_dir(p: PackedVector3Array) -> Vector3:
	var d := p[p.size() - 1] - p[p.size() - 2]
	d.y = 0.0
	return d.normalized()


static func _start_dir(p: PackedVector3Array) -> Vector3:
	var d := p[1] - p[0]
	d.y = 0.0
	return d.normalized()


static func _trim_tail(p: PackedVector3Array, r: float) -> PackedVector3Array:
	var acc := 0.0
	for i in range(p.size() - 1, 0, -1):
		var seg := p[i].distance_to(p[i - 1])
		if acc + seg >= r:
			var out := p.slice(0, i)
			out.append(p[i].lerp(p[i - 1], (r - acc) / maxf(seg, 0.0001)))
			return out
		acc += seg
	return p


static func _trim_head(p: PackedVector3Array, r: float) -> PackedVector3Array:
	var acc := 0.0
	for i in range(p.size() - 1):
		var seg := p[i].distance_to(p[i + 1])
		if acc + seg >= r:
			var out := PackedVector3Array([p[i].lerp(p[i + 1], (r - acc) / maxf(seg, 0.0001))])
			out.append_array(p.slice(i + 1))
			return out
		acc += seg
	return p


## Intersection of the two tangent lines (XZ); the midpoint when they are parallel.
static func _corner_control(a: Vector3, da: Vector3, b: Vector3, db: Vector3) -> Vector3:
	var den := da.x * db.z - da.z * db.x
	if absf(den) < 0.02:
		return (a + b) * 0.5
	var ab := b - a
	var t := (ab.x * db.z - ab.z * db.x) / den
	if t < 0.0 or t > 3.0 * a.distance_to(b):
		return (a + b) * 0.5
	return a + da * t


# --- queries ------------------------------------------------------------------------------------------------------

func _idx_at(s: float) -> int:
	var lo := 0
	var hi := cum.size() - 2
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid - 1
	return maxi(lo, 0)


func pos_at(s: float) -> Vector3:
	if pts.size() < 2:
		return Vector3.ZERO
	s = clampf(s, 0.0, cum[cum.size() - 1])
	var i := _idx_at(s)
	var seg := cum[i + 1] - cum[i]
	var t := 0.0 if seg < 0.0001 else (s - cum[i]) / seg
	return pts[i].lerp(pts[i + 1], t)


func dir_at(s: float) -> Vector3:
	if pts.size() < 2:
		return Vector3.FORWARD
	var i := _idx_at(clampf(s, 0.0, cum[cum.size() - 1]))
	var d := pts[i + 1] - pts[i]
	d.y = 0.0
	return d.normalized()


## Distance along the route of the point closest to `pos` (XZ). Searches a window around `hint` unless `global`.
func closest_s(pos: Vector3, hint: float, global := false) -> float:
	if pts.size() < 2:
		return 0.0
	var i0 := 0
	var i1 := pts.size() - 2
	if not global:
		i0 = _idx_at(maxf(hint - 12.0, 0.0))
		i1 = _idx_at(hint + 70.0)
	var best_d := INF
	var best_s := hint
	var p := Vector2(pos.x, pos.z)
	for i in range(i0, i1 + 1):
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var c := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_squared_to(c)
		if d < best_d:
			best_d = d
			best_s = cum[i] + a.distance_to(c)
	last_dist = sqrt(best_d)
	if not global and last_dist > 25.0:
		return closest_s(pos, hint, true)
	return best_s


func current_leg(s: float) -> int:
	for i in legs.size():
		if leg_end[i] >= s:
			return i
	return maxi(legs.size() - 1, 0)


## Junction nodes ahead: [{dist, node, arrive: leg, depart: leg, leg: index}] (the last leg has no departure).
func upcoming_nodes(s: float, horizon: float) -> Array:
	var out: Array = []
	for i in range(legs.size() - 1):
		var d := leg_end[i] - s
		if d < -3.0:
			continue
		if d > horizon:
			break
		out.append({"dist": d, "node": legs[i].to, "arrive": legs[i], "depart": legs[i + 1], "leg": i})
	return out


## Highest speed (m/s) allowed right now so that every bend ahead can be taken at lateral acceleration `a_lat`
## while braking at `a_brake`.
func curve_limit(s: float, horizon: float, a_lat: float, a_brake: float) -> float:
	if pts.size() < 3:
		return 1000.0
	var best := 1000.0
	var j := _idx_at(s) + 1
	while j < pts.size() - 1 and cum[j] - s < horizon:
		var a := pts[j] - pts[j - 1]
		var b := pts[j + 1] - pts[j]
		a.y = 0.0
		b.y = 0.0
		var la := a.length()
		var lb := b.length()
		if la > 0.01 and lb > 0.01:
			var ang := absf(a.angle_to(b))
			if ang > 0.02:
				# curvature from the circle through three points, or the kink estimate when a corner is not smoothed
				var chord := (pts[j + 1] - pts[j - 1])
				chord.y = 0.0
				var area2 := absf(a.x * b.z - a.z * b.x)
				var kappa := 2.0 * area2 / maxf(la * lb * chord.length(), 0.0001)
				kappa = maxf(kappa, ang / minf(0.5 * (la + lb), 12.0))
				var vc := sqrt(a_lat / kappa)
				var d := maxf(cum[j] - s, 0.0)
				best = minf(best, sqrt(vc * vc + 2.0 * a_brake * d))
		j += 1
	return best


## Drops legs that were fully passed (keeps the polyline short). Returns true when the polyline changed.
func drop_passed(s: float) -> bool:
	var dropped := false
	while legs.size() > 2 and leg_end[0] < s - 30.0:
		legs.remove_at(0)
		leg_end.remove_at(0)
		dropped = true
		break
	if dropped:
		rebuild()
	return dropped
