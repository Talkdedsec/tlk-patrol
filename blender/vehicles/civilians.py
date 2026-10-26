"""Civilian traffic vehicles: sedan, hatchback, pickup, van, box truck. Recolour via the `Paint` material at runtime.
Run: blender -b --factory-startup --python blender/vehicles/civilians.py
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

CARS = {}

CARS["civ_sedan"] = dict(
	height=1.42, axle_f=1.4, axle_r=-1.35, track_f=0.78, track_r=0.78, wr=0.33, ww=0.22,
	lower=[(-2.28, 0.30), (-2.33, 0.55), (-2.30, 0.98), (-1.4, 1.0), (1.1, 0.98), (1.9, 0.9), (2.25, 0.72), (2.30, 0.5),
		(2.2, 0.3), (1.8, 0.24), (-1.9, 0.24)],
	hw_lo=(0.85, 0.88),
	cabin=dict(base=0.98, pts=[(-1.35, 0.98), (-0.8, 1.36), (0.35, 1.40), (1.15, 0.98)], hw=(0.78, 0.68), pillars=[(-0.1, 0.11)]),
	interior=dict(floor=0.34, y_mid=-0.2, w=1.4, len=2.8, dash_y=0.95, rows=[0.2, -0.7], bench=True),
	doors=[("FL", -1, 0.9, -0.05), ("FR", 1, 0.9, -0.05), ("RL", -1, -0.15, -1.05), ("RR", 1, -0.15, -1.05)],
	door_z=(0.32, 0.97), door_mid_y=0.4,
	head=((0.62, 2.29, 0.72), (0.32, 0.05, 0.1)), tail=((0.7, -2.325, 0.9), (0.3, 0.04, 0.1)),
	brake=((0.42, -2.33, 0.84), (0.22, 0.04, 0.08)), plate_r=(0, -2.34, 0.62), plate_f=(0, 2.33, 0.45),
	bumpers=[(0, -2.32, 0.42, 1.7, 0.08, 0.22), (0, 2.28, 0.40, 1.7, 0.08, 0.2)],
)

CARS["civ_hatchback"] = dict(
	height=1.5, axle_f=1.2, axle_r=-1.15, track_f=0.74, track_r=0.74, wr=0.31, ww=0.2,
	lower=[(-1.95, 0.32), (-1.98, 0.6), (-1.95, 1.0), (1.0, 1.0), (1.6, 0.9), (1.92, 0.7), (1.95, 0.48), (1.85, 0.3),
		(1.5, 0.24), (-1.6, 0.24)],
	hw_lo=(0.82, 0.85),
	cabin=dict(base=1.0, pts=[(-1.93, 1.0), (-1.72, 1.46), (0.3, 1.5), (1.0, 1.0)], hw=(0.78, 0.7), pillars=[(-0.05, 0.1)]),
	interior=dict(floor=0.34, y_mid=-0.2, w=1.35, len=2.4, dash_y=0.8, rows=[0.15, -0.65], bench=True),
	doors=[("FL", -1, 0.75, -0.1), ("FR", 1, 0.75, -0.1), ("RL", -1, -0.15, -0.95), ("RR", 1, -0.15, -0.95)],
	door_z=(0.32, 0.98), door_mid_y=0.3,
	head=((0.55, 1.96, 0.7), (0.3, 0.05, 0.12)), tail=((0.72, -1.99, 0.92), (0.1, 0.04, 0.26)),
	brake=((0.72, -1.99, 0.66), (0.1, 0.04, 0.12)), plate_r=(0, -2.0, 0.66), plate_f=(0, 1.98, 0.42),
	bumpers=[(0, -1.97, 0.42, 1.55, 0.08, 0.2), (0, 1.93, 0.40, 1.55, 0.08, 0.2)],
)

CARS["civ_pickup"] = dict(
	height=1.8, axle_f=1.65, axle_r=-1.6, track_f=0.86, track_r=0.86, wr=0.38, ww=0.26,
	lower=[(-0.35, 0.30), (2.2, 0.30), (2.55, 0.38), (2.62, 0.62), (2.56, 0.95), (2.1, 1.06), (1.1, 1.10), (-0.35, 1.10)],
	hw_lo=(0.93, 0.95),
	cabin=dict(base=1.1, pts=[(-0.4, 1.76), (0.55, 1.80), (1.2, 1.1)], hw=(0.88, 0.78), pillars=[]),
	interior=dict(floor=0.42, y_mid=0.3, w=1.65, len=1.6, dash_y=1.05, rows=[0.3], bench=False),
	doors=[("FL", -1, 0.85, -0.2), ("FR", 1, 0.85, -0.2)],
	door_z=(0.38, 1.08), door_mid_y=0.35, bed=(-0.45, -2.62, 0.78),
	head=((0.7, 2.62, 0.82), (0.36, 0.06, 0.14)), tail=((0.9, -2.64, 1.0), (0.1, 0.05, 0.26)),
	brake=((0.9, -2.64, 0.78), (0.1, 0.05, 0.1)), plate_r=(0, -2.72, 0.55), plate_f=(0, 2.7, 0.45),
	bumpers=[(0, -2.7, 0.55, 1.95, 0.12, 0.28), (0, 2.68, 0.5, 1.95, 0.12, 0.3)],
)

CARS["civ_van"] = dict(
	height=2.12, axle_f=1.7, axle_r=-1.7, track_f=0.88, track_r=0.88, wr=0.36, ww=0.24,
	lower=[(-2.65, 0.35), (-2.7, 0.6), (-2.68, 1.0), (1.7, 1.0), (2.3, 0.95), (2.62, 0.75), (2.65, 0.5), (2.55, 0.3),
		(2.2, 0.26), (-2.3, 0.26)],
	hw_lo=(0.96, 1.0),
	cabin=dict(base=1.0, pts=[(-2.66, 2.05), (-2.5, 2.1), (1.3, 2.12), (2.05, 1.0)], hw=(0.97, 0.92), pillars=[],
		solid_sides=True, glass_edges_only=[3]),
	interior=dict(floor=0.4, y_mid=0.9, w=1.7, len=1.8, dash_y=1.6, rows=[1.2], bench=False),
	doors=[("FL", -1, 1.7, 0.6), ("FR", 1, 1.7, 0.6)],
	door_z=(0.34, 1.0), door_mid_y=1.15,
	head=((0.7, 2.64, 0.78), (0.34, 0.06, 0.14)), tail=((0.93, -2.7, 1.0), (0.1, 0.05, 0.34)),
	brake=((0.93, -2.7, 0.7), (0.1, 0.05, 0.1)), plate_r=(0, -2.75, 0.6), plate_f=(0, 2.68, 0.45),
	bumpers=[(0, -2.74, 0.5, 2.0, 0.1, 0.24), (0, 2.66, 0.45, 2.0, 0.1, 0.24)],
)

CARS["civ_boxtruck"] = dict(
	height=2.8, axle_f=1.9, axle_r=-1.7, track_f=0.92, track_r=0.92, wr=0.42, ww=0.3,
	lower=[(0.4, 0.34), (3.2, 0.34), (3.38, 0.5), (3.38, 0.9), (3.2, 1.1), (0.4, 1.1)],
	hw_lo=(1.0, 1.0),
	cabin=dict(base=1.1, pts=[(0.4, 1.9), (2.55, 1.95), (3.15, 1.1)], hw=(0.96, 0.9), pillars=[]),
	interior=dict(floor=0.5, y_mid=1.6, w=1.7, len=1.7, dash_y=2.7, rows=[1.7], bench=False),
	doors=[("FL", -1, 2.55, 1.15), ("FR", 1, 2.55, 1.15)],
	door_z=(0.38, 1.1), door_mid_y=1.9, box=(0.15, -3.45, 0.78, 2.78, 1.05), arch=False,
	head=((0.72, 3.39, 0.7), (0.34, 0.05, 0.14)), tail=((1.0, -3.47, 1.0), (0.1, 0.05, 0.3)),
	brake=((1.0, -3.47, 0.7), (0.1, 0.05, 0.1)), plate_r=(0, -3.5, 0.6), plate_f=(0, 3.4, 0.45),
	bumpers=[(0, -3.5, 0.55, 2.0, 0.12, 0.26), (0, 3.4, 0.42, 1.9, 0.1, 0.22)],
)


CARS["civ_wagon"] = dict(
	height=1.62, axle_f=1.45, axle_r=-1.4, track_f=0.8, track_r=0.8, wr=0.33, ww=0.22, rack=True, default_paint="#6c7178",
	lower=[(-2.4, 0.30), (-2.45, 0.55), (-2.42, 1.0), (1.2, 0.98), (1.95, 0.9), (2.3, 0.72), (2.35, 0.5),
		(2.25, 0.3), (1.85, 0.24), (-2.0, 0.24)],
	hw_lo=(0.87, 0.9),
	cabin=dict(base=0.98, pts=[(-2.38, 0.98), (-2.3, 1.5), (0.35, 1.54), (1.2, 0.98)], hw=(0.8, 0.74), pillars=[(-0.1, 0.11), (-1.25, 0.12)]),
	interior=dict(floor=0.34, y_mid=-0.5, w=1.45, len=3.4, dash_y=1.0, rows=[0.25, -0.75], bench=True),
	doors=[("FL", -1, 0.95, -0.05), ("FR", 1, 0.95, -0.05), ("RL", -1, -0.1, -1.15), ("RR", 1, -0.1, -1.15)],
	door_z=(0.32, 0.97), door_mid_y=0.45,
	head=((0.64, 2.34, 0.72), (0.32, 0.05, 0.1)), tail=((0.78, -2.45, 0.92), (0.1, 0.04, 0.3)),
	brake=((0.78, -2.45, 0.66), (0.1, 0.04, 0.12)), plate_r=(0, -2.47, 0.6), plate_f=(0, 2.37, 0.45),
	bumpers=[(0, -2.45, 0.42, 1.75, 0.08, 0.22), (0, 2.31, 0.40, 1.75, 0.08, 0.2)],
)


def build(vid, sp):
	reset()
	clear_mats()
	mats = std_mats()
	paint = M("Paint", sp.get("default_paint", "#c8cdd2"), 0.45, 0.15)
	P = Part()
	hw_lo, hw_c = body(P, sp, mats, paint)
	if sp.get("arch", True):
		arches(P, sp, hw_lo, mats)
	zb, zt = sp["door_z"]
	for key, sd, yf, yb in sp["doors"]:
		door_well(P, mats, hw_lo, sd, yf, yb, zb, zt)
	for b in sp["bumpers"]:
		P.box(*b, mats["black"])
	P.box(0, 0, 0.2, 1.6, sp["lower"][0][0] - sp["lower"][-1][0] if False else 3.8, 0.08, mats["undercar"]) if False else None
	if "bed" in sp:
		y0, y1, zf = sp["bed"]
		yc, ln = (y0 + y1) / 2, abs(y0 - y1)
		P.box(0, yc, zf, 1.85, ln, 0.07, mats["interior"])
		for sd in (-1, 1):
			P.box(sd * 0.91, yc, zf + 0.2, 0.1, ln, 0.4, paint)
			P.box(sd * 0.62, sp["axle_r"], zf + 0.1, 0.32, 0.85, 0.2, mats["black"])
		P.box(0, y0 - 0.05, zf + 0.25, 1.85, 0.1, 0.5, paint)
		P.box(0, y1 + 0.04, zf + 0.2, 1.85, 0.08, 0.4, paint)
		side_band(P, hw_lo, y0, y1, 0.42, zf, paint, out=0.002)
	if "box" in sp:
		y0, y1, z0, z1, hw = sp["box"]
		boxm = M("Box", "#dfe2e5", 0.5)
		P.prism([(y1, z0), (y0, z0), (y0, z1), (y1, z1)], -hw, hw, boxm)
		for sd in (-1, 1):
			P.box(sd * 0.45, (y0 + y1) / 2 - 0.2, 0.55, 0.14, abs(y0 - y1) - 0.3, 0.2, mats["black"])
		P.box(0, y1 - 0.003, (z0 + z1) / 2, 0.02, 0.01, z1 - z0 - 0.1, mats["black"])
	if sp.get("rack"):  # roof rack: two rails and three cross bars
		rz = max(z for _, z in sp["cabin"]["pts"]) + 0.07
		for sd in (-1, 1):
			P.cyl(sd * 0.68, -0.85, rz, 0.022, 2.6, "y", mats["black"], segs=6)
			for yy in (-2.0, -0.85, 0.3):
				P.cyl(sd * 0.68, yy, rz - 0.035, 0.02, 0.07, "z", mats["black"], segs=6)
		for yy in (-2.0, -0.85, 0.3):
			P.cyl(0, yy, rz, 0.022, 1.4, "x", mats["black"], segs=6)
	P.finish("Body")
	interior(sp, mats)
	wheels(sp, mats)
	for key, sd, yf, yb in sp["doors"]:
		door(sp, mats, key, hw_lo, hw_c, paint, yf, yb, zb, zt)
	(hx, hy, hz), hs = sp["head"]
	lamp("Headlight_L", (-hx, hy, hz), hs, "#cfd3d9")
	lamp("Headlight_R", (hx, hy, hz), hs, "#cfd3d9")
	(tx, ty, tz), ts = sp["tail"]
	lamp("Taillight_L", (-tx, ty, tz), ts, "#4a0a0f")
	lamp("Taillight_R", (tx, ty, tz), ts, "#4a0a0f")
	(bx, by, bz), bs = sp["brake"]
	lamp("BrakeLight_L", (-bx, by, bz), bs, "#4a0a0f")
	lamp("BrakeLight_R", (bx, by, bz), bs, "#4a0a0f")
	plate("Plate_Rear", sp["plate_r"], "rear")
	plate("Plate_Front", sp["plate_f"], "front")
	markers(sp, hw_lo)
	export(vid)


for _vid, _sp in CARS.items():
	build(_vid, _sp)
