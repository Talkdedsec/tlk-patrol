class_name CityBuilder
extends RefCounted
## Builds the static city: ground, roads, markings, sidewalks, signs, signals and street lamps.
## Zones (houses, shops, warehouses, rural) live in city_zones.gd and use the helpers here.
## Geometry is original low-poly; colors are tuned by hand.

const PROP_DIR := "res://assets/models/world/"

# sRGB palette (daytime albedo; night look comes from the lighting).
const C_GRASS := Color("#56773D")
const C_ASPHALT := Color("#575A61")
const C_ASPHALT_LOT := Color("#4A4E56")
const C_SIDEWALK := Color("#B9BBBD")
const C_CURB := Color("#A3A5A8")
const C_LINE_W := Color("#E6E6E2")
const C_LINE_Y := Color("#E0B820")
const C_GREEN_SIGN := Color("#0E6B3A")
const C_SIGN_WHITE := Color("#EDEDED")

const ROAD_Y := 0.03
const MARK_Y := 0.045
const SIDEWALK_W := 2.0
const VERGE_W := 2.0   # grass strip between the curb and the sidewalk
const CURB_H := 0.14

var root: Node3D
var graph: RoadGraph
var lighting: Lighting
var signals: TrafficSignals
var rng := RandomNumberGenerator.new()

var lamp_points: Array[Dictionary] = []
var flat_material: StandardMaterial3D
var body: StaticBody3D

var _inst: Dictionary = {}       # "mesh|cx|cz" -> {mesh, xforms, colors, range, shadow}
var _meshes: Dictionary = {}
var _roads := MeshBuilder.new()
var _marks := MeshBuilder.new()
var _walks := MeshBuilder.new()
var _signs := MeshBuilder.new()


func _init() -> void:
	flat_material = StandardMaterial3D.new()
	flat_material.vertex_color_use_as_albedo = true
	flat_material.vertex_color_is_srgb = true
	flat_material.roughness = 0.95
	flat_material.metallic_specular = 0.25


func build(p_root: Node3D, p_graph: RoadGraph, p_lighting: Lighting, p_signals: TrafficSignals) -> void:
	root = p_root
	graph = p_graph
	lighting = p_lighting
	signals = p_signals
	rng.seed = 40117
	body = StaticBody3D.new()
	body.name = "Colliders"
	root.add_child(body)
	_build_ground()
	for e in graph.edges:
		_build_road(e)
	_build_intersections()
	for e in graph.edges:
		_build_sidewalks(e)
	_build_street_furniture()
	var zones := CityZones.new(self)
	zones.build()
	_commit_mesh(_roads, "Roads")
	_commit_mesh(_marks, "Markings")
	_commit_mesh(_walks, "Sidewalks")
	_commit_mesh(_signs, "SignPlates")
	_flush_instances()


# ---- helpers shared with CityZones -----------------------------------------------------------------------

func mesh_of(prop: String) -> Mesh:
	if _meshes.has(prop):
		return _meshes[prop]
	var scene: PackedScene = load(PROP_DIR + prop + ".glb")
	var inst := scene.instantiate()
	var mesh: Mesh = null
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		mesh = (n as MeshInstance3D).mesh.duplicate()
		break
	inst.free()
	if prop == "street_lamp" and mesh != null:
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			if m != null and "lamp_glow" in m.resource_name:
				mesh.surface_set_material(i, lighting.lamp_glow_material)
	_meshes[prop] = mesh
	return mesh


## Queues a MultiMesh instance (chunked per 250 m cell so frustum culling works).
func add_instance(prop: String, t: Transform3D, range_end := 450.0, shadow := true) -> void:
	var mesh := mesh_of(prop)
	var key := "%s|%d|%d" % [prop, floori(t.origin.x / 250.0), floori(t.origin.z / 250.0)]
	if not _inst.has(key):
		_inst[key] = {"mesh": mesh, "xforms": [], "range": range_end, "shadow": shadow}
	_inst[key].xforms.append(t)


func add_box_collider(center: Vector3, size: Vector3, yaw := 0.0) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	body.add_child(cs)


func add_cylinder_collider(center: Vector3, radius: float, height: float) -> void:
	var cs := CollisionShape3D.new()
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = height
	cs.shape = s
	cs.position = center
	body.add_child(cs)


func add_mesh_node(node_name: String, mesh: Mesh, pos := Vector3.ZERO, shadows := true, range_end := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if range_end > 0.0:
		mi.visibility_range_end = range_end
	root.add_child(mi)
	return mi


## Label3D helper for signs; `size_m` is the text height in metres, the text faces local +Z of `t`.
func add_label(text: String, t: Transform3D, size_m: float, color: Color, double_sided := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = size_m / 64.0
	l.modulate = color
	l.outline_size = 0
	l.double_sided = double_sided
	l.shaded = true
	l.transform = t
	l.visibility_range_end = 120.0
	root.add_child(l)
	return l


func edge_dir(e: Dictionary) -> Vector3:
	var d: Vector3 = e.points[e.points.size() - 1] - e.points[0]
	d.y = 0.0
	return d.normalized()


func lamp(base: Vector3, toward: Vector3) -> void:
	# Lamp pole at `base`, arm pointing along `toward` (unit, XZ).
	var yaw := atan2(-toward.z, toward.x)
	var t := Transform3D(Basis(Vector3.UP, yaw), base)
	add_instance("street_lamp", t, 300.0, true)
	add_cylinder_collider(base + Vector3(0, 1.5, 0), 0.14, 3.0)
	lamp_points.append({"pos": base + toward * 2.0 + Vector3(0, 8.84, 0), "dir": toward})


# ---- ground and roads ---------------------------------------------------------------------------------------

func _build_ground() -> void:
	var r := CityLayout.GROUND_BOUNDS
	var mb := MeshBuilder.new()
	mb.flat(Vector3(r.get_center().x, 0.0, r.get_center().y), r.size.x, r.size.y, C_GRASS)
	add_mesh_node("Ground", mb.to_mesh(flat_material), Vector3.ZERO, false)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(r.size.x, 1.0, r.size.y)
	cs.shape = bs
	cs.position = Vector3(r.get_center().x, ROAD_Y - 0.5, r.get_center().y)
	body.add_child(cs)


func approach_cross_hw(node_id: StringName, e: Dictionary) -> float:
	## Half width of the widest road crossing the approach `e` at the node (own half width when none).
	var d := graph.direction_from(e, node_id)
	var best := 0.0
	for eid in graph.nodes[node_id].edges:
		var o: Dictionary = graph.edges[eid]
		if o.id == e.id:
			continue
		var od := graph.direction_from(o, node_id)
		if absf(od.dot(d)) < 0.5:
			best = maxf(best, o.width * 0.5)
	return best if best > 0.0 else e.width * 0.5


func _marking_trim(node_id: StringName, e: Dictionary) -> float:
	var n: Dictionary = graph.nodes[node_id]
	if n.edges.size() < 3 and n.control == "none":
		return 0.0
	if n.edges.size() == 1:
		return 0.0
	return approach_cross_hw(node_id, e) + 6.5


func _build_road(e: Dictionary) -> void:
	var pts: PackedVector3Array = e.points
	var half: float = e.width * 0.5
	for i in pts.size() - 1:
		var p0 := Vector3(pts[i].x, ROAD_Y, pts[i].z)
		var p1 := Vector3(pts[i + 1].x, ROAD_Y, pts[i + 1].z)
		_roads.strip(p0, p1, e.width, C_ASPHALT)
	var d := edge_dir(e)
	var left := Vector3.UP.cross(d)
	var a_trim := _marking_trim(e.a, e)
	var b_trim := _marking_trim(e.b, e)
	var s0: float = a_trim
	var s1: float = e.length - b_trim
	if s1 <= s0 + 1.0:
		return
	var p_start: Vector3 = pts[0] + d * s0
	var p_end: Vector3 = pts[0] + d * s1
	var y := Vector3(0, MARK_Y, 0)
	var dbl_gap := 0.13
	if e.kind == "highway":
		_jersey_barrier(pts[0] + d * (s0 + 20.0), pts[0] + d * (s1 - 20.0))
		for sgn3 in [-1.0, 1.0]:
			_marks.strip(p_start + y + left * (0.85 * sgn3), p_end + y + left * (0.85 * sgn3), 0.15, C_LINE_Y)
	elif e.oneway:
		pass
	else:
		_marks.strip(p_start + y + left * dbl_gap, p_end + y + left * dbl_gap, 0.12, C_LINE_Y)
		_marks.strip(p_start + y - left * dbl_gap, p_end + y - left * dbl_gap, 0.12, C_LINE_Y)
	# Lane dashes for 2+ lanes per direction.
	if e.lanes >= 2:
		var lane_w: float = (e.width - 1.0) / (e.lanes * 2.0)
		for k in range(1, e.lanes):
			for sgn in [-1.0, 1.0]:
				var off: float = lane_w * k * sgn
				var s := s0
				while s + 3.0 < s1:
					var a: Vector3 = pts[0] + d * s + left * off + y
					var b: Vector3 = pts[0] + d * (s + 3.0) + left * off + y
					_marks.strip(a, b, 0.12, C_LINE_W)
					s += 9.0
	# Edge lines on roads without curbs.
	if e.kind in ["highway", "rural", "arterial"]:
		for sgn2 in [-1.0, 1.0]:
			var off2: float = (half - 0.35) * sgn2
			_marks.strip(p_start + y + left * off2, p_end + y + left * off2, 0.15, C_LINE_W)


func _jersey_barrier(a: Vector3, b: Vector3) -> void:
	## Tan concrete median barrier between the carriageways (Davidson Beltway / I-40).
	var len := a.distance_to(b)
	if len < 8.0:
		return
	var mid := (a + b) * 0.5
	var dn := (b - a).normalized()
	var yaw := atan2(-dn.z, dn.x)
	var mb := MeshBuilder.new()
	mb.box(Vector3(0, 0.45, 0), Vector3(len, 0.9, 0.55), Color("#C9B08C"))
	mb.box(Vector3(0, 0.1, 0), Vector3(len, 0.2, 0.8), Color("#B39A78"))
	add_mesh_node("JerseyBarrier", mb.to_mesh(flat_material), mid, true, 600.0).rotation.y = yaw
	# Collision in 36 m pieces with 4 m pedestrian gaps (visual barrier stays continuous).
	var pos_s := 0.0
	while pos_s < len:
		var seg := minf(36.0, len - pos_s)
		var c := a + dn * (pos_s + seg * 0.5)
		add_box_collider(Vector3(c.x, 0.45, c.z), Vector3(seg, 0.9, 0.7), yaw)
		pos_s += 40.0


func _build_intersections() -> void:
	for id in graph.nodes:
		var n: Dictionary = graph.nodes[id]
		var ctl: String = n.control
		if n.edges.size() < 3 and ctl == "none":
			continue
		for eid in n.edges:
			var e: Dictionary = graph.edges[eid]
			var stops := false
			var d := graph.direction_from(e, id)
			match ctl:
				"all_way", "signal":
					stops = true
				"minor_stop":
					stops = _is_minor(id, e)
			var cross_hw := approach_cross_hw(id, e)
			var hw: float = e.width * 0.5
			var right := Vector3.UP.cross(d)  # right of travel (travel = -d)
			var base: Vector3 = n.pos
			if e.kind == "highway":
				continue
			# Zebra crosswalk across the approach.
			var cw_center := base + d * (cross_hw + 2.2)
			var x := -hw + 0.9
			while x < hw - 0.5:
				var c := cw_center + right * x + Vector3(0, MARK_Y, 0)
				_marks.strip(c - d * 1.5, c + d * 1.5, 0.55, C_LINE_W)
				x += 1.3
			if stops:
				var sl := base + d * (cross_hw + 4.6) + Vector3(0, MARK_Y, 0)
				_marks.strip(sl + right * 0.15, sl + right * (hw - 0.1), 0.5, C_LINE_W)  # stop bar across the approach lane


func _is_minor(id: StringName, e: Dictionary) -> bool:
	## At a "minor_stop" node the stop applies to the lower-class (narrower) road.
	var wmax := 0.0
	for eid in graph.nodes[id].edges:
		wmax = maxf(wmax, graph.edges[eid].width)
	return e.width < wmax - 0.5 or (e.kind == "residential" and e.width < wmax + 0.01 and graph.nodes[id].edges.size() <= 3 and _is_stem(id, e))


func _is_stem(id: StringName, e: Dictionary) -> bool:
	# True when `e` is the only edge in its direction axis (the stem of a T).
	var d := graph.direction_from(e, id)
	for eid in graph.nodes[id].edges:
		var o: Dictionary = graph.edges[eid]
		if o.id != e.id and absf(graph.direction_from(o, id).dot(d)) > 0.9:
			return false
	return true


# ---- sidewalks -------------------------------------------------------------------------------------------------

static func verge_of(kind: String) -> float:
	return 0.0 if kind == "industrial" else VERGE_W


func _side_trim(node_id: StringName, e: Dictionary, side: Vector3) -> float:
	var n: Dictionary = graph.nodes[node_id]
	var trim := 0.0
	for eid in n.edges:
		var o: Dictionary = graph.edges[eid]
		if o.id == e.id:
			continue
		var od := graph.direction_from(o, node_id)
		if od.dot(side) > 0.5:
			trim = maxf(trim, o.width * 0.5 + verge_of(o.kind))
	return trim


func _build_sidewalks(e: Dictionary) -> void:
	if e.kind not in ["residential", "arterial", "industrial"]:
		return
	var d := edge_dir(e)
	var left := Vector3.UP.cross(d)
	var hw: float = e.width * 0.5
	var vg := verge_of(e.kind)
	var p0: Vector3 = e.points[0]
	for side in [left, -left]:
		var t0 := _side_trim(e.a, e, side)
		var t1 := _side_trim(e.b, e, side)
		var s0 := t0
		var s1: float = e.length - t1
		if s1 - s0 < 1.0:
			continue
		var center: Vector3 = side * (hw + vg + SIDEWALK_W * 0.5)
		_walk_strip(p0 + d * s0 + center, p0 + d * s1 + center, SIDEWALK_W, C_SIDEWALK)
		# Curb strip along the road edge (trimmed only by crossing road pavement).
		var c0 := 0.0
		var c1: float = e.length
		for k in [e.a, e.b]:
			var tr := 0.0
			for eid in graph.nodes[k].edges:
				var o: Dictionary = graph.edges[eid]
				if o.id != e.id and graph.direction_from(o, k).dot(side) > 0.5:
					tr = maxf(tr, o.width * 0.5)
			if k == e.a:
				c0 = tr
			else:
				c1 = e.length - tr
		if vg > 0.0 and c1 - c0 > 1.0:
			var cc: Vector3 = side * (hw + 0.15)
			_walk_strip(p0 + d * c0 + cc, p0 + d * c1 + cc, 0.3, C_CURB)
	# Corner squares at crossings.
	for id in [e.a, e.b]:
		var n: Dictionary = graph.nodes[id]
		if n.edges.size() < 3:
			continue
		var sd: Vector3 = graph.direction_from(e, id)
		for eid in n.edges:
			var o: Dictionary = graph.edges[eid]
			if o.id <= e.id:
				continue
			var od := graph.direction_from(o, id)
			if absf(od.dot(sd)) > 0.5:
				continue
			var c: Vector3 = n.pos + sd * (o.width * 0.5 + verge_of(o.kind) + SIDEWALK_W * 0.5) + od * (hw + vg + SIDEWALK_W * 0.5)
			_walk_strip(c - sd * (SIDEWALK_W * 0.5), c + sd * (SIDEWALK_W * 0.5), SIDEWALK_W, C_SIDEWALK)


func _walk_strip(a: Vector3, b: Vector3, w: float, color: Color) -> void:
	var a2 := Vector3(a.x, CURB_H, a.z)
	var b2 := Vector3(b.x, CURB_H, b.z)
	_walks.strip(a2, b2, w, color)
	# curb faces (road side is whichever side is nearer; a thin darker box edge keeps the silhouette)
	var d := (b - a)
	d.y = 0.0
	var len := d.length()
	if len < 0.5:
		return
	var dn := d / len
	var side := Vector3(-dn.z, 0.0, dn.x)
	var mid := (a + b) * 0.5
	var yaw := atan2(-dn.z, dn.x)
	# Curb collision is a low step (walkers and cars roll over it); the visual curb stays 0.14 m.
	add_box_collider(Vector3(mid.x, 0.03, mid.z), Vector3(len, 0.06, w), yaw)
	# visible side walls: draw as two thin vertical quads
	for sgn in [-1.0, 1.0]:
		var o: Vector3 = side * (w * 0.5) * sgn
		var q0 := Vector3(a.x, 0.0, a.z) + o
		var q1 := Vector3(b.x, 0.0, b.z) + o
		var q2 := Vector3(b.x, CURB_H, b.z) + o
		var q3 := Vector3(a.x, CURB_H, a.z) + o
		var face_out: Vector3 = side * sgn
		var n := (q1 - q0).cross(q2 - q0)
		if n.dot(face_out) > 0.0:
			_walks.quad(q0, q1, q2, q3, C_CURB)
		else:
			_walks.quad(q1, q0, q3, q2, C_CURB)


# ---- signs, signals, hydrants, street lamps -----------------------------------------------------------------

func basis_facing(d: Vector3) -> Basis:
	## Basis whose +Z is `d` (XZ unit) and +X is the driver's right when approaching along -d.
	var x := Vector3.UP.cross(d)
	return Basis(x, Vector3.UP, d)


func _build_street_furniture() -> void:
	for id in graph.nodes:
		var n: Dictionary = graph.nodes[id]
		var ctl: String = n.control
		if n.edges.size() >= 3 or ctl != "none":
			_street_name_post(id)
		for eid in n.edges:
			var e: Dictionary = graph.edges[eid]
			if e.kind == "highway":
				continue
			var d := graph.direction_from(e, id)
			var hw: float = e.width * 0.5
			var cross_hw := approach_cross_hw(id, e)
			var right := Vector3.UP.cross(d)
			match ctl:
				"all_way":
					_stop_sign(n.pos + d * (cross_hw + 5.4) + right * (hw + 1.4), d, true)
				"minor_stop":
					if _is_minor(id, e):
						_stop_sign(n.pos + d * (cross_hw + 5.4) + right * (hw + 1.4), d, false)
				"signal":
					_signal_mast(id, n.pos + d * (cross_hw + 2.8) + right * (hw + 1.6), d)
	for e in graph.edges:
		_speed_signs(e)
		_edge_lamps_and_hydrants(e)


func _stop_sign(pos: Vector3, d: Vector3, all_way: bool) -> void:
	var b := basis_facing(d)
	add_instance("stop_sign", Transform3D(b, pos), 220.0, false)
	add_cylinder_collider(pos + Vector3(0, 1.2, 0), 0.08, 2.4)
	var front := pos + d * 0.16
	add_label("STOP", Transform3D(b, front + Vector3(0, 2.35, 0)), 0.2, Color.WHITE)
	if all_way:
		_signs.xf = Transform3D(b, pos)
		_signs.box(Vector3(0, 1.82, 0.03), Vector3(0.62, 0.22, 0.02), C_SIGN_WHITE)
		_signs.xf = Transform3D.IDENTITY
		add_label("ALL WAY", Transform3D(b, front + Vector3(0, 1.82, 0.01)), 0.11, Color("#1A1A1A"))


func _signal_mast(id: StringName, pos: Vector3, d: Vector3) -> void:
	var b := basis_facing(d)
	var t := Transform3D(b, pos)
	add_instance("signal_mast", t, 320.0, true)
	add_cylinder_collider(pos + Vector3(0, 2.0, 0), 0.16, 4.0)
	var axis := "ns" if absf(d.z) > absf(d.x) else "ew"
	var lens_mesh := BoxMesh.new()
	lens_mesh.size = Vector3(0.26, 0.26, 0.05)
	for hx in [-2.6, -5.8]:
		var lenses: Array = []
		for k in 3:
			var mi := MeshInstance3D.new()
			mi.mesh = lens_mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = 260.0
			mi.transform = Transform3D(b, pos + b * Vector3(hx, 5.45 + 0.36 - 0.36 * k, 0.17))
			root.add_child(mi)
			lenses.append(mi)
		signals.add_head(id, axis, lenses)


func _street_name_post(id: StringName) -> void:
	var n: Dictionary = graph.nodes[id]
	var picked: Array = []
	for eid in n.edges:
		var e: Dictionary = graph.edges[eid]
		if e.kind == "highway":
			continue
		var dup := false
		for o in picked:
			if absf(graph.direction_from(o, id).dot(graph.direction_from(e, id))) > 0.9:
				dup = true
		if not dup:
			picked.append(e)
	if picked.size() < 2:
		return
	var ea: Dictionary = picked[0]
	var eb: Dictionary = picked[1]
	var da := graph.direction_from(ea, id)
	var db := graph.direction_from(eb, id)
	if absf(da.dot(db)) > 0.5:
		return
	var pos: Vector3 = n.pos + da * (eb.width * 0.5 + 2.9) + db * (ea.width * 0.5 + 2.9)
	var post := MeshBuilder.new()
	post.box(Vector3(0, 1.4, 0), Vector3(0.07, 2.8, 0.07), Color("#8A8D92"))
	for k in 2:
		var e: Dictionary = picked[k]
		var dir: Vector3 = [da, db][k]
		var along := Vector3(absf(dir.x), 0, absf(dir.z))   # blade runs parallel to the road it names
		var yaw := atan2(-along.z, along.x)
		var h := 2.62 - 0.3 * k
		post.xf = Transform3D(Basis(Vector3.UP, yaw), Vector3(0, h, 0))
		post.box(Vector3(0, 0, 0), Vector3(1.15, 0.22, 0.03), C_GREEN_SIGN)
		post.xf = Transform3D.IDENTITY
		for face in [1.0, -1.0]:
			var lt := Transform3D(Basis(Vector3.UP, yaw + (0.0 if face > 0 else PI)), pos + Vector3(0, h, 0) + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.05 * face))
			add_label(e.name, lt, minf(0.15, 1.0 / (e.name.length() * 0.55)), Color.WHITE)
	add_mesh_node("NamePost_%s" % id, post.to_mesh(flat_material), pos, false, 200.0)


func _speed_signs(e: Dictionary) -> void:
	if e.kind == "residential":
		return
	var d := edge_dir(e)
	var hw: float = e.width * 0.5
	var shoulder := 2.4 if e.kind in ["highway", "rural"] else 3.2
	var specs := [[e.a, d, 28.0]]
	if not e.oneway:
		specs.append([e.b, -d, 28.0])
	for spec in specs:
		var node_pos: Vector3 = graph.nodes[spec[0]].pos
		var dir: Vector3 = spec[1]          # direction of travel along the edge, away from the node
		var travel_right := -Vector3.UP.cross(dir)
		var pos: Vector3 = node_pos + dir * spec[2] + travel_right * (hw + shoulder)
		_speed_sign(pos, -dir, e.limit_mph)


func _speed_sign(pos: Vector3, face: Vector3, mph: int) -> void:
	var b := basis_facing(face)
	var post := MeshBuilder.new()
	post.box(Vector3(0, 1.2, 0), Vector3(0.06, 2.4, 0.06), Color("#8A8D92"))
	post.box(Vector3(0, 2.0, 0.045), Vector3(0.62, 0.78, 0.03), C_SIGN_WHITE)
	var mi := add_mesh_node("SpeedSign", post.to_mesh(flat_material), pos, false, 250.0)
	mi.basis = b
	var front := pos + face * 0.07
	add_label("SPEED\nLIMIT", Transform3D(b, front + Vector3(0, 2.2, 0)), 0.15, Color.BLACK)
	add_label(str(mph), Transform3D(b, front + Vector3(0, 1.82, 0)), 0.3, Color.BLACK)


func _edge_lamps_and_hydrants(e: Dictionary) -> void:
	var d := edge_dir(e)
	var left := Vector3.UP.cross(d)
	var hw: float = e.width * 0.5
	var p0: Vector3 = e.points[0]
	var t0 := _marking_trim(e.a, e) + 6.0
	var t1 := _marking_trim(e.b, e) + 6.0
	match e.kind:
		"residential":
			var spacing := 38.0
			var s := t0 + 8.0
			var k := 0
			while s < e.length - t1 - 4.0:
				var side := left if k % 2 == 0 else -left
				lamp(p0 + d * s + side * (hw + 1.0), -side)
				s += spacing
				k += 1
			# Hydrants every ~75 m at the property line.
			s = t0 + 20.0
			k = 0
			while s < e.length - t1 - 10.0:
				var sd := left if k % 2 == 0 else -left
				var hp: Vector3 = p0 + d * s + sd * (hw + 1.2)
				add_instance("hydrant", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), hp), 160.0, false)
				s += 76.0
				k += 1
		"arterial":
			var s2 := t0 + 6.0
			while s2 < e.length - t1 - 4.0:
				for side in [left, -left]:
					lamp(p0 + d * s2 + side * (hw + 1.0), -side)
				s2 += 34.0
		"industrial":
			var s3 := t0 + 6.0
			var k3 := 0
			while s3 < e.length - t1 - 4.0:
				var side3 := left if k3 % 2 == 0 else -left
				lamp(p0 + d * s3 + side3 * (hw + SIDEWALK_W + 0.8), -side3)
				s3 += 42.0
				k3 += 1


# ---- commit ---------------------------------------------------------------------------------------------------------

func _commit_mesh(mb: MeshBuilder, node_name: String) -> void:
	if mb.is_empty():
		return
	var mi := add_mesh_node(node_name, mb.to_mesh(flat_material), Vector3.ZERO, node_name == "Sidewalks")
	if node_name == "Roads" or node_name == "Markings":
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _flush_instances() -> void:
	for key in _inst:
		var d: Dictionary = _inst[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = d.mesh
		mm.instance_count = d.xforms.size()
		for i in d.xforms.size():
			mm.set_instance_transform(i, d.xforms[i])
		var mi := MultiMeshInstance3D.new()
		mi.name = "MM_" + key.replace("|", "_").replace("-", "n")
		mi.multimesh = mm
		mi.visibility_range_end = d.range
		if not d.shadow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	_inst.clear()
