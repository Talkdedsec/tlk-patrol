class_name CityZones
extends RefCounted
## Buildings and scenery of the city: Hoover St houses, Davidson Blvd shops, Davidson Plaza parking lot with
## strip mall and apartments, Kiln Rd warehouses, highway guardrails and rural land. Original layout.

const HOUSE_WALLS := ["#7E93A6", "#BFB093", "#D8D8D2", "#909399", "#8A735C", "#8FA3B3", "#C9BFA5", "#A6ABB2"]
const HOUSE_ROOFS := ["#3C3A40", "#5A3A32", "#45464C", "#2F3A44"]
const WARM_TINTS := ["#FFE2A8", "#FFD890", "#F5F1E0", "#FFE9BD"]
const C_DARK_GLASS_TINT := "#D7D0BC"

var b: CityBuilder
var g: RoadGraph
var rng: RandomNumberGenerator
var _house_sizes: Array[Vector3] = []
var _fence_mat: StandardMaterial3D
var _reserved: Array[Rect2] = []   # shop plots on Hoover St; houses are skipped inside


func _init(builder: CityBuilder) -> void:
	b = builder
	g = builder.graph
	rng = RandomNumberGenerator.new()
	rng.seed = 90311
	_fence_mat = StandardMaterial3D.new()
	_fence_mat.albedo_color = Color(0.56, 0.58, 0.62, 0.3)
	_fence_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fence_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fence_mat.roughness = 0.6


func build() -> void:
	_make_house_variants()
	_make_fence_meshes()
	_corner_shops()
	for e in g.edges:
		match e.kind:
			"residential":
				_residential_edge(e)
			"arterial":
				_commercial_edge(e)
			"industrial":
				_industrial_edge(e)
			"highway":
				_guardrails(e)
	_plaza()
	_skyline()
	_downtown()
	_rural()
	_gantry(-300.0, "I-40 WEST", "DAVIDSON CITY  12 MILE")
	_gantry(420.0, "I-40 EAST", "KILN RD  EXIT 9")
	for ox in [-700.0, -250.0, 300.0]:
		_overpass(ox)
	_exit_sign(-900.0, true, "I-40 EAST", "1/2 MILE")
	_exit_sign(150.0, true, "SUDS CITY LAUNDROMAT", "EXIT 7  1 MILE")
	_exit_sign(-500.0, false, "I-40 WEST", "1/2 MILE")


# ---- window helpers -------------------------------------------------------------------------------------------

func _win(mb: MeshBuilder, center: Vector3, rot_y: float, w: float, h: float, lit: bool, tint := Color.WHITE) -> void:
	var saved := mb.xf
	mb.xf = saved * Transform3D(Basis(Vector3.UP, rot_y), center)
	var c := Color(tint.r, tint.g, tint.b, 1.0 if lit else 0.0)
	mb.quad(Vector3(-w * 0.5, -h * 0.5, 0), Vector3(w * 0.5, -h * 0.5, 0), Vector3(w * 0.5, h * 0.5, 0), Vector3(-w * 0.5, h * 0.5, 0), c)
	mb.xf = saved


func _warm(lit_prob: float, dim := 1.0) -> Array:
	var c := Color(WARM_TINTS[rng.randi() % WARM_TINTS.size()])
	return [rng.randf() < lit_prob, Color(c.r * dim, c.g * dim, c.b * dim)]


func _building_mesh(body: MeshBuilder, win: MeshBuilder) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	body.commit(mesh, b.flat_material)
	win.commit(mesh, b.lighting.window_material)
	return mesh


# ---- houses -------------------------------------------------------------------------------------------------------

func _frame_window(body: MeshBuilder, win: MeshBuilder, center: Vector3, rot_y: float, w: float, h: float, lit: bool, tint: Color) -> void:
	# White trim box behind the glass quad (white-framed windows).
	var saved := body.xf
	body.xf = saved * Transform3D(Basis(Vector3.UP, rot_y), center)
	body.box(Vector3(0, 0, -0.02), Vector3(w + 0.28, h + 0.28, 0.05), Color("#ECECE8"))
	body.xf = saved
	_win(win, center + Basis(Vector3.UP, rot_y) * Vector3(0, 0, 0.012), rot_y, w, h, lit, tint)


func _make_house_variants() -> void:
	var r := RandomNumberGenerator.new()
	# [wall color, roof color, storeys, brick]
	var styles := [
		["#6F8CA6", "#5C5F66", 1, false], ["#8E4B3F", "#3C3A40", 1, true], ["#C9BFA5", "#5A3A32", 1, false],
		["#6F8CA6", "#4A4C52", 2, false], ["#7E93A6", "#5C5F66", 2, false], ["#8E4B3F", "#45464C", 2, true],
		["#D8D8D2", "#6B3F36", 1, false], ["#8FA3B3", "#3C3A40", 1, false], ["#A6ABB2", "#5C5F66", 2, false],
		["#8A735C", "#3C3A40", 1, false], ["#6F8CA6", "#6B3F36", 1, false], ["#B7A88A", "#4A4C52", 2, false],
	]
	for v in styles.size():
		r.seed = 1000 + v
		var st: Array = styles[v]
		var body := MeshBuilder.new()
		var win := MeshBuilder.new()
		var w := r.randf_range(10.5, 13.5)
		var d := r.randf_range(8.5, 10.0)
		var storeys: int = st[2]
		var h := 3.0 * storeys
		var wall := Color(st[0])
		var roof := Color(st[1])
		body.box(Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall)
		body.box(Vector3(0, 0.2, 0), Vector3(w + 0.14, 0.4, d + 0.14), wall.darkened(0.25))
		if storeys == 2:
			body.box(Vector3(0, 3.0, 0), Vector3(w + 0.1, 0.18, d + 0.1), Color("#ECECE8"))  # belt trim
		body.gable(Vector3(0, h, 0), Vector3(w, 0, d), r.randf_range(2.8, 3.5), roof, 0.55)
		var total_w := w
		var garage := v % 3 == 0
		if garage:
			var gw := 4.8
			var gd := 6.4
			var gx := w * 0.5 + gw * 0.5 - 0.2
			body.box(Vector3(gx, 1.4, d * 0.5 - gd * 0.5), Vector3(gw, 2.8, gd), wall)
			body.gable(Vector3(gx, 2.8, d * 0.5 - gd * 0.5), Vector3(gw, 0, gd), 1.4, roof, 0.45)
			body.box(Vector3(gx, 1.15, d * 0.5 + 0.03), Vector3(3.8, 2.3, 0.07), Color("#E4E4DF"))
			total_w = w + gw - 0.2
		# porch with railing
		var px := -w * 0.5 + 3.0
		body.box(Vector3(px, 0.14, d * 0.5 + 1.1), Vector3(4.6, 0.28, 2.2), Color("#B3B5B8"))
		for sx in [-2.1, 2.1]:
			body.box(Vector3(px + sx, 1.5, d * 0.5 + 2.0), Vector3(0.16, 2.4, 0.16), Color("#F0F0EC"))
		body.box(Vector3(px, 2.75, d * 0.5 + 1.1), Vector3(4.9, 0.18, 2.5), roof.lightened(0.06))
		body.box(Vector3(px, 0.95, d * 0.5 + 2.05), Vector3(4.2, 0.07, 0.07), Color("#F0F0EC"))
		body.box(Vector3(px, 0.4, d * 0.5 + 2.05), Vector3(4.2, 0.07, 0.07), Color("#F0F0EC"))
		for k in 7:
			body.box(Vector3(px - 1.9 + k * 0.63, 0.7, d * 0.5 + 2.05), Vector3(0.05, 0.6, 0.05), Color("#F0F0EC"))
		body.box(Vector3(px, 1.05, d * 0.5 + 0.03), Vector3(1.0, 2.1, 0.08), Color("#3E3A38") if st[3] else Color("#4A5A6E"))
		if st[3] or v % 2 == 0:
			body.box(Vector3(w * 0.25, h + 2.2, -d * 0.2), Vector3(0.8, 1.7, 0.8), Color("#7A4A3E"))
		# windows
		for fl in storeys:
			var wy := 1.7 + fl * 3.0
			var cols := [w * 0.5 - 2.7, 0.3] if fl == 0 else [w * 0.5 - 2.7, 0.3, -w * 0.5 + 3.0]
			for fx in cols:
				var lit_f := _warm_r(r, 0.4)
				_frame_window(body, win, Vector3(fx, wy, d * 0.5 + 0.03), 0.0, 1.3, 1.5, lit_f[0], lit_f[1])
			for bx in [-w * 0.28, w * 0.28]:
				var lit_b := _warm_r(r, 0.3)
				_frame_window(body, win, Vector3(bx, wy, -d * 0.5 - 0.03), PI, 1.3, 1.5, lit_b[0], lit_b[1])
			var lit_s := _warm_r(r, 0.3)
			_frame_window(body, win, Vector3(-w * 0.5 - 0.03, wy, 0.0), -PI * 0.5, 1.3, 1.5, lit_s[0], lit_s[1])
			if not garage:
				var lit_e := _warm_r(r, 0.3)
				_frame_window(body, win, Vector3(w * 0.5 + 0.03, wy, 0.0), PI * 0.5, 1.3, 1.5, lit_e[0], lit_e[1])
		var mesh := _building_mesh(body, win)
		b._meshes["house_%d" % v] = mesh
		_house_sizes.append(Vector3(total_w, h + 2.8, d))


func _warm_r(r: RandomNumberGenerator, p: float) -> Array:
	return [r.randf() < p, Color(WARM_TINTS[r.randi() % WARM_TINTS.size()])]


func _make_fence_meshes() -> void:
	for kind in ["white", "brown"]:
		var mb := MeshBuilder.new()
		var col := Color("#E0E0DC") if kind == "white" else Color("#6B5037")
		var hgt := 0.95 if kind == "white" else 1.8
		mb.box(Vector3(0, hgt * 0.5, 0), Vector3(4.0, hgt * 0.85, 0.05), col)
		mb.box(Vector3(-1.95, hgt * 0.5, 0), Vector3(0.1, hgt, 0.1), col.darkened(0.15))
		mb.box(Vector3(1.95, hgt * 0.5, 0), Vector3(0.1, hgt, 0.1), col.darkened(0.15))
		b._meshes["fence_" + kind] = mb.to_mesh(b.flat_material)


func _tree(pos: Vector3, collide := true) -> void:
	var kind := "pine_tree" if rng.randf() < 0.45 else "round_tree"
	var s := rng.randf_range(0.8, 1.1) if kind == "pine_tree" else rng.randf_range(1.1, 1.6)
	var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), pos)
	b.add_instance(kind, t, 380.0, false)
	if collide:
		b.add_cylinder_collider(pos + Vector3(0, 1.5, 0), 0.3, 3.0)


func _residential_edge(e: Dictionary) -> void:
	var d := b.edge_dir(e)
	var left := Vector3.UP.cross(d)
	var hw: float = e.width * 0.5
	var p0: Vector3 = e.points[0]
	var t0 := 3.0 + b.approach_cross_hw(e.a, e) + CityBuilder.SIDEWALK_W
	var t1 := 3.0 + b.approach_cross_hw(e.b, e) + CityBuilder.SIDEWALK_W
	var south_plaza := Rect2(CityLayout.PLAZA.position.x - 40.0, CityLayout.PLAZA.position.y - 30.0, 120.0, CityLayout.PLAZA.size.y + 60.0)
	for side in [left, -left]:
		var s := t0 + 4.0
		var k := 0
		while true:
			var lot_w := rng.randf_range(22.0, 29.0)
			if s + lot_w > e.length - t1 - 3.0:
				break
			var depth := hw + CityBuilder.VERGE_W + CityBuilder.SIDEWALK_W + 6.8
			var variant := rng.randi() % _house_sizes.size()
			# Blue single-storey porch house beside the Hoover x 9th crossing (north-east corner).
			if e.name == "Hoover St" and e.b == &"h9" and side.x > 0.5 and s + lot_w * 2.0 > e.length - t1 - 3.0:
				variant = 0
			var size: Vector3 = _house_sizes[variant]
			var center_s := s + lot_w * 0.5
			var front: Vector3 = p0 + d * center_s + side * depth
			var face: Vector3 = -side
			var hp: Vector3 = front + side * (size.z * 0.5)
			# House anchored so its centre is at hp; garage/porch widen +/-X so shift for symmetry.
			var skip: bool = south_plaza.has_point(Vector2(hp.x, hp.z)) and side.x > 0.5
			for rr in _reserved:
				if rr.grow(8.0).has_point(Vector2(hp.x, hp.z)):
					skip = true
			if not skip:
				var basis := b.basis_facing(face)
				b.add_instance("house_%d" % variant, Transform3D(basis.scaled(Vector3.ONE * 1.12), hp), 420.0, true)
				b.add_box_collider(hp + Vector3(0, 2.0, 0), Vector3(size.x + 0.5, 4.0, size.z + 2.0), atan2(-basis.x.z, basis.x.x))
				# driveway
				var dw_a: Vector3 = p0 + d * (center_s + size.x * 0.5 + 0.8) + side * (hw + CityBuilder.VERGE_W + CityBuilder.SIDEWALK_W)
				var dw_b: Vector3 = dw_a + side * (depth - hw - CityBuilder.VERGE_W - CityBuilder.SIDEWALK_W + 3.0)
				b._walks.strip(Vector3(dw_a.x, 0.05, dw_a.z), Vector3(dw_b.x, 0.05, dw_b.z), 3.2, Color("#7C7E82"))
				# trees and mailbox
				if rng.randf() < 0.75:
					_tree(p0 + d * (s + rng.randf_range(2.0, lot_w - 2.0)) + side * (hw + CityBuilder.VERGE_W + CityBuilder.SIDEWALK_W + 3.0))
				if rng.randf() < 0.6:
					_tree(p0 + d * (s + rng.randf_range(2.0, lot_w - 2.0)) + side * (depth + size.z + rng.randf_range(2.0, 8.0)))
				b.add_instance("mailbox", Transform3D(b.basis_facing(face), p0 + d * (center_s + size.x * 0.5 - 0.5) + side * (hw + CityBuilder.VERGE_W + CityBuilder.SIDEWALK_W + 0.6)), 120.0, false)
				if rng.randf() < 0.45:
					_fence_run(p0 + d * s + side * (depth + size.z + 5.0), d, lot_w, "brown")
				if rng.randf() < 0.3:
					_fence_run(p0 + d * (s + 3.0) + side * (hw + CityBuilder.VERGE_W + CityBuilder.SIDEWALK_W + 1.6), d, lot_w - 8.0, "white")
			s += lot_w
			k += 1


func _fence_run(start: Vector3, dir: Vector3, length: float, kind: String) -> void:
	var yaw := atan2(-dir.z, dir.x)
	var n := int(length / 4.0)
	for i in n:
		var c := start + dir * (2.0 + 4.0 * i)
		b.add_instance("fence_" + kind, Transform3D(Basis(Vector3.UP, yaw), c), 160.0, false)


# ---- commercial buildings -----------------------------------------------------------------------------------------

func _storefront(w: float, d: float, h: float, wall: Color, lit_prob: float, sign_color: Color) -> ArrayMesh:
	var body := MeshBuilder.new()
	var win := MeshBuilder.new()
	body.box(Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall)
	body.box(Vector3(0, h + 0.2, 0), Vector3(w + 0.3, 0.4, d + 0.3), wall.darkened(0.12))
	body.box(Vector3(rng.randf_range(-w * 0.25, w * 0.25), h + 0.9, rng.randf_range(-d * 0.2, d * 0.2)), Vector3(2.4, 1.0, 1.8), Color("#9A9CA0"))
	body.box(Vector3(0, 3.35, d * 0.5 + 0.1), Vector3(w - 0.4, 0.7, 0.2), sign_color)
	body.box(Vector3(0, 0.15, d * 0.5 + 0.1), Vector3(w, 0.3, 0.3), wall.darkened(0.25))
	var panel := 3.0
	var count := int((w - 1.0) / (panel + 0.25))
	var x0 := -(count * (panel + 0.25) - 0.25) * 0.5 + panel * 0.5
	for i in count:
		var lit := rng.randf() < lit_prob
		var col := Color(C_DARK_GLASS_TINT) if lit else Color.WHITE
		_win(win, Vector3(x0 + i * (panel + 0.25), 1.6, d * 0.5 + 0.03), 0.0, panel, 2.3, lit, col)
	return _building_mesh(body, win)


func _commercial_edge(e: Dictionary) -> void:
	var d := b.edge_dir(e)
	var left := Vector3.UP.cross(d)
	var hw: float = e.width * 0.5
	var p0: Vector3 = e.points[0]
	var t0 := 22.0 + b.approach_cross_hw(e.a, e)
	var t1 := 22.0 + b.approach_cross_hw(e.b, e)
	var plaza := CityLayout.PLAZA.grow(12.0)
	var towers := Rect2(-520.0, 150.0, 300.0, 100.0)
	for side in [left, -left]:
		var s := t0
		while true:
			var w := rng.randf_range(20.0, 38.0)
			if s + w > e.length - t1:
				break
			var depth := rng.randf_range(10.0, 15.0)
			var h := rng.randf_range(4.2, 6.5)
			var back := hw + CityBuilder.VERGE_W + CityBuilder.SIDEWALK_W + 14.0 + depth * 0.5
			var c: Vector3 = p0 + d * (s + w * 0.5) + side * back
			var c_front: Vector3 = p0 + d * (s + w * 0.5) + side * (hw + CityBuilder.VERGE_W + CityBuilder.SIDEWALK_W)
			var blocked: bool = plaza.has_point(Vector2(c.x, c.z)) or plaza.has_point(Vector2(c_front.x, c_front.z + 25.0)) or (side.z < -0.5 and towers.has_point(Vector2(c.x, c.z)))
			if not blocked and c.x < -140.0 and not _near_cross_road(c, e):
				_lined_lot(p0, d, side, hw, s, w)
			elif not blocked and not _near_cross_road(c, e):
				var wall := Color(["#A8A29A", "#B9AE98", "#8F96A0", "#A5ADB5", "#9C8F86"][rng.randi() % 5])
				var sign_col := Color(["#1D3F73", "#7A1F1F", "#1F5F3A", "#3A3A44", "#6B4B1E"][rng.randi() % 5])
				var mesh := _storefront(w, depth, h, wall, 0.7, sign_col)
				var mi := b.add_mesh_node("Shop", mesh, c, true, 500.0)
				mi.basis = b.basis_facing(-side)
				b.add_box_collider(c + Vector3(0, h * 0.5, 0), Vector3(w, h, depth), atan2(-d.z, d.x))
				# asphalt apron between the street and the shop
				var apron_a: Vector3 = p0 + d * (s + w * 0.5) + side * (hw + CityBuilder.VERGE_W + CityBuilder.SIDEWALK_W + 6.5)
				b._roads.flat(Vector3(apron_a.x, CityBuilder.ROAD_Y + 0.002, apron_a.z), w if absf(d.x) > 0.5 else 13.0, 13.0 if absf(d.x) > 0.5 else w, CityBuilder.C_ASPHALT_LOT)
				if rng.randf() < 0.5:
					_tree(p0 + d * (s + rng.randf_range(2.0, w - 2.0)) + side * (hw + CityBuilder.VERGE_W + CityBuilder.SIDEWALK_W + 1.8))
			s += w + rng.randf_range(4.0, 14.0)


func _near_cross_road(p: Vector3, e: Dictionary) -> bool:
	for o in g.edges:
		if o.id == e.id:
			continue
		var best := g.nearest_edge(p)
		if best.is_empty():
			return false
		return best.edge.id != e.id and best.dist < best.edge.width * 0.5 + 16.0
	return false


# ---- apartments and towers ----------------------------------------------------------------------------------------

func _apartment(w: float, d: float, floors: int, wall: Color, lit_prob: float, dim := 1.0) -> ArrayMesh:
	var body := MeshBuilder.new()
	var win := MeshBuilder.new()
	var h := floors * 3.2 + 0.6
	body.box(Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall)
	body.box(Vector3(0, h + 0.25, 0), Vector3(w + 0.4, 0.5, d + 0.4), wall.darkened(0.15))
	body.box(Vector3(w * 0.2, h + 1.2, 0.0), Vector3(3.2, 1.4, 3.0), Color("#8E9094"))
	var cols := int(w / 3.0)
	for f in floors:
		var y := 1.9 + f * 3.2
		for i in cols:
			var x := -w * 0.5 + 1.5 + i * 3.0
			var l1 := _warm(lit_prob, dim)
			_win(win, Vector3(x, y, d * 0.5 + 0.03), 0.0, 1.5, 1.7, l1[0], l1[1])
			var l2 := _warm(lit_prob, dim)
			_win(win, Vector3(x, y, -d * 0.5 - 0.03), PI, 1.5, 1.7, l2[0], l2[1])
		var rows := int(d / 3.2)
		for j in rows:
			var z := -d * 0.5 + 1.8 + j * 3.2
			var l3 := _warm(lit_prob, dim)
			_win(win, Vector3(w * 0.5 + 0.03, y, z), PI * 0.5, 1.5, 1.7, l3[0], l3[1])
			var l4 := _warm(lit_prob, dim)
			_win(win, Vector3(-w * 0.5 - 0.03, y, z), -PI * 0.5, 1.5, 1.7, l4[0], l4[1])
	# ground floor lobby glass
	_win(win, Vector3(0, 1.4, d * 0.5 + 0.03), 0.0, 4.0, 2.4, true, Color(C_DARK_GLASS_TINT))
	return _building_mesh(body, win)


func _place_building(mesh: Mesh, pos: Vector3, face: Vector3, size: Vector3, node_name: String) -> void:
	var mi := b.add_mesh_node(node_name, mesh, pos, true, 800.0)
	mi.basis = b.basis_facing(face)
	var yaw := atan2(-mi.basis.x.z, mi.basis.x.x)
	b.add_box_collider(pos + Vector3(0, size.y * 0.5, 0), size, yaw)


func _skyline() -> void:
	# A few taller blocks behind Davidson Blvd west (downtown feel).
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var x := -500.0
	var i := 0
	while x < -230.0:
		var floors := r.randi_range(6, 12)
		var w := r.randf_range(20.0, 28.0)
		var dd := r.randf_range(18.0, 24.0)
		var wall := Color(["#8E9AA6", "#A7A39B", "#7F8892", "#B0B3B8"][r.randi() % 4])
		var mesh := _apartment(w, dd, floors, wall, 0.45)
		var h := floors * 3.2 + 0.6
		_place_building(mesh, Vector3(x + w * 0.5, 0, 250.0 - 9.0 - 2.0 - 160.0 - dd * 0.5 - r.randf_range(0.0, 40.0)), Vector3(0, 0, 1), Vector3(w, h, dd), "Tower_%d" % i)
		x += w + r.randf_range(8.0, 22.0)
		i += 1


# ---- Davidson Plaza -------------------------------------------------------------------------------------------------

func _plaza() -> void:
	var r := CityLayout.PLAZA
	var cx := r.get_center().x
	var cz := r.get_center().y
	b._roads.flat(Vector3(cx, CityBuilder.ROAD_Y + 0.003, cz), r.size.x, r.size.y, CityBuilder.C_ASPHALT_LOT)
	# Entrances from Davidson Blvd.
	for ex in [r.position.x + 70.0, r.position.x + 260.0]:
		b._roads.flat(Vector3(ex, CityBuilder.ROAD_Y + 0.003, 276.0), 13.0, 34.0, CityBuilder.C_ASPHALT_LOT)
	# Stall lines: bays of two rows around a 7.5 m aisle, running along X.
	var z := r.position.y + 6.0
	while z + 17.0 < r.end.y:
		for row in [-1.0, 1.0]:
			var zc: float = z + 8.5 + row * (3.75 + 2.5)
			var x := r.position.x + 6.0
			while x < r.end.x - 6.0:
				b._marks.strip(Vector3(x, CityBuilder.MARK_Y + 0.003, zc - 2.5), Vector3(x, CityBuilder.MARK_Y + 0.003, zc + 2.5), 0.17, CityBuilder.C_LINE_W)
				x += 2.8
		z += 24.0
	# Lamps on a grid inside the lot.
	var gz := r.position.y + 24.0
	var row_i := 0
	while gz < r.end.y - 10.0:
		var gx := r.position.x + 30.0 + (18.0 if row_i % 2 == 1 else 0.0)
		while gx < r.end.x - 20.0:
			b.lamp(Vector3(gx, 0.03, gz), Vector3.RIGHT if int(gx / 20.0) % 2 == 0 else Vector3.LEFT)
			gx += 38.0
		gz += 48.0
		row_i += 1
	# Strip mall on the east edge, apartment blocks behind it.
	var strip := _storefront_long(18.0, 100.0)
	_place_building(strip, Vector3(r.end.x + 14.0, 0, cz), Vector3(-1, 0, 0), Vector3(18.0, 8.6, 100.0), "StripMall")
	var zz := cz - 110.0
	for i in 4:
		var floors: int = [4, 5, 4, 3][i]
		var mesh := _apartment(26.0, 15.0, floors, Color(["#A9AAB0", "#B7B2A7", "#9FA7B0", "#B2ABA0"][i]), 0.42)
		_place_building(mesh, Vector3(r.end.x + 14.0 + 9.0 + 28.0, 0, zz + i * 62.0), Vector3(-1, 0, 0), Vector3(26.0, floors * 3.2 + 0.6, 15.0), "Apartments_%d" % i)
	# Trees along the lot edges.
	var tx := r.position.x + 4.0
	while tx < r.end.x:
		_tree(Vector3(tx, 0.0, r.end.y + 4.0), false)
		_tree(Vector3(tx, 0.0, r.position.y + 4.0 + 5.0), false)
		tx += rng.randf_range(22.0, 34.0)


func _storefront_long(depth: float, length: float) -> ArrayMesh:
	# Two-storey strip building: local +Z faces the lot, X runs along the building. Window brightness varies per panel.
	var body := MeshBuilder.new()
	var win := MeshBuilder.new()
	var h := 8.6
	var wall := Color("#9A958C")
	body.box(Vector3(0, h * 0.5, 0), Vector3(length, h, depth), wall)
	body.box(Vector3(0, h + 0.2, 0), Vector3(length + 0.4, 0.4, depth + 0.4), wall.darkened(0.15))
	body.box(Vector3(0, 4.8, depth * 0.5 + 0.12), Vector3(length - 0.4, 0.5, 0.24), Color("#7A6F66"))
	body.box(Vector3(0, 0.15, depth * 0.5 + 0.1), Vector3(length, 0.3, 0.3), wall.darkened(0.25))
	var panel := 3.6
	var count := int((length - 1.0) / (panel + 0.3))
	var x0 := -(count * (panel + 0.3) - 0.3) * 0.5 + panel * 0.5
	for i in count:
		var lit := rng.randf() < 0.82
		var k := rng.randf_range(0.55, 1.0)
		var warm := rng.randf() < 0.75
		var tint := Color(0.95, 0.9, 0.78) * k if warm else Color(0.8, 0.88, 1.0) * k
		_win(win, Vector3(x0 + i * (panel + 0.3), 2.3, depth * 0.5 + 0.03), 0.0, panel, 3.0, lit, Color(tint.r, tint.g, tint.b))
		var lit2 := rng.randf() < 0.6
		var k2 := rng.randf_range(0.5, 1.0)
		_win(win, Vector3(x0 + i * (panel + 0.3), 6.6, depth * 0.5 + 0.03), 0.0, panel * 0.8, 2.0, lit2, Color(0.95 * k2, 0.9 * k2, 0.78 * k2))
	return _building_mesh(body, win)


# ---- industrial (Kiln Rd, Foundry Rd) ------------------------------------------------------------------------------

func _warehouse(w: float, d: float, h: float, wall: Color) -> ArrayMesh:
	var body := MeshBuilder.new()
	var win := MeshBuilder.new()
	body.box(Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall)
	body.box(Vector3(0, h + 0.15, 0), Vector3(w + 0.3, 0.3, d + 0.3), wall.darkened(0.2))
	var doors := maxi(1, int(w / 16.0))
	for i in doors:
		var x := -w * 0.5 + (i + 0.5) * w / doors
		body.box(Vector3(x, 2.1, d * 0.5 + 0.04), Vector3(4.4, 4.2, 0.08), wall.darkened(0.45))
		_win(win, Vector3(x, 4.7, d * 0.5 + 0.12), 0.0, 0.5, 0.25, true, Color("#FFF4DC"))
	var strip_n := int(w / 6.0)
	for i in strip_n:
		var lit := rng.randf() < 0.15
		_win(win, Vector3(-w * 0.5 + 3.0 + i * 6.0, h - 1.5, d * 0.5 + 0.03), 0.0, 2.2, 0.9, lit, Color(WARM_TINTS[0]))
	return _building_mesh(body, win)


func _industrial_edge(e: Dictionary) -> void:
	var d := b.edge_dir(e)
	var left := Vector3.UP.cross(d)
	var hw: float = e.width * 0.5
	var p0: Vector3 = e.points[0]
	var t0 := 16.0 + b.approach_cross_hw(e.a, e)
	var t1 := 16.0 + b.approach_cross_hw(e.b, e)
	var first_lot := true
	for side in [left, -left]:
		var s := t0
		while true:
			var w := rng.randf_range(38.0, 62.0)
			if s + w > e.length - t1:
				break
			var depth := rng.randf_range(24.0, 38.0)
			var h := rng.randf_range(8.0, 10.5)
			var setback := hw + CityBuilder.SIDEWALK_W + 18.0
			var c: Vector3 = p0 + d * (s + w * 0.5) + side * (setback + depth * 0.5)
			var wall := Color(["#8D9096", "#6F7F8C", "#B0A58C", "#7A8580"][rng.randi() % 4])
			var mesh := _warehouse(w, depth, h, wall)
			_place_building(mesh, c, -side, Vector3(w, h, depth) if absf(d.x) < 0.5 else Vector3(w, h, depth), "Warehouse")
			# apron + fence along the frontage
			var apron_c: Vector3 = p0 + d * (s + w * 0.5) + side * (hw + CityBuilder.SIDEWALK_W + 9.0)
			var along_x := absf(d.x) > 0.5
			b._roads.flat(Vector3(apron_c.x, CityBuilder.ROAD_Y + 0.002, apron_c.z), w if along_x else 18.0, 18.0 if along_x else w, Color("#5D6068"))
			var fence_start: Vector3 = p0 + d * s + side * (hw + CityBuilder.SIDEWALK_W + 2.5)
			_chain_fence(fence_start, d, w, side)
			if first_lot and e.name == "Kiln Rd" and e.kind == "industrial" and side.x > 0.5 and e.a == &"kd":
				first_lot = false
				var sign_pos: Vector3 = c - side * (depth * 0.5 + 0.2) + Vector3(0, h - 2.0, 0)
				b.add_label("SMELTER METALS", Transform3D(b.basis_facing(-side), sign_pos), 1.1, Color("#F2F2EE"))
			for k in rng.randi_range(1, 3):
				var cont := MeshBuilder.new()
				cont.box(Vector3(0, 1.3, 0), Vector3(6.0, 2.6, 2.4), Color(["#9E3A2E", "#2F5A8C", "#8A6A2A", "#4C6B52"][rng.randi() % 4]))
				var cp: Vector3 = p0 + d * (s + rng.randf_range(4.0, w - 4.0)) + side * (hw + CityBuilder.SIDEWALK_W + rng.randf_range(6.0, 14.0))
				var mi := b.add_mesh_node("Container", cont.to_mesh(b.flat_material), cp, true, 300.0)
				mi.rotation.y = rng.randf_range(-0.2, 0.2) + (0.0 if along_x else PI * 0.5)
			s += w + rng.randf_range(8.0, 24.0)


func _chain_fence(start: Vector3, dir: Vector3, length: float, side: Vector3) -> void:
	var mb := MeshBuilder.new()
	var panel := MeshBuilder.new()
	var gate_at := length * 0.5
	var n := int(length / 3.0)
	var local_dir := dir
	for i in n + 1:
		var p := local_dir * (i * 3.0)
		mb.box(p + Vector3(0, 1.1, 0), Vector3(0.1, 2.2, 0.1), Color("#8A8D92"))
	mb.box(local_dir * (n * 3.0 * 0.5) + Vector3(0, 2.2, 0), Vector3(absf(dir.x) * n * 3.0 + 0.1, 0.08, absf(dir.z) * n * 3.0 + 0.1), Color("#8A8D92"))
	var seg_a := Vector3.ZERO
	var seg_b := local_dir * (n * 3.0)
	var h := 2.1
	var q := [seg_a, seg_b, seg_b + Vector3(0, h, 0), seg_a + Vector3(0, h, 0)]
	panel.quad(q[0], q[1], q[2], q[3], Color(1, 1, 1, 1))
	var mesh := ArrayMesh.new()
	mb.commit(mesh, b.flat_material)
	panel.commit(mesh, _fence_mat)
	var mi := b.add_mesh_node("ChainFence", mesh, start, false, 250.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.add_box_collider(start + local_dir * (n * 3.0 * 0.5) + Vector3(0, 1.1, 0), Vector3(maxf(absf(dir.x) * n * 3.0, 0.2), 2.2, maxf(absf(dir.z) * n * 3.0, 0.2)))
	gate_at += 0.0


# ---- highway guardrails and rural land ------------------------------------------------------------------------------

func _guardrails(e: Dictionary) -> void:
	var d := b.edge_dir(e)
	var left := Vector3.UP.cross(d)
	var hw: float = e.width * 0.5
	var p0: Vector3 = e.points[0]
	var yaw := atan2(-d.z, d.x)
	var t0 := 55.0 if g.nodes[e.a].edges.size() >= 3 else 4.0
	var t1 := 55.0 if g.nodes[e.b].edges.size() >= 3 else 4.0
	for side in [left, -left]:
		var s := t0 + 2.0
		while s < e.length - t1:
			var pos: Vector3 = p0 + d * s + side * (hw + 1.3)
			b.add_instance("guardrail", Transform3D(Basis(Vector3.UP, yaw), pos), 320.0, false)
			s += 4.0
	# Dense low-poly tree rows 3-8 m outside the guardrail on both sides.
	var s2 := 14.0
	while s2 < e.length - 14.0:
		for side2 in [left, -left]:
			if rng.randf() < 0.8:
				var tp: Vector3 = p0 + d * (s2 + rng.randf_range(-6.0, 6.0)) + side2 * (hw + 1.3 + rng.randf_range(3.0, 8.0))
				if not CityLayout.PLAZA.has_point(Vector2(tp.x, tp.z)) and (e.name != "I-40" or true):
					_tree(tp, false)
		s2 += rng.randf_range(15.0, 28.0)
	# Tall bent-arm lamps on the median every 60 m (Beltway / Route 7 only; I-40 stays an unlit night road).
	if e.name in ["Davidson Beltway", "Route 7"]:
		var s3 := t0 + 30.0
		var k3 := 0
		while s3 < e.length - t1 - 20.0:
			var sd: Vector3 = left if k3 % 2 == 0 else -left
			b.lamp(p0 + d * s3, sd)
			s3 += 60.0
			k3 += 1


## Overpass carrying a N-S road over I-40 at x (visual only): deck, parapets, piers and embankments.
func _overpass(x: float) -> void:
	var z := CityLayout.HIGHWAY_Z
	var mb := MeshBuilder.new()
	var deck_y := 6.6
	mb.box(Vector3(0, deck_y, 0), Vector3(11.0, 1.0, 46.0), Color("#9A9CA0"))
	mb.box(Vector3(0, deck_y + 0.62, 0), Vector3(9.4, 0.24, 46.0), CityBuilder.C_ASPHALT)
	for sx in [-5.3, 5.3]:
		mb.box(Vector3(sx, deck_y + 1.0, 0), Vector3(0.4, 0.9, 46.0), Color("#B3B5B8"))
	for pz in [-12.0, 12.0]:
		mb.box(Vector3(0, 3.0, pz), Vector3(9.0, 6.0, 1.6), Color("#8E9094"))
	# approach embankments (stepped wedges) on both ends
	for sgn in [-1.0, 1.0]:
		for k in 5:
			var len := 8.0
			var h := deck_y - 0.4 - k * 1.3
			mb.box(Vector3(0, h * 0.5, sgn * (23.0 + len * (k + 0.5))), Vector3(11.0 + k * 2.0, h, len), Color("#5A7A3C"))
	b.add_mesh_node("Overpass", mb.to_mesh(b.flat_material), Vector3(x, 0, z), true, 1200.0)
	for pz in [-12.0, 12.0]:
		b.add_box_collider(Vector3(x, 3.0, z + pz), Vector3(9.0, 6.0, 1.6))


## Green roadside exit sign on a post (right shoulder, facing west-bound or east-bound traffic).
func _exit_sign(x: float, east_bound: bool, text: String, sub: String) -> void:
	var z := CityLayout.HIGHWAY_Z + (12.0 if east_bound else -12.0)
	var face := Vector3(-1, 0, 0) if east_bound else Vector3(1, 0, 0)
	var mb := MeshBuilder.new()
	mb.box(Vector3(-1.4, 1.8, 0), Vector3(0.18, 3.6, 0.18), Color("#7A7D82"))
	mb.box(Vector3(1.4, 1.8, 0), Vector3(0.18, 3.6, 0.18), Color("#7A7D82"))
	mb.box(Vector3(0, 4.3, 0.1), Vector3(4.2, 2.0, 0.12), Color("#0E6B3A"))
	var mi := b.add_mesh_node("ExitSign", mb.to_mesh(b.flat_material), Vector3(x, 0, z), true, 700.0)
	mi.basis = b.basis_facing(face)
	var bs := b.basis_facing(face)
	b.add_label(text, Transform3D(bs, Vector3(x, 4.6, z) + face * 0.18), 0.5, Color.WHITE)
	b.add_label(sub, Transform3D(bs, Vector3(x, 3.85, z) + face * 0.18), 0.3, Color.WHITE)


func _rural() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	# Fields: flat colored patches just above the grass.
	var field_mb := MeshBuilder.new()
	var field_cols := ["#6B6A3A", "#7A7040", "#4A5E3A", "#60683C", "#8A7A48"]
	for i in 26:
		var fx := r.randf_range(-1900.0, 1900.0)
		var fz := r.randf_range(-1100.0, 1000.0)
		if absf(fz - 0.0) < 760.0 and absf(fx) < 1050.0:
			continue   # keep the town area clear
		field_mb.flat(Vector3(fx, 0.012, fz), r.randf_range(120.0, 320.0), r.randf_range(100.0, 260.0), Color(field_cols[r.randi() % field_cols.size()]))
	b.add_mesh_node("Fields", field_mb.to_mesh(b.flat_material), Vector3.ZERO, false, 2500.0)
	# Barn + silo.
	var barn := MeshBuilder.new()
	barn.box(Vector3(0, 3.5, 0), Vector3(16.0, 7.0, 11.0), Color("#8E2B24"))
	barn.gable(Vector3(0, 7.0, 0), Vector3(16.0, 0, 11.0), 3.6, Color("#4A4A50"), 0.5)
	barn.box(Vector3(0, 2.0, 5.52), Vector3(5.0, 4.0, 0.06), Color("#E6E6E2"))
	barn.box(Vector3(11.0, 5.0, 0), Vector3(4.0, 10.0, 4.0), Color("#B9BCC0"))
	var bp := Vector3(-820.0, 0.0, 520.0)
	b.add_mesh_node("Barn", barn.to_mesh(b.flat_material), bp, true, 1200.0)
	b.add_box_collider(bp + Vector3(0, 3.5, 0), Vector3(16, 7, 11))
	# Tree clusters away from roads.
	for i in 46:
		var cx := r.randf_range(-1900.0, 1900.0)
		var cz := r.randf_range(-1100.0, 1000.0)
		var near := g.nearest_edge(Vector3(cx, 0, cz))
		if not near.is_empty() and near.dist < 60.0:
			continue
		if absf(cz) < 400.0 and absf(cx) < 700.0:
			continue
		for k in r.randi_range(6, 16):
			var tp := Vector3(cx + r.randfn(0.0, 22.0), 0.0, cz + r.randfn(0.0, 22.0))
			_tree(tp, false)


# ---- Davidson Blvd west: houses behind brown fences and tall pines -------------------------

func _lined_lot(p0: Vector3, d: Vector3, side: Vector3, hw: float, s: float, lot_w: float) -> void:
	var vg := CityBuilder.VERGE_W
	var depth := hw + vg + CityBuilder.SIDEWALK_W + 7.5
	var variant := rng.randi() % _house_sizes.size()
	var size: Vector3 = _house_sizes[variant]
	var center_s := s + lot_w * 0.5
	var hp: Vector3 = p0 + d * center_s + side * (depth + size.z * 0.5)
	var basis := b.basis_facing(-side)
	b.add_instance("house_%d" % variant, Transform3D(basis.scaled(Vector3.ONE * 1.12), hp), 420.0, true)
	b.add_box_collider(hp + Vector3(0, 2.0, 0), Vector3(size.x + 0.5, 4.0, size.z + 2.0), atan2(-basis.x.z, basis.x.x))
	_fence_run(p0 + d * s + side * (hw + vg + CityBuilder.SIDEWALK_W + 1.2), d, lot_w, "brown")
	for k in rng.randi_range(1, 2):
		var tp: Vector3 = p0 + d * (s + rng.randf_range(2.0, lot_w - 2.0)) + side * (hw + vg + CityBuilder.SIDEWALK_W + rng.randf_range(2.5, 5.0))
		b.add_instance("pine_tree", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.65, 0.95)), tp), 450.0, false)
		b.add_cylinder_collider(tp + Vector3(0, 1.5, 0), 0.3, 3.0)


# ---- Hoover St corner shops (traffic stop: Discount Liquors, Last Call Saloon) ------------------------

func _corner_shops() -> void:
	var specs := [
		["Discount Liquors", Rect2(12.0, 14.0, 24.0, 26.0), Vector3(-1, 0, 0), Color("#1D3F9A"), Color("#B9AE98")],
		["Last Call Saloon", Rect2(-36.0, 64.0, 24.0, 26.0), Vector3(1, 0, 0), Color("#1F6B3A"), Color("#8F6F58")],
	]
	for sp in specs:
		var rect: Rect2 = sp[1]
		var face: Vector3 = sp[2]
		_reserved.append(rect)
		var depth := 12.0
		var width := 20.0
		var mesh := _storefront(width, depth, 4.6, sp[4], 0.9, sp[3])
		var c := Vector3(rect.get_center().x, 0, rect.get_center().y)
		_place_building(mesh, c, face, Vector3(width, 4.6, depth), "Shop_" + String(sp[0]).replace(" ", ""))
		# sign text on the band (band centre y 3.35, 0.1 m in front of the band)
		var front: Vector3 = c + face * (depth * 0.5 + 0.23) + Vector3(0, 3.35, 0)
		b.add_label(sp[0], Transform3D(b.basis_facing(face), front), 0.34, Color("#F4F4F0"))
		b._roads.flat(Vector3(c.x + face.x * (depth * 0.5 + 6.0), CityBuilder.ROAD_Y + 0.002, c.z), 12.0, width + 4.0, CityBuilder.C_ASPHALT_LOT)


# ---- distant downtown skyline (seen from the highway) ----------------------------------

func _downtown() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 515
	var variants: Array[String] = []
	for i in 7:
		var floors := r.randi_range(8, 22)
		var w := r.randf_range(22.0, 34.0)
		var dd := r.randf_range(20.0, 30.0)
		var wall := Color(["#8E9AA6", "#A7A39B", "#7F8892", "#B0B3B8", "#9A8F86", "#8794A0", "#B7B2A7"][i])
		var mesh := _apartment(w, dd, floors, wall, 0.22, 0.45)
		var key := "tower_%d" % i
		b._meshes[key] = mesh
		variants.append(key)
	var gx := -1050.0
	while gx < -560.0:
		var gz := -330.0
		while gz < 120.0:
			if r.randf() < 0.8:
				var key: String = variants[r.randi() % variants.size()]
				var pos := Vector3(gx + r.randf_range(-12.0, 12.0), 0, gz + r.randf_range(-12.0, 12.0))
				b.add_instance(key, Transform3D(Basis(Vector3.UP, r.randi_range(0, 3) * PI * 0.5), pos), 2600.0, false)
			gz += 62.0
		gx += 62.0
	# street lights for the downtown block are skipped on purpose (far away, windows give the glow).


# ---- overhead freeway signs ---------------------------------------------------------------------------------------

func _gantry(x: float, text: String, sub: String) -> void:
	var mb := MeshBuilder.new()
	var z := CityLayout.HIGHWAY_Z
	for dz in [-9.5, 9.5]:
		mb.box(Vector3(0, 3.2, dz), Vector3(0.4, 6.4, 0.4), Color("#7A7D82"))
	mb.box(Vector3(0, 6.2, 0), Vector3(0.3, 0.35, 19.4), Color("#7A7D82"))
	mb.box(Vector3(0.2, 5.4, 0), Vector3(0.12, 3.0, 7.0), Color("#0E6B3A"))
	mb.box(Vector3(-0.2, 5.4, 0), Vector3(0.12, 3.0, 7.0), Color("#0E6B3A"))
	b.add_mesh_node("Gantry", mb.to_mesh(b.flat_material), Vector3(x, 0, z), true, 900.0)
	for face in [1.0, -1.0]:
		var t := Transform3D(Basis(Vector3.UP, PI * 0.5 * face), Vector3(x + 0.28 * face, 5.9, z))
		b.add_label(text, t, 0.9, Color.WHITE)
		t.origin.y = 4.9
		b.add_label(sub, t, 0.5, Color.WHITE)
