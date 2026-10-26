"""Boxy full-size SUV: `ranger_suv` (civilian, recolourable) and `patrol_suv` (black/white department SUV, number 12).
Run: blender -b --factory-startup --python blender/vehicles/suv.py
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *

SP = dict(
	height=1.87, axle_f=1.58, axle_r=-1.4, track_f=0.84, track_r=0.84, wr=0.38, ww=0.27,
	lower=[(-2.35, 0.35), (-2.42, 0.60), (-2.40, 1.08), (1.15, 1.08), (2.0, 1.0), (2.5, 0.9), (2.55, 0.65),
		(2.47, 0.38), (2.0, 0.28), (-2.0, 0.28)],
	hw_lo=(0.93, 0.97),
	cabin=dict(base=1.08, pts=[(-2.37, 1.42), (-2.14, 1.80), (-1.8, 1.86), (0.55, 1.87), (1.15, 1.08)], hw=(0.9, 0.84),
		pillars=[(-0.075, 0.13), (-1.15, 0.14)]),
	interior=dict(floor=0.4, y_mid=-0.4, w=1.6, len=3.2, dash_y=0.95, rows=[0.2, -0.75], bench=True),
	door_mid_y=0.4,
)


def build(kind):
	reset()
	clear_mats()
	mats = std_mats()
	patrol = kind in ("patrol", "sheriff")
	sheriff = kind == "sheriff"
	beige = M("DoorBeige", "#cfc6a8", 0.5)
	if sheriff:
		paint = M("PaintBlack", "#0d0e13", 0.45, 0.3)
		roof = paint
		band = beige
	elif patrol:
		paint = M("PaintBlack", "#0d0e11", 0.45, 0.3)
		roof = M("PaintWhite", "#e8eaec", 0.5)
		band = M("DoorWhite", "#e8eaec", 0.5)
	else:
		paint = M("Paint", "#a9b8a8", 0.55)
		roof = M("Roof", "#17181c", 0.6)
		band = M("Band", "#a9b8a8", 0.55)
	P = Part()
	hw_lo, hw_c = body(P, SP, mats, paint, roof_paint=roof)
	arches(P, SP, hw_lo, mats)
	for sd in (-1, 1):
		door_well(P, mats, hw_lo, sd, 0.95, -0.05, 0.36, 1.06)
		door_well(P, mats, hw_lo, sd, -0.1, -1.1, 0.36, 1.06)
	P.box(0, -2.44, 0.45, 1.9, 0.1, 0.3, mats["black"])
	P.box(0, 2.55, 0.42, 1.9, 0.1, 0.26, mats["black"])
	P.box(0, 2.54, 0.72, 1.2, 0.05, 0.22, mats["well"])
	P.box(0, 0.0, 0.2, 1.7, 4.6, 0.08, mats["undercar"])
	if not patrol:
		# roof rack and side cladding
		t = 0.022
		for sd in (-1, 1):
			P.cyl(sd * 0.72, -0.9, 1.93, t, 2.6, "y", mats["black"], segs=6)
		for y in (-1.9, -0.9, 0.1):
			P.cyl(0, y, 1.95, t, 1.5, "x", mats["black"], segs=6)
		side_band(P, hw_lo, 2.2, -2.35, 0.28, 0.40, mats["black"], out=0.01)
	else:
		P.box(0, 2.66, 0.40, 1.3, 0.08, 0.14, mats["black"])
	if sheriff:
		side_band(P, hw_lo, -1.1, -2.4, 0.40, 0.80, beige)
		side_band(P, hw_lo, 2.45, 1.1, 0.40, 0.80, beige)
	P.finish("Body")
	interior(SP, mats)
	wheels(SP, mats)
	tc = M("TextBlack", "#101216", 0.7)
	for key, sd, yf, yb in (("FL", -1, 0.95, -0.05), ("FR", 1, 0.95, -0.05), ("RL", -1, -0.1, -1.1), ("RR", 1, -0.1, -1.1)):
		d = door(SP, mats, key, hw_lo, hw_c, paint, yf, yb, 0.36, 1.06, panel_paint=paint if sheriff else band, band=(0.80, band) if (sheriff or not patrol) else None)
		if patrol and not sheriff and key in ("FL", "FR"):
			x = sd * (hw_lo(0.65) + 0.0365)
			face = "left" if sd < 0 else "right"
			text("Decal_Police_" + key, "POLICE", 0.17, face, (x, (yf + yb) / 2 - 0.12, 0.55), tc, parent=d, bold=True)
			text("Decal_City_" + key, "DAVIDSON CITY", 0.06, face, (x, (yf + yb) / 2 - 0.12, 0.76), tc, parent=d)
			decal_quad("Decal_Badge_" + key, face, (x, (yf + yb) / 2 + 0.33, 0.66), 0.14, 0.16, mats["gold"], parent=d)
	if sheriff:
		wt = M("TextWhite", "#e8eaec", 0.7)
		text("Decal_Roof", "214", 0.5, "top", (0, -0.1, 1.875), wt, extrude=0.006, bold=True)
		text("Decal_Tailgate", "GENERAL", 0.09, "rear", (0, -2.435, 1.0), M("TextGrey", "#3b3e46", 0.6), extrude=0.005)
		decal_quad("Decal_Badge_Rear", "rear", (0, -2.438, 0.93), 0.16, 0.1, M("BadgeBlue", "#2b4a9a", 0.5))
		text("Decal_Sheriff", "SHERIFF", 0.17, "rear", (0, -2.435, 0.78), M("TextGold", "#a58f3a", 0.6), extrude=0.006, bold=True)
		text("Decal_Door_FL", "SHERIFF", 0.08, "left", (-(hw_lo(0.6) + 0.0365), 0.45, 0.58), M("TextGrey", "#3b3e46", 0.6), extrude=0.004)
	elif patrol:
		text("Decal_Roof", "12", 0.5, "top", (0, -0.1, 1.875), tc, extrude=0.006, bold=True)
		text("Decal_Hood", "12", 0.4, "top", (0, 1.75, 1.0), M("TextWhite", "#e8eaec", 0.7), extrude=0.006, bold=True) if False else None
	if not sheriff:
		text("Decal_Tailgate", "GENERAL", 0.17, "rear", (0, -2.452, 1.1), M("TextGrey", "#3b3e46", 0.6) if patrol else M("TextChrome", "#b9bec6", 0.35, 0.8), extrude=0.006, bold=True)
	lamp("Headlight_L", (-0.7, 2.55, 0.8), (0.36, 0.06, 0.17), "#cfd3d9")
	lamp("Headlight_R", (0.7, 2.55, 0.8), (0.36, 0.06, 0.17), "#cfd3d9")
	lamp("Taillight_L", (-0.9, -2.435, 0.98), (0.1, 0.05, 0.42), "#4a0a0f")
	lamp("Taillight_R", (0.9, -2.435, 0.98), (0.1, 0.05, 0.42), "#4a0a0f")
	lamp("BrakeLight_L", (-0.74, -2.47, 0.62), (0.22, 0.03, 0.07), "#4a0a0f")
	lamp("BrakeLight_R", (0.74, -2.47, 0.62), (0.22, 0.03, 0.07), "#4a0a0f")
	lamp("BrakeLight_High", (0, -2.3, 1.5), (0.5, 0.04, 0.04), "#4a0a0f")
	plate("Plate_Rear", (0, -2.5, 0.5), "rear")
	plate("Plate_Front", (0, 2.62, 0.42), "front")
	if patrol:
		lightbar(0, 0.2, 1.87, 1.1, 0.3, 0.07, mats)
		els_cells([
			(10, (-0.5, 2.56, 0.7), (0.2, 0.02, 0.06)), (11, (0.5, 2.56, 0.7), (0.2, 0.02, 0.06)),
			(12, (-0.5, 0.72, 1.78), (0.34, 0.1, 0.03)), (13, (0.5, 0.72, 1.78), (0.34, 0.1, 0.03)),
			(14, (-0.5, -2.25, 1.6), (0.34, 0.1, 0.03)), (15, (0.5, -2.25, 1.6), (0.34, 0.1, 0.03)),
			(16, (-0.98, 2.3, 0.95), (0.03, 0.14, 0.05)), (17, (0.98, 2.3, 0.95), (0.03, 0.14, 0.05)),
			(18, (-0.98, -2.3, 1.2), (0.03, 0.14, 0.05)), (19, (0.98, -2.3, 1.2), (0.03, 0.14, 0.05)),
		])
	markers(SP, hw_lo)
	export("patrol_suv_214" if sheriff else ("patrol_suv" if patrol else "ranger_suv"))


build("sheriff" if "--sheriff" in sys.argv else ("patrol" if "--patrol" in sys.argv else "civ"))
