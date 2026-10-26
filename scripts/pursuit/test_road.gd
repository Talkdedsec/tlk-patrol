extends RefCounted
## Fallback test road network (3x3 city grid, a signal and stop signs, a 65 mph beltway ring with guard rails) for runs
## where World.road_graph is unavailable or placeholders are forced. Same RoadGraph structure as the real world.

const RoadGraphScript := preload("res://scripts/world/road_graph.gd")
const PlaceholderVehicle := preload("res://scripts/pursuit/placeholder_vehicle.gd")


## Builds the graph, the road meshes and the rails under `root`; returns the graph.
static func build(root: Node3D) -> Object:
	var g: Object = RoadGraphScript.new()
	var ids := {}
	for i in 3:
		for j in 3:
			var id := StringName("c%d%d" % [i, j])
			var control := "none"
			if i == 1 and j == 1:
				control = "signal"
			elif i == 0 and j == 1:
				control = "minor_stop"
			elif i == 2 and j == 0:
				control = "all_way"
			g.add_node(id, Vector3((i - 1) * 100.0, 0.0, (j - 1) * 100.0), control)
			ids[id] = true
	var ring := {&"e0": Vector3(520, 0, 0), &"ne": Vector3(520, 0, -420), &"n0": Vector3(0, 0, -420),
		&"nw": Vector3(-520, 0, -420), &"w0": Vector3(-520, 0, 0), &"sw": Vector3(-520, 0, 420),
		&"s0": Vector3(0, 0, 420), &"se": Vector3(520, 0, 420)}
	for k: StringName in ring:
		g.add_node(k, ring[k], "none")
	for i in 3:
		for j in 3:
			if i < 2:
				g.add_edge("Lincoln St", StringName("c%d%d" % [i, j]), StringName("c%d%d" % [i + 1, j]), 1, 30, 9.0, "residential")
			if j < 2:
				g.add_edge("E 3rd St", StringName("c%d%d" % [i, j]), StringName("c%d%d" % [i, j + 1]), 1, 30, 9.0, "residential")
	g.add_edge("East Ave", &"c21", &"e0", 1, 35, 10.0, "arterial")
	g.add_edge("West Ave", &"c01", &"w0", 1, 35, 10.0, "arterial")
	g.add_edge("North Rd", &"c10", &"n0", 1, 35, 10.0, "arterial")
	g.add_edge("South Rd", &"c12", &"s0", 1, 35, 10.0, "arterial")
	var order: Array[StringName] = [&"e0", &"ne", &"n0", &"nw", &"w0", &"sw", &"s0", &"se"]
	for i in order.size():
		g.add_edge("Davidson Beltway", order[i], order[(i + 1) % order.size()], 2, 65, 15.0, "highway")
	_meshes(root, g)
	_rails(g)
	return g


static func _meshes(root: Node3D, g: Object) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000, 3000)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("3c5a3a")
	plane.material = gm
	ground.mesh = plane
	ground.position.y = -0.06
	root.add_child(ground)
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color("3d4047")
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color("d9b84a")
	for e: Dictionary in g.edges:
		var pts: PackedVector3Array = e.points
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg_len := a.distance_to(b)
			var road := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(float(e.width), 0.08, seg_len + 2.0)
			bm.material = road_mat
			road.mesh = bm
			road.position = (a + b) * 0.5
			road.rotation.y = atan2(-(b - a).x, -(b - a).z)
			root.add_child(road)
			var line := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.18, 0.09, seg_len)
			lm.material = line_mat
			line.mesh = lm
			line.position = (a + b) * 0.5 + Vector3(0, 0.01, 0)
			line.rotation.y = road.rotation.y
			root.add_child(line)
	# blocks so that speed reads
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("8d8f95")
	for i in 60:
		var b := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(rng.randf_range(10, 22), rng.randf_range(5, 18), rng.randf_range(10, 22))
		box.material = bmat
		b.mesh = box
		b.position = Vector3(rng.randf_range(-700, 700), box.size.y * 0.5, rng.randf_range(-560, 560))
		if g.nearest_edge(b.position).dist > 22.0:
			root.add_child(b)
		else:
			b.free()


## Guard rails 13 m either side of the beltway ring (placeholder vehicles collide with them).
static func _rails(g: Object) -> void:
	PlaceholderVehicle.rails.clear()
	for e: Dictionary in g.edges:
		if String(e.kind) != "highway":
			continue
		var pts: PackedVector3Array = e.points
		for i in pts.size() - 1:
			var d := (pts[i + 1] - pts[i]).normalized()
			var a := pts[i] + d * 90.0   # gaps at the junctions
			var b := pts[i + 1] - d * 90.0
			var n := Vector3(-d.z, 0, d.x)
			for side in [-1.0, 1.0]:
				var o: Vector3 = n * 13.0 * side
				PlaceholderVehicle.rails.append([Vector2(a.x + o.x, a.z + o.z), Vector2(b.x + o.x, b.z + o.z)])
