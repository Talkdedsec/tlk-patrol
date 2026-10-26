"""Patrol sedan (muscle proportions): black/white department livery and an all-black unmarked variant.
Run: blender -b --factory-startup --python blender/vehicles/patrol_sedan.py
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

SP = dict(
	height=1.45, axle_f=1.55, axle_r=-1.5, track_f=0.84, track_r=0.84, wr=0.37, ww=0.27,
	lower=[(-2.45, 0.30), (-2.52, 0.55), (-2.50, 1.00), (-1.50, 1.05), (0.2, 1.04), (1.30, 1.00), (2.15, 0.92),
		(2.50, 0.74), (2.53, 0.50), (2.42, 0.30), (2.0, 0.22), (-2.0, 0.22)],
	hw_lo=(0.93, 0.97),
	cabin=dict(base=1.0, pts=[(-1.45, 1.0), (-0.80, 1.43), (0.55, 1.45), (1.30, 1.0)], hw=(0.86, 0.74),
		pillars=[(-0.175, 0.12)]),
	interior=dict(floor=0.35, y_mid=-0.2, w=1.5, len=3.0, dash_y=1.0, rows=[0.25, -0.75], bench=True),
	door_mid_y=0.45,
)


def build(variant):
	reset()
	clear_mats()
	mats = std_mats()
	unmarked = variant == "unmarked"
	global SP
	if unmarked:  # lower, coupe-like roof line
		SP = dict(SP, height=1.40, cabin=dict(SP["cabin"], pts=[(-1.45, 1.0), (-0.80, 1.36), (0.55, 1.38), (1.30, 1.0)]))
	black = M("PaintBlack", "#0d0e11", 0.45, 0.3)
	P = Part()
	hw_lo, hw_c = body(P, SP, mats, black, roof_paint=black)
	arches(P, SP, hw_lo, mats)
	for sd in (-1, 1):
		door_well(P, mats, hw_lo, sd, 1.0, -0.15, 0.33, 1.0)
		door_well(P, mats, hw_lo, sd, -0.2, -1.2, 0.33, 1.0)
	P.box(0, -2.52, 0.45, 1.9, 0.1, 0.28, mats["black"])
	P.box(0, 2.52, 0.40, 1.9, 0.1, 0.22, mats["black"])
	P.box(0, 2.54, 0.62, 1.1, 0.05, 0.14, mats["well"])
	P.box(0, 2.54, 0.78, 1.7, 0.02, 0.04, mats["black"])
	P.box(0, -0.2, 0.19, 1.6, 4.4, 0.08, mats["undercar"])
	if not unmarked:
		P.box(0, 2.64, 0.38, 1.3, 0.08, 0.12, mats["black"])  # push bar
	P.finish("Body")
	interior(SP, mats)
	wheels(SP, mats)
	door_paint = black if unmarked else M("PaintWhite", "#e8eaec", 0.5)
	dgt = M("TextGrey", "#2a2c31", 0.7) if unmarked else M("TextBlack", "#101216", 0.7)
	for key, sd, yf, yb in (("FL", -1, 1.0, -0.15), ("FR", 1, 1.0, -0.15), ("RL", -1, -0.2, -1.2), ("RR", 1, -0.2, -1.2)):
		d = door(SP, mats, key, hw_lo, hw_c, black, yf, yb, 0.33, 1.0, panel_paint=door_paint)
		x = sd * (hw_lo(0.65) + 0.0365)
		face = "left" if sd < 0 else "right"
		ym = (yf + yb) / 2
		if unmarked:
			if key in ("FL", "FR"):
				text("Decal_Unit_" + key, "GANG UNIT", 0.1, face, (x, ym - 0.02, 0.55), dgt, parent=d, bold=True)
		elif key in ("FL", "FR"):
			text("Decal_Police_" + key, "POLICE", 0.19, face, (x, ym - 0.1, 0.5), dgt, parent=d, bold=True)
			text("Decal_City_" + key, "DAVIDSON CITY", 0.065, face, (x, ym - 0.1, 0.76), dgt, parent=d)
			text("Decal_Dept_" + key, "Police Department", 0.06, face, (x, ym - 0.1, 0.33), dgt, parent=d)
			decal_quad("Decal_Badge_" + key, face, (x, ym + 0.35, 0.66), 0.001 + 0.14, 0.16, mats["gold"], parent=d)
	if unmarked:
		text("Decal_Trunk", "GANG UNIT", 0.09, "top", (0, -1.95, 1.062), dgt)
	else:
		text("Decal_Trunk", "POLICE", 0.16, "top", (0, -1.95, 1.062), M("TextWhite", "#e8eaec", 0.7))
	# lamps
	lamp("Headlight_L", (-0.72, 2.52, 0.72), (0.4, 0.06, 0.1), "#cfd3d9")
	lamp("Headlight_R", (0.72, 2.52, 0.72), (0.4, 0.06, 0.1), "#cfd3d9")
	if unmarked:  # the full-width LED bar is the 10 ELS cells; small corner lamps carry the tail light
		lamp("Taillight_L", (-0.92, -2.53, 0.93), (0.1, 0.03, 0.07), "#4a0a0f")
		lamp("Taillight_R", (0.92, -2.53, 0.93), (0.1, 0.03, 0.07), "#4a0a0f")
	else:
		lamp("Taillight_L", (-0.45, -2.53, 0.93), (0.82, 0.03, 0.07), "#4a0a0f")
		lamp("Taillight_R", (0.45, -2.53, 0.93), (0.82, 0.03, 0.07), "#4a0a0f")
	lamp("BrakeLight_L", (-0.78, -2.54, 0.66), (0.24, 0.03, 0.08), "#4a0a0f")
	lamp("BrakeLight_R", (0.78, -2.54, 0.66), (0.24, 0.03, 0.08), "#4a0a0f")
	plate("Plate_Rear", (0, -2.545, 0.5), "rear")
	plate("Plate_Front", (0, 2.62 if not unmarked else 2.57, 0.42), "front")
	# ELS cells: roof bar (0-9) on the marked car, hidden cells (10-19) on both
	if not unmarked:
		lightbar(0, 0.1, 1.45, 1.0, 0.3, 0.06, mats)
	if unmarked:
		# 10-19: rear LED bar, left to right (cell n takes colours[n % 10]); 20/25 grille, 21/26 windshield top
		bar = [(10 + i, (-0.8 + 0.16 * (i + 0.5), -2.552, 0.93), (0.15, 0.02, 0.07)) for i in range(10)]
		els_cells(bar, "#3a0d12", "#3a0d12")
		els_cells([
			(20, (-0.42, 2.555, 0.60), (0.18, 0.02, 0.06)), (25, (0.42, 2.555, 0.60), (0.18, 0.02, 0.06)),
			(21, (-0.45, 1.22, 1.34), (0.3, 0.1, 0.03)), (26, (0.45, 1.22, 1.34), (0.3, 0.1, 0.03)),
		])
	else:
		els_cells([
			(10, (-0.42, 2.555, 0.60), (0.18, 0.02, 0.06)), (11, (0.42, 2.555, 0.60), (0.18, 0.02, 0.06)),
			(12, (-0.45, 1.22, 1.375), (0.3, 0.1, 0.03)), (13, (0.45, 1.22, 1.375), (0.3, 0.1, 0.03)),
			(14, (-0.45, -1.35, 1.03), (0.3, 0.1, 0.03)), (15, (0.45, -1.35, 1.03), (0.3, 0.1, 0.03)),
			(16, (-0.96, 2.3, 0.80), (0.03, 0.12, 0.05)), (17, (0.96, 2.3, 0.80), (0.03, 0.12, 0.05)),
			(18, (-0.96, -2.3, 0.80), (0.03, 0.12, 0.05)), (19, (0.96, -2.3, 0.80), (0.03, 0.12, 0.05)),
		])
	markers(SP, hw_lo)
	export("patrol_sedan_unmarked" if unmarked else "patrol_sedan")


if __name__ == "__main__":
	build("unmarked" if "--unmarked" in sys.argv else "marked")
