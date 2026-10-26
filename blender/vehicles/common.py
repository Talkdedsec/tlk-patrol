"""Shared low-poly vehicle builder for Blender (run via blender -b --factory-startup --python <script>).

Conventions (Blender space): +Y is the front of the car, +X is the passenger (right) side, +Z is up,
origin at ground level in the middle of the wheelbase. glTF export turns +Y into Godot -Z (forward).
Node names are the contract with scripts/vehicles/vehicle.gd (see docs/api/vehicles.md).
"""
import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models", "vehicles"))


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def lin(h):
	"""sRGB hex string -> linear RGBA tuple."""
	h = h.lstrip("#")
	rgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
	rgb = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
	return (rgb[0], rgb[1], rgb[2], 1.0)


_mats = {}


def M(name, hexcolor, rough=0.7, metal=0.0, emit=None, emit_strength=0.0, alpha=1.0):
	"""Cached principled material (name must be unique per look)."""
	if name in _mats:
		return _mats[name]
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	bsdf = m.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = lin(hexcolor)
	bsdf.inputs["Roughness"].default_value = rough
	bsdf.inputs["Metallic"].default_value = metal
	if emit:
		bsdf.inputs["Emission Color"].default_value = lin(emit)
		bsdf.inputs["Emission Strength"].default_value = emit_strength
	if alpha < 1.0:
		bsdf.inputs["Alpha"].default_value = alpha
		try:
			m.surface_render_method = "BLENDED"
		except Exception:
			m.blend_method = "BLEND"
	_mats[name] = m
	return m


def clear_mats():
	_mats.clear()


# Common materials -------------------------------------------------------------------------
def std_mats():
	return {
		"black": M("Trim", "#17181c", 0.8),
		"chrome": M("Chrome", "#a3a9b2", 0.25, 0.8),
		"glass": M("Glass", "#0b1016", 0.12, 0.2, alpha=0.62),
		"rubber": M("Rubber", "#0d0d0f", 0.95),
		"rim": M("Rim", "#25262b", 0.5, 0.4),
		"hub": M("HubCap", "#b4b8c0", 0.3, 0.8),
		"white": M("White", "#e6e8ea", 0.55),
		"gold": M("Gold", "#c9a227", 0.45, 0.4),
		"plate": M("Plate", "#eceef2", 0.6),
		"interior": M("Interior", "#202228", 0.9),
		"seat": M("Seat", "#2b2d34", 0.9),
		"well": M("DoorWell", "#08090b", 1.0),
		"undercar": M("Undercar", "#0c0d0f", 1.0),
	}


def lerp(a, b, t):
	return a + (b - a) * t


def chain_z(chain, y):
	"""Height of a (y,z) polyline at y (clamped); chain sorted by y ascending."""
	pts = sorted(chain)
	if y <= pts[0][0]:
		return pts[0][1]
	for (y0, z0), (y1, z1) in zip(pts, pts[1:]):
		if y0 <= y <= y1:
			return lerp(z0, z1, (y - y0) / (y1 - y0)) if y1 > y0 else z1
	return pts[-1][1]


def taper(zlo, zhi, w_lo, w_hi):
	"""Half-width as a function of z, linear between zlo and zhi."""
	def f(z):
		t = 0.0 if zhi == zlo else (z - zlo) / (zhi - zlo)
		return lerp(w_lo, w_hi, max(0.0, min(1.0, t)))
	return f


def _fn(v):
	return v if callable(v) else (lambda z, v=v: v)


class Part:
	"""A bmesh with an auto-managed material list; becomes one object via finish()."""

	def __init__(self):
		self.bm = bmesh.new()
		self.mats = []

	def mi(self, m):
		if m not in self.mats:
			self.mats.append(m)
		return self.mats.index(m)

	def prism(self, profile, xl, xr, mat, edge_mats=None, side_mat=None):
		"""Extrude a side silhouette (list of (y,z)) between x=xl(z) and x=xr(z)."""
		xl, xr = _fn(xl), _fn(xr)
		bm = self.bm
		n = len(profile)
		lv = [bm.verts.new((xl(z), y, z)) for y, z in profile]
		rv = [bm.verts.new((xr(z), y, z)) for y, z in profile]
		faces = []
		sm = self.mi(side_mat or mat)
		f = bm.faces.new(rv)
		f.material_index = sm
		faces.append(f)
		f = bm.faces.new(lv[::-1])
		f.material_index = sm
		faces.append(f)
		for i in range(n):
			j = (i + 1) % n
			f = bm.faces.new((lv[i], lv[j], rv[j], rv[i]))
			f.material_index = self.mi((edge_mats or {}).get(i, mat))
			faces.append(f)
		bmesh.ops.recalc_face_normals(bm, faces=faces)
		return faces

	def box(self, cx, cy, cz, sx, sy, sz, mat, taper_top=0.0):
		"""Axis aligned box; taper_top narrows the x half-width at the top."""
		y0, y1, z0, z1 = cy - sy / 2, cy + sy / 2, cz - sz / 2, cz + sz / 2
		hw = sx / 2
		self.prism([(y0, z0), (y1, z0), (y1, z1), (y0, z1)],
			lambda z: cx - (hw - taper_top * (z - z0) / max(sz, 1e-6)),
			lambda z: cx + (hw - taper_top * (z - z0) / max(sz, 1e-6)), mat)

	def cyl(self, cx, cy, cz, radius, length, axis, mat, segs=14, radius2=None):
		m = Matrix.Identity(4)
		if axis == "x":
			m = Matrix.Rotation(math.radians(90), 4, "Y")
		elif axis == "y":
			m = Matrix.Rotation(math.radians(90), 4, "X")
		m = Matrix.Translation((cx, cy, cz)) @ m
		ret = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segs,
			radius1=radius, radius2=radius if radius2 is None else radius2, depth=length, matrix=m)
		mi = self.mi(mat)
		for v in ret["verts"]:
			for f in v.link_faces:
				f.material_index = mi

	def translate(self, d):
		bmesh.ops.translate(self.bm, verts=self.bm.verts, vec=Vector(d))

	def finish(self, name, loc=(0, 0, 0), origin=None, parent=None):
		"""Create the object; origin (world coords) becomes the object pivot."""
		if origin is not None:
			self.translate((-origin[0], -origin[1], -origin[2]))
			loc = origin
		me = bpy.data.meshes.new(name)
		self.bm.to_mesh(me)
		self.bm.free()
		for m in self.mats:
			me.materials.append(m)
		ob = bpy.data.objects.new(name, me)
		bpy.context.collection.objects.link(ob)
		ob.location = loc
		if parent is not None:
			ob.parent = parent
			ob.matrix_parent_inverse = parent.matrix_world.inverted()
		return ob


def empty(name, loc):
	ob = bpy.data.objects.new(name, None)
	bpy.context.collection.objects.link(ob)
	ob.location = loc
	return ob


# Text ---------------------------------------------------------------------------------------
FACES = {  # face -> (local X axis, local Y axis) of the text plane, local Z = X cross Y is the outward normal
	"right": ((0, 1, 0), (0, 0, 1)),
	"left": ((0, -1, 0), (0, 0, 1)),
	"rear": ((1, 0, 0), (0, 0, 1)),
	"front": ((-1, 0, 0), (0, 0, 1)),
	"top": ((1, 0, 0), (0, 1, 0)),
}


def text(name, body, size, face, pos, mat, extrude=0.004, parent=None, bold=False, spacing=1.0):
	"""Flat 3D lettering lying on a car surface; pos is the text centre in world coordinates."""
	cu = bpy.data.curves.new(name, "FONT")
	cu.body = body
	cu.size = size
	cu.extrude = extrude
	cu.align_x = "CENTER"
	cu.align_y = "CENTER"
	cu.space_character = spacing
	if bold:
		cu.offset = 0.012 * size / 0.1
	tmp = bpy.data.objects.new(name + "_c", cu)
	bpy.context.collection.objects.link(tmp)
	dg = bpy.context.evaluated_depsgraph_get()
	me = bpy.data.meshes.new_from_object(tmp.evaluated_get(dg))
	bpy.data.objects.remove(tmp)
	me.materials.append(mat)
	xa, ya = (Vector(a) for a in FACES[face])
	za = xa.cross(ya)
	r = Matrix(((xa.x, ya.x, za.x), (xa.y, ya.y, za.y), (xa.z, ya.z, za.z))).to_4x4()
	ob = bpy.data.objects.new(name, me)
	bpy.context.collection.objects.link(ob)
	ob.matrix_world = Matrix.Translation(pos) @ r
	if parent is not None:
		ob.parent = parent
		ob.matrix_parent_inverse = parent.matrix_world.inverted()
	return ob


def decal_quad(name, face, pos, w, h, mat, parent=None):
	"""Thin decal plate (shield, stripe) on a surface."""
	p = Part()
	if face in ("right", "left"):
		sx = 0.004
		p.box(0, 0, 0, sx, w, h, mat)
	elif face in ("rear", "front"):
		p.box(0, 0, 0, w, 0.004, h, mat)
	else:
		p.box(0, 0, 0, w, h, 0.004, mat)
	ob = p.finish(name, loc=pos)
	if parent is not None:
		ob.parent = parent
		ob.matrix_parent_inverse = parent.matrix_world.inverted()
	return ob


# Standard car parts -------------------------------------------------------------------------
def tint_dark(hexcolor):
	return hexcolor


def lamp(name, center, size, hexcolor, tint=None, rough=0.3):
	"""Emissive-capable lamp box with its own material (the game script drives emission)."""
	m = bpy.data.materials.new("mat_" + name)
	m.use_nodes = True
	b = m.node_tree.nodes["Principled BSDF"]
	b.inputs["Base Color"].default_value = lin(hexcolor)
	b.inputs["Roughness"].default_value = rough
	p = Part()
	p.box(0, 0, 0, size[0], size[1], size[2], m)
	return p.finish(name, loc=center)


def wheels(sp, mats):
	"""Four wheel objects with the origin at the hub; sp: wb (axle y's), x (half track f,r), r, w."""
	r, w = sp["wr"], sp["ww"]
	out = {}
	for key, (x, y) in {
		"FL": (-sp["track_f"], sp["axle_f"]), "FR": (sp["track_f"], sp["axle_f"]),
		"RL": (-sp["track_r"], sp["axle_r"]), "RR": (sp["track_r"], sp["axle_r"]),
	}.items():
		p = Part()
		side = 1 if x > 0 else -1
		p.cyl(0, 0, 0, r, w, "x", mats["rubber"], segs=16)
		p.cyl(side * (w / 2 + 0.002), 0, 0, r * 0.62, 0.02, "x", mats["rim"], segs=12)
		p.cyl(side * (w / 2 + 0.012), 0, 0, r * 0.22, 0.02, "x", mats["hub"], segs=8)
		out[key] = p.finish("Wheel_" + key, loc=(x, y, r))
	return out


def arches(P, sp, hw_lo, mats):
	"""Dark discs on the body sides behind each wheel to fake wheel wells."""
	r = sp["wr"] + sp.get("arch_extra", 0.05)
	for (x, y) in [(-1, sp["axle_f"]), (1, sp["axle_f"]), (-1, sp["axle_r"]), (1, sp["axle_r"])]:
		xx = x * (hw_lo(sp["wr"]) + 0.004)
		P.cyl(xx, y, sp["wr"] + 0.07, r, 0.008, "x", mats["well"], segs=16)


def cabin_geom(sp):
	"""Greenhouse side silhouette: the upper chain closed down to the base height."""
	c = sp["cabin"]
	pts = list(c["pts"])
	prof = pts[:]
	if pts[0][1] > c["base"] + 1e-4:
		prof = [(pts[0][0], c["base"])] + prof
	if pts[-1][1] > c["base"] + 1e-4:
		prof = prof + [(pts[-1][0], c["base"])]
	return prof


def body(P, sp, mats, paint, roof_paint=None):
	lo = sp["lower"]
	zlo, zhi = min(z for _, z in lo), max(z for _, z in lo)
	hw_lo = taper(zlo, zhi, sp["hw_lo"][0], sp["hw_lo"][1])
	P.prism(lo, lambda z: -hw_lo(z), hw_lo, paint)
	c = sp["cabin"]
	prof = cabin_geom(sp)
	n = len(prof)
	roof_z = max(z for _, z in c["pts"])
	hw_c = taper(c["base"], roof_z, c["hw"][0], c["hw"][1])
	edge = {}
	for i in range(n):
		(y0, z0), (y1, z1) = prof[i], prof[(i + 1) % n]
		if i == n - 1:
			edge[i] = mats["black"]  # closing edge at the base
		elif min(z0, z1) >= roof_z - 0.06 or (abs(z1 - z0) < 0.05 and z0 > c["base"] + 0.05):
			edge[i] = roof_paint or paint  # roof
		else:
			edge[i] = mats["glass"]
	if c.get("solid_sides"):  # cargo vans: painted sides, only the listed end faces stay glazed
		keep = c.get("glass_edges_only")
		for i in range(n):
			if edge[i] is mats["glass"] and keep is not None and i not in keep:
				edge[i] = paint
	P.prism(prof, lambda z: -hw_c(z), hw_c, paint, edge_mats=edge, side_mat=paint if c.get("solid_sides") else mats["glass"])
	for y, wd in c.get("pillars", []):
		zt = chain_z(c["pts"], y)
		pp = [(y - wd / 2, c["base"] + 0.01), (y + wd / 2, c["base"] + 0.01), (y + wd / 2, zt), (y - wd / 2, zt)]
		for sd in (-1, 1):
			P.prism(pp, lambda z, sd=sd: sd * (hw_c(z) - 0.01), lambda z, sd=sd: sd * (hw_c(z) + 0.016), mats["black"])
	return hw_lo, hw_c


def door(sp, mats, key, hw_lo, hw_c, paint, y_front, y_back, zb, zt, panel_paint=None, glass_top=True, band=None):
	"""Hinged door with its pivot at the front edge. Returns the object (decals may be parented)."""
	side = -1 if key[1] == "L" else 1
	c = sp["cabin"]
	roof_z = max(z for _, z in c["pts"])
	hwc = taper(c["base"], roof_z, c["hw"][0], c["hw"][1])
	p = Part()
	pm = panel_paint or paint
	prof = [(y_back, zb), (y_front, zb), (y_front, zt), (y_back, zt)]
	if band:  # (z split, material): lower part of the panel gets the band material
		zs, bm_ = band
		p.prism([(y_back, zb), (y_front, zb), (y_front, zs), (y_back, zs)], lambda z: side * (hw_lo(z) + 0.034),
			lambda z: side * (hw_lo(z) - 0.012), bm_)
		prof = [(y_back, zs), (y_front, zs), (y_front, zt), (y_back, zt)]
	p.prism(prof, lambda z: side * (hw_lo(z) + 0.034), lambda z: side * (hw_lo(z) - 0.012), pm)
	p.box(side * (hw_lo(zt - 0.12) + 0.045), y_back + 0.16, zt - 0.1, 0.02, 0.12, 0.03, mats["chrome"])
	if glass_top:
		m = 0.05
		ya, yb = y_back + m, y_front - m
		mid = [(yy, zz) for yy, zz in sorted(c["pts"]) if ya < yy < yb]
		top = lambda y: chain_z(c["pts"], y) - 0.05
		wp = [(ya, zt + 0.02), (yb, zt + 0.02), (yb, top(yb))] + [(yy, top(yy)) for yy, _ in reversed(mid)] + [(ya, top(ya))]
		p.prism(wp, lambda z: side * (hwc(z) + 0.03), lambda z: side * (hwc(z) + 0.004), mats["glass"])
	hinge = (side * (hw_lo(zt) + 0.01), y_front, 0.0)
	ob = p.finish("Door_" + key, origin=hinge)
	return ob


def door_well(P, mats, hw_lo, side, y_front, y_back, zb, zt):
	prof = [(y_back, zb), (y_front, zb), (y_front, zt), (y_back, zt)]
	P.prism(prof, lambda z: side * (hw_lo(z) - 0.004), lambda z: side * (hw_lo(z) + 0.01), mats["well"])


def side_band(P, hw_lo, y0, y1, z0, z1, mat, out=0.006):
	"""Flat slab on both body sides (livery band, stripe)."""
	prof = [(y0, z0), (y1, z0), (y1, z1), (y0, z1)]
	for sd in (-1, 1):
		P.prism(prof, lambda z, sd=sd: sd * (hw_lo(z) - 0.002), lambda z, sd=sd: sd * (hw_lo(z) + out), mat)


def plate(name, center, face, w=0.31, h=0.155):
	m = M("Plate", "#eceef2", 0.6)
	p = Part()
	if face in ("rear", "front"):
		p.box(0, 0, 0, w, 0.012, h, m)
	return p.finish(name, loc=center)


def interior(sp, mats):
	"""Dark dash, seats and wheel inside the greenhouse (visible through the glass)."""
	i = sp["interior"]
	P = Part()
	k, s, st = mats["interior"], mats["seat"], mats["black"]
	zf = i["floor"]
	P.box(0, i["y_mid"], zf + 0.02, i["w"], i["len"], 0.04, k)
	P.box(0, i["dash_y"], zf + 0.38, i["w"], 0.35, 0.34, k)
	for row_y in i["rows"]:
		for x in i.get("seat_x", (-0.38, 0.38)):
			P.box(x, row_y, zf + 0.30, 0.46, 0.5, 0.2, s)
			P.box(x, row_y - 0.28, zf + 0.58, 0.46, 0.12, 0.5, s)
	P.box(0, i["rows"][-1] - 0.03, zf + 0.3, 1.2, 0.5, 0.2, s) if i.get("bench") else None
	P.cyl(-0.38, i["dash_y"] - 0.2, zf + 0.62, 0.17, 0.03, "y", st, segs=10)
	return P.finish("Interior")


def markers(sp, hw_lo):
	zf = sp["interior"]["floor"]
	ry = sp["interior"]["rows"][0]
	door_y = sp["door_mid_y"]
	hl = hw_lo(0.5)
	empty("Seat_Driver", (-0.38, ry, zf + 0.35))
	empty("Seat_Passenger", (0.38, ry, zf + 0.35))
	empty("Enter_Driver", (-hl - 0.75, door_y, 0.0))
	empty("Enter_Passenger", (hl + 0.75, door_y, 0.0))
	empty("Cam_Target", (0, 0, sp["height"] * 0.8))


def els_cells(spec, tint_l="#401318", tint_r="#13203f"):
	"""spec: list of (index, center, size). Left half (x<0) reddish base, right bluish."""
	for idx, c, s in spec:
		lamp("ELS_CELL_%d" % idx, c, s, tint_l if c[0] < 0 else tint_r, rough=0.25)


def lightbar(cx, cy, z, width, depth, h, mats, start=0, n=10, housing_h=0.04, advisor=True):
	"""Roof light bar: black housing with n wrap-around lenses ELS_CELL_<start+i>, left to right."""
	P = Part()
	P.box(cx, cy, z + housing_h / 2, width + 0.06, depth + 0.02, housing_h, mats["black"])
	P.finish("LightBar_Housing")
	cw = width / n
	for i in range(n):
		x = cx - width / 2 + cw * (i + 0.5)
		lamp("ELS_CELL_%d" % (start + i), (x, cy, z + housing_h + h / 2), (cw - 0.012, depth, h),
			"#401318" if x < cx else "#13203f", rough=0.25)
	if advisor:  # traffic advisor: 8 amber cells on the rear face of the bar, driven by Els.traffic_colors
		aw = width * 0.8 / 8
		for i in range(8):
			x = cx - width * 0.4 + aw * (i + 0.5)
			lamp("ELS_TRAFFIC_%d" % i, (x, cy - depth / 2 - 0.03, z + housing_h * 0.9), (aw - 0.004, 0.05, housing_h * 1.8), "#4a3206", rough=0.25)


def export(name):
	os.makedirs(OUT_DIR, exist_ok=True)
	path = os.path.join(OUT_DIR, name + ".glb")
	for o in bpy.data.objects:
		o.select_set(False)
	bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True,
		export_cameras=False, export_lights=False, export_yup=True)
	print("EXPORTED", path, "objects:", len(bpy.data.objects))
