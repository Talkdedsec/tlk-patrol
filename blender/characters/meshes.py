"""Low-poly character geometry: soft tubes for body parts, boxes for gear, text plates.

All builders append to a Builder (vertices, faces, per-face material name, per-vertex bone weights).
Weights are looked up by height (z) because every limb hangs straight down at rest.
"""
import math
import bmesh
from mathutils import Vector, Matrix

SEGS = 8
HEAD_DZ = -0.030   # head sits lower than the Head bone midpoint: shorter neck, closer to the target proportions


def hex_linear(h):
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (out[0], out[1], out[2], 1.0)


def piecewise(stops):
    """stops: [(z, {bone: w})...] sorted by z descending or ascending; returns f(z) -> {bone: w}."""
    pts = sorted(stops, key=lambda s: s[0])

    def f(z):
        if z <= pts[0][0]:
            return dict(pts[0][1])
        if z >= pts[-1][0]:
            return dict(pts[-1][1])
        for (z0, w0), (z1, w1) in zip(pts, pts[1:]):
            if z0 <= z <= z1:
                t = (z - z0) / (z1 - z0) if z1 > z0 else 0.0
                out = {}
                for b in set(w0) | set(w1):
                    v = w0.get(b, 0.0) * (1 - t) + w1.get(b, 0.0) * t
                    if v > 1e-4:
                        out[b] = v
                return out
        return dict(pts[-1][1])
    return f


def rigid(bone):
    return lambda z: {bone: 1.0}


class Builder:
    def __init__(self):
        self.verts = []
        self.faces = []      # (vertex indices, material name)
        self.weights = []    # per vertex dict

    def add_verts(self, pts, wfn):
        base = len(self.verts)
        for p in pts:
            self.verts.append(Vector(p))
            self.weights.append(wfn(p[2]))
        return base

    def tube(self, rings, wfn, segs=SEGS, cap_top=True, cap_bottom=True, cap_mat=None):
        """rings: list of dicts {z, c:(x,y), r:(rx,ry), m: material of the band to the NEXT ring}.
        Rings may be listed in any order; they are sorted bottom -> top."""
        rings = sorted(rings, key=lambda r: r["z"])
        idx = []
        for r in rings:
            cx, cy = r.get("c", (0.0, 0.0))
            rx, ry = r["r"]
            pts = []
            for k in range(segs):
                a = 2.0 * math.pi * k / segs
                pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a), r["z"]))
            idx.append(self.add_verts(pts, wfn))
        for i in range(len(rings) - 1):
            mat = rings[i]["m"]
            for k in range(segs):
                k2 = (k + 1) % segs
                a, b = idx[i] + k, idx[i] + k2
                c, d = idx[i + 1] + k2, idx[i + 1] + k
                self.faces.append(((a, b, c, d), mat))
        if cap_bottom:
            self.faces.append((tuple(idx[0] + k for k in reversed(range(segs))), cap_mat or rings[0]["m"]))
        if cap_top:
            self.faces.append((tuple(idx[-1] + k for k in range(segs)), cap_mat or rings[-2]["m"] if len(rings) > 1 else rings[-1]["m"]))

    def box(self, center, size, mat, wfn, taper_front=0.0, rot=None):
        """Axis-aligned box (size = full extents). taper_front narrows the +Y face (shoes)."""
        cx, cy, cz = center
        sx, sy, sz = (s / 2.0 for s in size)
        corners = []
        for ix in (-1, 1):
            for iy in (-1, 1):
                for iz in (-1, 1):
                    k = 1.0 - (taper_front if iy > 0 else 0.0)
                    corners.append((ix * sx * k, iy * sy, iz * sz))
        if rot is not None:
            corners = [tuple(rot @ Vector(c)) for c in corners]
        pts = [(cx + c[0], cy + c[1], cz + c[2]) for c in corners]
        base = self.add_verts(pts, wfn)
        # corner index = ix_bit*4 + iy_bit*2 + iz_bit with bit 0 => -1
        quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        center = Vector(center)
        for q in quads:
            vs = [self.verts[base + i] for i in q]
            normal = (vs[1] - vs[0]).cross(vs[3] - vs[0])
            mid = sum(vs, Vector()) / 4.0 - center
            order = q if normal.dot(mid) > 0 else tuple(reversed(q))
            self.faces.append((tuple(base + i for i in order), mat))

    def ellipsoid(self, center, radii, mat, wfn, rows=6, segs=SEGS, theta_max=None, open_shell=False):
        """UV sphere. theta_max: callable(azimuth) -> polar angle limit (radians) for partial shells (hair)."""
        cx, cy, cz = center
        rx, ry, rz = radii
        grid = []
        top = self.add_verts([(cx, cy, cz + rz)], wfn)
        for i in range(1, rows + 1):
            row = []
            for k in range(segs):
                a = 2.0 * math.pi * k / segs
                tmax = theta_max(a) if theta_max else math.pi
                th = (i / rows) * tmax
                if theta_max is None and i == rows:
                    break
                p = (cx + rx * math.sin(th) * math.cos(a), cy + ry * math.sin(th) * math.sin(a), cz + rz * math.cos(th))
                row.append(p)
            if not row:
                break
            grid.append(self.add_verts(row, wfn))
        if theta_max is None:
            bottom = self.add_verts([(cx, cy, cz - rz)], wfn)
        for k in range(segs):
            k2 = (k + 1) % segs
            self.faces.append(((top, grid[0] + k, grid[0] + k2), mat))
        for i in range(len(grid) - 1):
            for k in range(segs):
                k2 = (k + 1) % segs
                self.faces.append(((grid[i] + k, grid[i + 1] + k, grid[i + 1] + k2, grid[i] + k2), mat))
        if theta_max is None:
            for k in range(segs):
                k2 = (k + 1) % segs
                self.faces.append(((bottom, grid[-1] + k2, grid[-1] + k), mat))

    def raw(self, verts, faces, mat, wfn, matrix=None):
        pts = [tuple(matrix @ Vector(v)) if matrix is not None else tuple(v) for v in verts]
        base = self.add_verts(pts, wfn)
        for f in faces:
            self.faces.append((tuple(base + i for i in f), mat))

    def to_object(self, bpy, name, materials, group_names):
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        dl = bm.verts.layers.deform.verify()
        bverts = [bm.verts.new(v) for v in self.verts]
        gindex = {g: i for i, g in enumerate(group_names)}
        for bv, w in zip(bverts, self.weights):
            total = sum(w.values()) or 1.0
            for bone, val in w.items():
                if bone in gindex:
                    bv[dl][gindex[bone]] = val / total
        mat_slots = {m: i for i, m in enumerate(materials)}
        for vi, mat in self.faces:
            try:
                f = bm.faces.new([bverts[i] for i in vi])
            except ValueError:
                continue
            f.material_index = mat_slots[mat]
            f.smooth = True
        bm.to_mesh(me)
        bm.free()
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        for g in group_names:
            obj.vertex_groups.new(name=g)
        for m in materials:
            me.materials.append(bpy.data.materials[m])
        return obj


def make_material(bpy, name, hex_color, roughness=0.85):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    col = hex_linear(hex_color)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = roughness
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = 0.0
    for key in ("Specular IOR Level", "Specular"):
        if key in bsdf.inputs:
            bsdf.inputs[key].default_value = 0.15
    mat.diffuse_color = col
    return mat


def text_mesh(bpy, text, size, extrude=0.0025):
    """Flat text lying in the XY plane facing +Z; returns (verts, faces) in local space."""
    cu = bpy.data.curves.new("txt", "FONT")
    cu.body = text
    cu.size = size
    cu.extrude = extrude
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.resolution_u = 2
    ob = bpy.data.objects.new("txt", cu)
    bpy.context.scene.collection.objects.link(ob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    verts = [tuple(v.co) for v in me.vertices]
    faces = [tuple(p.vertices) for p in me.polygons]
    bpy.data.objects.remove(ob)
    bpy.data.meshes.remove(me)
    bpy.data.curves.remove(cu)
    return verts, faces


# --- body parts -----------------------------------------------------------------------------------
W_TORSO = piecewise([
    (0.88, {"Hips": 1}), (1.00, {"Hips": 1}), (1.08, {"Hips": 0.5, "Spine": 0.5}),
    (1.16, {"Spine": 1}), (1.25, {"Spine": 0.5, "Chest": 0.5}), (1.34, {"Chest": 1}), (1.50, {"Chest": 1}),
])
W_NECK = piecewise([(1.40, {"Chest": 1}), (1.46, {"Neck": 1}), (1.53, {"Neck": 0.5, "Head": 0.5}), (1.58, {"Head": 1})])
W_HEAD = rigid("Head")


def w_leg(side):
    u, l, f = "UpperLeg_" + side, "LowerLeg_" + side, "Foot_" + side
    return piecewise([
        (1.00, {"Hips": 0.6, u: 0.4}), (0.90, {u: 1}), (0.56, {u: 1}), (0.44, {l: 1}),
        (0.14, {l: 1}), (0.07, {l: 0.5, f: 0.5}),
    ])


def w_arm(side):
    u, l, h = "UpperArm_" + side, "LowerArm_" + side, "Hand_" + side
    return piecewise([
        (1.43, {"Chest": 0.45, u: 0.55}), (1.34, {u: 1}), (1.19, {u: 1}), (1.07, {l: 1}),
        (0.92, {l: 1}), (0.85, {l: 0.5, h: 0.5}), (0.80, {h: 1}),
    ])


def build_torso(b, m_pants, m_shirt, shirt_hem=1.02):
    """Pelvis + torso as one soft tube. Pants band below `shirt_hem`."""
    rings = [
        {"z": 0.88, "r": (0.150, 0.100), "c": (0, 0.0), "m": m_pants},
        {"z": 0.97, "r": (0.168, 0.108), "c": (0, 0.0), "m": m_pants},
        {"z": shirt_hem, "r": (0.158, 0.102), "c": (0, 0.0), "m": m_shirt},
        {"z": 1.08, "r": (0.150, 0.098), "c": (0, 0.0), "m": m_shirt},
        {"z": 1.20, "r": (0.164, 0.104), "c": (0, 0.005), "m": m_shirt},
        {"z": 1.32, "r": (0.184, 0.112), "c": (0, 0.01), "m": m_shirt},
        {"z": 1.40, "r": (0.190, 0.100), "c": (0, 0.0), "m": m_shirt},
        {"z": 1.45, "r": (0.100, 0.075), "c": (0, 0.0), "m": m_shirt},
    ]
    b.tube(rings, W_TORSO, cap_mat=m_shirt)


def build_neck_head(b, m_skin, m_eye, nose=True):
    b.tube([
        {"z": 1.42, "r": (0.052, 0.052), "m": m_skin},
        {"z": 1.56, "r": (0.050, 0.050), "m": m_skin},
    ], W_NECK, cap_bottom=False, cap_top=False)
    b.ellipsoid((0, 0.004, 1.668 + HEAD_DZ), (0.092, 0.104, 0.118), m_skin, W_HEAD, rows=6)
    for sx in (-1, 1):
        b.ellipsoid((sx * 0.093, 0.0, 1.662 + HEAD_DZ), (0.012, 0.022, 0.032), m_skin, W_HEAD, rows=3, segs=6)
        b.box((sx * 0.037, 0.099, 1.688 + HEAD_DZ), (0.020, 0.012, 0.016), m_eye, W_HEAD)
    if nose:
        b.box((0, 0.108, 1.655 + HEAD_DZ), (0.026, 0.026, 0.040), m_skin, W_HEAD, taper_front=0.5)


def build_legs(b, m_upper, m_lower, m_shoe, split_z=0.68, hem_extra=None):
    for side, sx in (("R", 1), ("L", -1)):
        cx = 0.095 * sx
        rings = [
            {"z": 0.99, "c": (cx, 0), "r": (0.090, 0.090), "m": m_upper},
            {"z": 0.80, "c": (cx, 0), "r": (0.082, 0.082), "m": m_upper},
            {"z": split_z, "c": (cx, 0), "r": (0.072, 0.072), "m": m_lower},
            {"z": 0.50, "c": (cx, 0), "r": (0.060, 0.062), "m": m_lower},
            {"z": 0.34, "c": (cx, 0), "r": (0.058, 0.060), "m": m_lower},
            {"z": 0.14, "c": (cx, 0), "r": (0.042, 0.044), "m": m_lower},
            {"z": 0.075, "c": (cx, 0), "r": (0.044, 0.046), "m": m_lower},
        ]
        b.tube(rings, w_leg(side), cap_bottom=False, cap_top=False)
        # shoe: tapered box + ankle cuff
        b.box((cx, 0.045, 0.040), (0.098, 0.285, 0.082), m_shoe, rigid("Foot_" + side), taper_front=0.30)


def build_arms(b, m_upper, m_lower, m_skin, split_z=1.19):
    for side, sx in (("R", 1), ("L", -1)):
        cx = 0.235 * sx
        rings = [
            {"z": 1.425, "c": (cx, 0), "r": (0.058, 0.058), "m": m_upper},
            {"z": 1.30, "c": (cx, 0), "r": (0.052, 0.052), "m": m_upper},
            {"z": split_z, "c": (cx, 0), "r": (0.047, 0.047), "m": m_lower},
            {"z": 1.12, "c": (cx, 0), "r": (0.043, 0.043), "m": m_lower},
            {"z": 0.98, "c": (cx, 0), "r": (0.038, 0.038), "m": m_lower},
            {"z": 0.89, "c": (cx, 0), "r": (0.034, 0.034), "m": m_skin},
        ]
        b.tube(rings, w_arm(side), cap_bottom=False, cap_top=True, cap_mat=m_upper)
        # hand
        b.ellipsoid((cx, 0.005, 0.825), (0.034, 0.030, 0.058), m_skin, rigid("Hand_" + side), rows=4, segs=6)


def build_belt_gear(b, m_gear, m_badge, with_holster=True):
    """Duty belt, holster, magazine pouch, radio, cuff pouch."""
    belt = [
        {"z": 0.975, "r": (0.176, 0.114), "m": m_gear},
        {"z": 1.035, "r": (0.176, 0.114), "m": m_gear},
    ]
    b.tube(belt, rigid("Hips"), cap_bottom=False, cap_top=False)
    if with_holster:
        b.box((0.205, 0.015, 0.865), (0.050, 0.100, 0.170), m_gear, rigid("Hips"))
        b.box((0.205, -0.010, 0.960), (0.038, 0.060, 0.050), m_gear, rigid("Hips"))   # grip stub when holstered
    b.box((-0.075, 0.108, 1.005), (0.060, 0.032, 0.085), m_gear, rigid("Hips"))        # mag pouch
    b.box((-0.145, 0.060, 1.005), (0.060, 0.032, 0.085), m_gear, rigid("Hips"))
    b.box((0.0, -0.120, 1.005), (0.110, 0.030, 0.070), m_gear, rigid("Hips"))          # cuff pouch
    b.box((-0.215, 0.0, 0.970), (0.036, 0.045, 0.120), m_gear, rigid("Hips"))          # flashlight ring


def build_vest(b, m_vest, m_plate, m_text, text, m_badge, height_top=1.425):
    rings = [
        {"z": 1.10, "r": (0.190, 0.122), "c": (0, 0.004), "m": m_vest},
        {"z": 1.22, "r": (0.200, 0.126), "c": (0, 0.008), "m": m_vest},
        {"z": 1.33, "r": (0.208, 0.128), "c": (0, 0.012), "m": m_vest},
        {"z": height_top, "r": (0.160, 0.100), "c": (0, 0.0), "m": m_vest},
    ]
    b.tube(rings, W_TORSO, cap_bottom=False, cap_top=False)
    # back ID plate with lettering (reads correctly from behind)
    b.box((0.0, -0.1365, 1.285), (0.205, 0.010, 0.082), m_plate, rigid("Chest"))
    verts, faces = text_mesh(_BPY[0], text, 0.050 if len(text) <= 6 else 0.040)
    mtx = Matrix.Translation((0.0, -0.1425, 1.285)) @ Matrix.Rotation(math.radians(90), 4, "X")
    b.raw(verts, faces, m_text, rigid("Chest"), mtx)
    # small department line under the lettering
    b.box((0.0, -0.1425, 1.245), (0.090, 0.003, 0.010), m_text, rigid("Chest"))
    # front: radio, badge, mic
    b.box((-0.095, 0.138, 1.300), (0.055, 0.030, 0.085), m_plate, rigid("Chest"))
    b.box((0.090, 0.140, 1.320), (0.040, 0.008, 0.050), m_badge, rigid("Chest"))
    b.box((-0.150, 0.100, 1.390), (0.030, 0.026, 0.040), m_plate, rigid("Chest"))


def build_cap(b, m_cap, m_visor, brim=0.075, hat_z=1.705 + HEAD_DZ, flat=False):
    rows = 4
    b.ellipsoid((0, 0.0, hat_z), (0.106, 0.116, 0.078), m_cap, W_HEAD, rows=rows,
                theta_max=lambda a: math.radians(90))
    # band + visor
    b.tube([
        {"z": hat_z - 0.024, "r": (0.106, 0.116), "m": m_cap},
        {"z": hat_z, "r": (0.107, 0.117), "m": m_cap},
    ], W_HEAD, cap_bottom=False, cap_top=False)
    b.box((0, 0.140, hat_z - 0.018), (0.150, brim, 0.008), m_visor, W_HEAD, taper_front=0.15)


def build_hair_short(b, m_hair):
    def tmax(a):
        s = math.sin(a)
        return math.radians(66 + (112 - 66) * (1 - s) / 2)
    b.ellipsoid((0, 0.0, 1.672 + HEAD_DZ), (0.099, 0.110, 0.124), m_hair, W_HEAD, rows=5, theta_max=tmax)


def build_hair_long(b, m_hair):
    def tmax(a):
        s = math.sin(a)
        return math.radians(66 + (125 - 66) * (1 - s) / 2)
    b.ellipsoid((0, 0.0, 1.672 + HEAD_DZ), (0.100, 0.112, 0.126), m_hair, W_HEAD, rows=5, theta_max=tmax)
    wf = piecewise([(1.30, {"Chest": 0.5, "Neck": 0.5}), (1.46, {"Neck": 1}), (1.56, {"Head": 1})])
    b.tube([
        {"z": 1.34, "c": (0, -0.100), "r": (0.080, 0.028), "m": m_hair},
        {"z": 1.50, "c": (0, -0.098), "r": (0.092, 0.034), "m": m_hair},
        {"z": 1.62, "c": (0, -0.082), "r": (0.098, 0.040), "m": m_hair},
    ], wf, cap_top=False)


_BPY = [None]


def set_bpy(bpy):
    _BPY[0] = bpy
