"""County sheriff pickup (GENERAL T-150 style crew cab): navy upper, white lower band, roll cage, cab roof bar, 214.
Run: blender -b --factory-startup --python blender/vehicles/sheriff_pickup.py
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

SP = dict(
	height=1.9, axle_f=2.05, axle_r=-1.7, track_f=0.88, track_r=0.88, wr=0.40, ww=0.3,
	lower=[(-0.9, 0.30), (2.75, 0.30), (3.08, 0.38), (3.16, 0.65), (3.10, 0.98), (2.6, 1.10), (1.25, 1.14), (-0.9, 1.14)],
	hw_lo=(0.97, 1.0),
	cabin=dict(base=1.14, pts=[(-0.95, 1.84), (0.6, 1.88), (1.35, 1.14)], hw=(0.92, 0.80), pillars=[(-0.075, 0.13)]),
	interior=dict(floor=0.42, y_mid=0.1, w=1.7, len=2.2, dash_y=1.1, rows=[0.3, -0.5], bench=True),
	door_mid_y=0.4,
)


def build():
	reset()
	clear_mats()
	mats = std_mats()
	paint = M("Paint", "#1b2440", 0.4, 0.2)
	band = M("Band", "#dcdee1", 0.5)
	P = Part()
	hw_lo, hw_c = body(P, SP, mats, paint)
	arches(P, SP, hw_lo, mats)
	for sd in (-1, 1):
		door_well(P, mats, hw_lo, sd, 0.85, -0.05, 0.40, 1.12)
		door_well(P, mats, hw_lo, sd, -0.1, -0.9, 0.40, 1.12)
	# white lower band and gold pinstripe along the front section, bed skirt
	side_band(P, hw_lo, 2.8, 0.88, 0.40, 0.76, band)
	side_band(P, hw_lo, -0.12, -0.12 - 0.0, 0.40, 0.76, band) if False else None
	side_band(P, hw_lo, -0.9, -2.75, 0.40, 0.76, band)
	side_band(P, hw_lo, 2.8, -2.75, 0.76, 0.785, mats["gold"], out=0.007)
	# bed
	P.box(0, -1.85, 0.8, 1.9, 1.95, 0.07, mats["interior"])
	for sd in (-1, 1):
		P.box(sd * 0.955, -1.85, 0.98, 0.1, 1.95, 0.4, paint)
		P.box(sd * 0.63, -1.7, 0.9, 0.34, 0.9, 0.2, mats["black"])  # wheel wells
	P.box(0, -0.97, 1.0, 1.9, 0.1, 0.45, paint)  # headboard
	P.box(0, -2.80, 0.98, 1.9, 0.08, 0.4, paint)  # tailgate
	P.box(0, -2.88, 0.55, 2.0, 0.14, 0.30, mats["black"])  # rear bumper
	P.box(0, 3.2, 0.50, 2.0, 0.12, 0.32, mats["black"])  # front bumper
	P.box(0, 3.19, 0.78, 1.1, 0.04, 0.2, mats["well"])  # grille
	P.box(0, -0.2, 0.22, 1.8, 5.2, 0.08, mats["undercar"])
	# bull bar and roll cage
	t = 0.028
	for x in (-0.55, 0.55):
		P.cyl(x, 3.3, 0.75, t, 0.7, "z", mats["black"], segs=6)
	P.cyl(0, 3.3, 0.62, t, 1.15, "x", mats["black"], segs=6)
	P.cyl(0, 3.3, 0.98, t, 1.15, "x", mats["black"], segs=6)
	for sd in (-1, 1):
		P.cyl(sd * 0.85, -1.85, 1.62, t, 1.65, "y", mats["black"], segs=6)
		for y in (-1.05, -2.65):
			P.cyl(sd * 0.85, y, 1.4, t, 0.5, "z", mats["black"], segs=6)
	P.cyl(0, -2.65, 1.62, t, 1.7, "x", mats["black"], segs=6)
	P.cyl(0, -1.05, 1.62, t, 1.7, "x", mats["black"], segs=6)
	P.finish("Body")
	interior(SP, mats)
	wheels(SP, mats)
	text("Decal_Roof", "214", 0.72, "top", (0, -0.1, 1.89), M("TextWhite", "#e8eaec", 0.7), extrude=0.006, bold=True)
	dark = M("TextNavy", "#18203a", 0.7)
	gold = mats["gold"]
	for key, sd, yf, yb in (("FL", -1, 0.85, -0.05), ("FR", 1, 0.85, -0.05), ("RL", -1, -0.1, -0.9), ("RR", 1, -0.1, -0.9)):
		d = door(SP, mats, key, hw_lo, hw_c, paint, yf, yb, 0.40, 1.12, band=(0.76, band))
		x = sd * (hw_lo(0.6) + 0.0365)
		face = "left" if sd < 0 else "right"
		ym = (yf + yb) / 2
		if key in ("FL", "FR"):
			text("Decal_Sheriff_" + key, "BUSCO COUNTY SHERIFF", 0.075, face, (x, ym - 0.02, 0.58), dark, parent=d, bold=True)
			cp = Part()
			cp.cyl(0, 0, 0, 0.075, 0.006, "x", gold, segs=6)
			sb = cp.finish("Decal_Star_" + key, loc=(sd * (hw_lo(0.9) + 0.037), ym, 0.93))
			sb.parent = d
			sb.matrix_parent_inverse = d.matrix_world.inverted()
	rear = (0, -2.846, 1.0)
	text("Decal_Tailgate", "GENERAL", 0.2, "rear", (0, -2.846, 1.0), M("TextChrome", "#b9bec6", 0.35, 0.8), extrude=0.008, bold=True)
	text("Decal_TailgateModel", "T-150", 0.08, "rear", (0.65, -2.846, 0.86), M("TextChrome", "#b9bec6", 0.35, 0.8))
	text("Decal_TailgateSheriff", "SHERIFF", 0.07, "rear", (-0.6, -2.846, 0.86), gold)
	lamp("Headlight_L", (-0.74, 3.18, 0.86), (0.4, 0.06, 0.16), "#cfd3d9")
	lamp("Headlight_R", (0.74, 3.18, 0.86), (0.4, 0.06, 0.16), "#cfd3d9")
	lamp("Taillight_L", (-0.93, -2.845, 1.02), (0.12, 0.05, 0.3), "#4a0a0f")
	lamp("Taillight_R", (0.93, -2.845, 1.02), (0.12, 0.05, 0.3), "#4a0a0f")
	lamp("BrakeLight_L", (-0.72, -2.96, 0.57), (0.2, 0.03, 0.08), "#4a0a0f")
	lamp("BrakeLight_R", (0.72, -2.96, 0.57), (0.2, 0.03, 0.08), "#4a0a0f")
	plate("Plate_Rear", (0, -2.96, 0.5), "rear")
	plate("Plate_Front", (0, 3.27, 0.50), "front")
	lightbar(0, 0.35, 1.88, 1.3, 0.34, 0.07, mats)
	els_cells([
		(10, (-0.5, 3.18, 0.80), (0.2, 0.02, 0.06)), (11, (0.5, 3.18, 0.80), (0.2, 0.02, 0.06)),
		(12, (-0.5, 0.78, 1.74), (0.34, 0.1, 0.03)), (13, (0.5, 0.78, 1.74), (0.34, 0.1, 0.03)),
		(14, (-0.45, -1.02, 1.34), (0.3, 0.04, 0.06)), (15, (0.45, -1.02, 1.34), (0.3, 0.04, 0.06)),
		(16, (-1.02, 2.8, 0.95), (0.03, 0.14, 0.05)), (17, (1.02, 2.8, 0.95), (0.03, 0.14, 0.05)),
		(18, (-1.0, -2.6, 1.22), (0.03, 0.14, 0.05)), (19, (1.0, -2.6, 1.22), (0.03, 0.14, 0.05)),
	])
	markers(SP, hw_lo)
	export("sheriff_pickup")


build()
