class_name RoadGraph
extends RefCounted
## Road network data for traffic / pursuit AI and street queries.
## nodes[id] = {id, pos: Vector3, control: String, edges: Array[int]}
##   control: "none", "all_way" (4-way STOP + ALL WAY plate), "minor_stop" (stop on the minor road), "signal".
## edges[i] = {id, name, a, b, points: PackedVector3Array, lanes, limit_mph, width, kind, oneway, length}
##   lanes = lanes in each travel direction; oneway edges are drivable only a -> b (along points).
##   kind: "residential", "arterial", "industrial", "highway", "ramp", "rural", "lot"

var nodes: Dictionary = {}
var edges: Array[Dictionary] = []


func add_node(id: StringName, pos: Vector3, control := "none") -> void:
	nodes[id] = {"id": id, "pos": pos, "control": control, "edges": []}


func add_edge(street: String, a: StringName, b: StringName, lanes: int, limit_mph: int, width: float,
		kind: String, via: Array = [], oneway := false) -> int:
	var points := PackedVector3Array()
	points.append(nodes[a].pos)
	for p in via:
		points.append(p)
	points.append(nodes[b].pos)
	var length := 0.0
	for i in points.size() - 1:
		length += points[i].distance_to(points[i + 1])
	var edge := {
		"id": edges.size(), "name": street, "a": a, "b": b, "points": points, "lanes": lanes,
		"limit_mph": limit_mph, "width": width, "kind": kind, "oneway": oneway, "length": length,
	}
	edges.append(edge)
	nodes[a].edges.append(edge.id)
	nodes[b].edges.append(edge.id)
	return edge.id


## Unit direction of edge `e` leaving node `from_id` (outward from that node).
func direction_from(e: Dictionary, from_id: StringName) -> Vector3:
	var pts: PackedVector3Array = e.points
	var d: Vector3
	if e.a == from_id:
		d = pts[1] - pts[0]
	else:
		d = pts[pts.size() - 2] - pts[pts.size() - 1]
	d.y = 0.0
	return d.normalized()


func other_end(e: Dictionary, id: StringName) -> StringName:
	return e.b if e.a == id else e.a


## Nearest edge to a world position (XZ): {edge, dist, point, t} or empty when the graph is empty.
func nearest_edge(pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	var p2 := Vector2(pos.x, pos.z)
	for e in edges:
		var pts: PackedVector3Array = e.points
		var acc := 0.0
		for i in pts.size() - 1:
			var a := Vector2(pts[i].x, pts[i].z)
			var b := Vector2(pts[i + 1].x, pts[i + 1].z)
			var c := Geometry2D.get_closest_point_to_segment(p2, a, b)
			var d := p2.distance_to(c)
			if d < best_d:
				best_d = d
				var seg_len := a.distance_to(b)
				best = {"edge": e, "dist": d, "point": Vector3(c.x, 0.0, c.y), "t": (acc + a.distance_to(c)) / maxf(e.length, 0.001)}
			acc += a.distance_to(b)
	return best


## Point and tangent along edge at distance `s` metres from the `a` end (clamped).
func point_on_edge(e: Dictionary, s: float) -> Dictionary:
	var pts: PackedVector3Array = e.points
	s = clampf(s, 0.0, e.length)
	var acc := 0.0
	for i in pts.size() - 1:
		var seg := pts[i].distance_to(pts[i + 1])
		if acc + seg >= s or i == pts.size() - 2:
			var t := 0.0 if seg < 0.0001 else (s - acc) / seg
			return {"pos": pts[i].lerp(pts[i + 1], t), "dir": (pts[i + 1] - pts[i]).normalized()}
		acc += seg
	return {"pos": pts[0], "dir": Vector3.FORWARD}


## Drivable neighbours of a node: Array of {edge, to, cost}.
func neighbors(id: StringName) -> Array:
	var out: Array = []
	for eid in nodes[id].edges:
		var e: Dictionary = edges[eid]
		if e.oneway and e.a != id:
			continue
		var to: StringName = other_end(e, id)
		var cost: float = e.length / (e.limit_mph * 0.44704)
		out.append({"edge": e, "to": to, "cost": cost})
	return out


## Shortest drive-time path as node ids (Dijkstra); empty when unreachable.
func shortest_path(from_id: StringName, to_id: StringName) -> Array[StringName]:
	var dist := {from_id: 0.0}
	var prev := {}
	var open: Array[StringName] = [from_id]
	var done := {}
	while not open.is_empty():
		var best_i := 0
		for i in open.size():
			if dist[open[i]] < dist[open[best_i]]:
				best_i = i
		var cur: StringName = open[best_i]
		open.remove_at(best_i)
		if done.has(cur):
			continue
		done[cur] = true
		if cur == to_id:
			break
		for n in neighbors(cur):
			var nd: float = dist[cur] + n.cost
			if not dist.has(n.to) or nd < dist[n.to]:
				dist[n.to] = nd
				prev[n.to] = cur
				open.append(n.to)
	var path: Array[StringName] = []
	if not dist.has(to_id):
		return path
	var c: StringName = to_id
	while c != from_id:
		path.push_front(c)
		c = prev[c]
	path.push_front(from_id)
	return path
