"""Hand-held props. Origin = grip centre, barrel/forward = +Y, top = +Z (socket bones share this frame)."""
import math
from mathutils import Matrix, Vector

import meshes as M

PROP_COLORS = {
    "metal": "#1B1D21", "gunmetal": "#2B2E34", "grip": "#101113", "taser_yellow": "#E3BE1C",
    "steel": "#A4AAB2", "lens": "#FFF3B8", "optic": "#0A0B0D",
}
NONE = lambda z: {}


def cyl_y(b, c, length, radius, mat, segs=8):
    """Cylinder along Y starting at c (centre of the rear face)."""
    verts, faces = [], []
    for ring in (0.0, length):
        for k in range(segs):
            a = 2 * math.pi * k / segs
            verts.append((c[0] + radius * math.cos(a), c[1] + ring, c[2] + radius * math.sin(a)))
    for k in range(segs):
        k2 = (k + 1) % segs
        faces.append((k, segs + k, segs + k2, k2))
    faces.append(tuple(reversed(range(segs))))
    faces.append(tuple(segs + k for k in range(segs)))
    b.raw(verts, faces, mat, NONE)


def pistol():
    b = M.Builder()
    b.box((0, 0.0, -0.040), (0.032, 0.060, 0.120), "grip", NONE)
    b.box((0, 0.060, 0.030), (0.030, 0.230, 0.036), "gunmetal", NONE)       # slide
    b.box((0, 0.150, 0.004), (0.020, 0.080, 0.020), "metal", NONE)          # frame / rail
    b.box((0, 0.040, -0.018), (0.014, 0.050, 0.030), "metal", NONE)         # trigger guard
    return b, ["grip", "gunmetal", "metal"]


def rifle():
    b = M.Builder()
    b.box((0, 0.0, -0.045), (0.034, 0.055, 0.110), "grip", NONE)
    b.box((0, 0.080, 0.030), (0.048, 0.360, 0.075), "metal", NONE)          # receiver
    b.box((0, -0.200, 0.010), (0.044, 0.230, 0.090), "grip", NONE)          # stock
    b.box((0, 0.400, 0.025), (0.052, 0.250, 0.060), "gunmetal", NONE)       # handguard
    cyl_y(b, (0, 0.520, 0.025), 0.180, 0.011, "metal")                      # barrel
    cyl_y(b, (0, 0.030, 0.108), 0.150, 0.026, "optic")                      # optic tube
    b.box((0, 0.030, 0.075), (0.020, 0.040, 0.030), "metal", NONE)          # optic mount
    b.box((0, 0.150, -0.050), (0.030, 0.050, 0.120), "metal", NONE)         # magazine
    return b, ["metal", "gunmetal", "grip", "optic"]


def shotgun():
    b = M.Builder()
    b.box((0, 0.0, -0.045), (0.034, 0.055, 0.110), "grip", NONE)
    b.box((0, 0.060, 0.025), (0.050, 0.240, 0.070), "metal", NONE)          # receiver
    b.box((0, -0.220, 0.000), (0.046, 0.250, 0.095), "grip", NONE)          # stock
    cyl_y(b, (0, 0.170, 0.040), 0.560, 0.013, "gunmetal")                   # barrel
    cyl_y(b, (0, 0.170, 0.000), 0.440, 0.013, "metal")                      # magazine tube
    b.box((0, 0.400, -0.005), (0.040, 0.170, 0.040), "grip", NONE)          # pump
    return b, ["metal", "gunmetal", "grip"]


def flashlight():
    b = M.Builder()
    cyl_y(b, (0, -0.090, 0.0), 0.190, 0.018, "metal")
    cyl_y(b, (0, 0.100, 0.0), 0.050, 0.028, "steel")
    cyl_y(b, (0, 0.150, 0.0), 0.004, 0.022, "lens")
    return b, ["metal", "steel", "lens"]


def taser():
    b = M.Builder()
    b.box((0, 0.0, -0.045), (0.034, 0.055, 0.110), "grip", NONE)
    b.box((0, 0.060, 0.030), (0.046, 0.200, 0.055), "taser_yellow", NONE)
    b.box((0, 0.180, 0.026), (0.030, 0.050, 0.030), "metal", NONE)
    return b, ["grip", "taser_yellow", "metal"]


def handcuffs():
    b = M.Builder()
    for sx in (-1, 1):
        b.tube([
            {"z": -0.020, "c": (sx * 0.055, 0), "r": (0.030, 0.014), "m": "steel"},
            {"z": 0.020, "c": (sx * 0.055, 0), "r": (0.030, 0.014), "m": "steel"},
        ], NONE)
    b.box((0, 0, 0), (0.060, 0.010, 0.010), "steel", NONE)
    return b, ["steel"]


def build(bpy, out_dir, export, reset, make_materials):
    import os
    reset()
    make_materials(PROP_COLORS)
    objs = []
    for name, fn in (("Pistol", pistol), ("PatrolRifle", rifle), ("Shotgun", shotgun),
                     ("Flashlight", flashlight), ("Taser", taser), ("Handcuffs", handcuffs)):
        builder, mats = fn()
        obj = builder.to_object(bpy, name, mats, [])
        objs.append(obj)
    export(os.path.join(out_dir, "props.glb"), objs)
