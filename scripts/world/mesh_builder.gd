class_name MeshBuilder
extends RefCounted
## Flat-shaded low-poly mesh accumulator (vertex colors, per-face normals) used by the procedural city.
## Colors are given in sRGB; materials must enable vertex_color_is_srgb.

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
## Applied to every vertex added afterwards (set/reset to orient parts).
var xf := Transform3D.IDENTITY


func is_empty() -> bool:
	return verts.is_empty()


func _quad_raw(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	# Vertices counter-clockwise when seen from the front side (normal = cross); indices are flipped for Godot.
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	var pd := xf * d
	var n := (pb - pa).cross(pc - pa).normalized()
	var base := verts.size()
	verts.append_array([pa, pb, pc, pd])
	for i in 4:
		normals.append(n)
		colors.append(color)
	indices.append_array([base, base + 2, base + 1, base, base + 3, base + 2])  # Godot front faces are clockwise


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	_quad_raw(a, b, c, d, color)


func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	var n := (pb - pa).cross(pc - pa).normalized()
	var base := verts.size()
	verts.append_array([pa, pb, pc])
	for i in 3:
		normals.append(n)
		colors.append(color)
	indices.append_array([base, base + 2, base + 1])


## Axis-aligned (in local space) box; bottom face optional.
func box(center: Vector3, size: Vector3, color: Color, bottom := false) -> void:
	var h := size * 0.5
	var x0 := center.x - h.x
	var x1 := center.x + h.x
	var y0 := center.y - h.y
	var y1 := center.y + h.y
	var z0 := center.z - h.z
	var z1 := center.z + h.z
	_quad_raw(Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x0, y1, z0), color)  # top
	_quad_raw(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), color.darkened(0.04))  # +z
	_quad_raw(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), color.darkened(0.04))  # -z
	_quad_raw(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), color.darkened(0.08))  # +x
	_quad_raw(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), color.darkened(0.08))  # -x
	if bottom:
		_quad_raw(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), color)


## Flat horizontal quad (top facing) centered at `center`, with width along local X and depth along local Z.
func flat(center: Vector3, width: float, depth: float, color: Color) -> void:
	var hx := width * 0.5
	var hz := depth * 0.5
	_quad_raw(center + Vector3(-hx, 0, hz), center + Vector3(hx, 0, hz), center + Vector3(hx, 0, -hz), center + Vector3(-hx, 0, -hz), color)


## Horizontal strip between two world points (top facing) with the given width; y is taken from the points.
func strip(p0: Vector3, p1: Vector3, width: float, color: Color) -> void:
	var dir := (p1 - p0)
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	var side := Vector3(-dir.z, 0.0, dir.x).normalized() * (width * 0.5)
	# side points to the right of dir (seen from above); winding chosen so the top faces up.
	_quad_raw(p0 + side, p1 + side, p1 - side, p0 - side, color)


## Gable roof over a rectangular footprint; ridge runs along local X.
func gable(center: Vector3, size: Vector3, rise: float, color: Color, overhang := 0.4) -> void:
	var hx := size.x * 0.5 + overhang
	var hz := size.z * 0.5 + overhang
	var y0 := center.y
	var y1 := center.y + rise
	var c := center.x
	_quad_raw(Vector3(c - hx, y0, hz), Vector3(c + hx, y0, hz), Vector3(c + hx, y1, 0), Vector3(c - hx, y1, 0), color)
	_quad_raw(Vector3(c + hx, y0, -hz), Vector3(c - hx, y0, -hz), Vector3(c - hx, y1, 0), Vector3(c + hx, y1, 0), color.darkened(0.06))
	var gx := size.x * 0.5
	var gz := size.z * 0.5
	tri(Vector3(c + gx, center.y, gz), Vector3(c + gx, center.y, -gz), Vector3(c + gx, y1 - 0.0, 0), color.darkened(0.12))
	tri(Vector3(c - gx, center.y, -gz), Vector3(c - gx, center.y, gz), Vector3(c - gx, y1 - 0.0, 0), color.darkened(0.12))


func commit(mesh: ArrayMesh, material: Material) -> void:
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


func to_mesh(material: Material) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	commit(mesh, material)
	return mesh
