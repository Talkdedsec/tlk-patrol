class_name ScenePresets
extends RefCounted
## Camera / time / weather presets that cover typical scenes (day, night, highway, dawn).
## heading_deg: 0 = looking north (-Z), 90 = east. A preset has either `cam` (absolute) or `orbit` (around `car`).

const PRESETS := {
	"town_a_hoover_day": {
		"cam": {"pos": Vector3(5.5, 2.4, -132.0), "heading_deg": 12.0}, "fov": 70.0,
		"hours": 13.22, "weather": "Cloudy", "lamp": "white",
	},
	"town_a_hoover_house": {
		"cam": {"pos": Vector3(-3.0, 1.9, -100.0), "heading_deg": 78.0}, "fov": 70.0,
		"hours": 13.22, "weather": "Cloudy", "lamp": "white",
	},
	"town_b_davidson_day": {
		"car": {"pos": Vector3(-318.0, 0.0, 255.5), "heading_deg": 90.0},
		"orbit": {"azim_deg": 0.0, "dist": 10.0, "height": 4.2}, "fov": 70.0,
		"hours": 13.22, "weather": "Clear", "lamp": "white",
	},
	"town_b_davidson_pines": {
		"cam": {"pos": Vector3(-300.0, 1.9, 262.0), "heading_deg": 80.0}, "fov": 70.0,
		"hours": 13.22, "weather": "Clear", "lamp": "white",
	},
	"town_c_kiln_night": {
		"cam": {"pos": Vector3(597.0, 1.9, 296.0), "heading_deg": 182.0}, "fov": 70.0,
		"hours": 18.93, "weather": "Clear", "lamp": "white",
	},
	"night_western_night": {
		"car": {"pos": Vector3(-14.0, 0.0, 53.7), "heading_deg": 90.0},
		"orbit": {"azim_deg": 0.0, "dist": 9.0, "height": 3.6}, "fov": 70.0,
		"hours": 2.28, "weather": "Cloudy", "lamp": "sodium",
	},
	"night_hoover_night": {
		"car": {"pos": Vector3(3.5, 0.0, 82.0), "heading_deg": 0.0},
		"orbit": {"azim_deg": 0.0, "dist": 9.0, "height": 3.4}, "fov": 70.0,
		"hours": 2.7, "weather": "Cloudy", "lamp": "sodium",
	},
	"night_stop_night": {
		"car": {"pos": Vector3(3.5, 0.0, -60.0), "heading_deg": 0.0},
		"orbit": {"azim_deg": 0.0, "dist": 8.0, "height": 3.0}, "fov": 70.0,
		"hours": 3.22, "weather": "Cloudy", "lamp": "sodium",
	},
	"chase_street_night": {
		"night_boost": 4.5, "window_energy": 1.9,
		"car": {"pos": Vector3(160.0, 0.0, 53.7), "heading_deg": 90.0},
		"orbit": {"azim_deg": 0.0, "dist": 9.0, "height": 4.0}, "fov": 70.0,
		"hours": 2.25, "weather": "Clear", "lamp": "white",
	},
	"chase_highway_0515": {
		"night_boost": 4.5, "window_energy": 1.9,
		"car": {"pos": Vector3(-700.0, 0.0, -686.3), "heading_deg": 90.0},
		"orbit": {"azim_deg": 0.0, "dist": 9.0, "height": 4.0}, "fov": 70.0,
		"hours": 5.25, "weather": "Clear", "lamp": "white",
	},
	"chase_highway_0605": {
		"car": {"pos": Vector3(-700.0, 0.0, -686.3), "heading_deg": 90.0},
		"orbit": {"azim_deg": 0.0, "dist": 9.0, "height": 4.0}, "fov": 70.0,
		"hours": 6.08, "weather": "Clear", "lamp": "white",
	},
	"chase_highway_0645": {
		"car": {"pos": Vector3(-700.0, 0.0, -686.3), "heading_deg": 90.0},
		"orbit": {"azim_deg": 0.0, "dist": 9.0, "height": 4.0}, "fov": 70.0,
		"hours": 6.75, "weather": "Clear", "lamp": "white",
	},
	"chase_highway_0815": {
		"cam": {"pos": Vector3(-700.0, 2.2, -690.0), "heading_deg": 90.0}, "fov": 70.0,
		"hours": 8.25, "weather": "Clear", "lamp": "white",
	},
	"dusk_beltway_1727": {
		"car": {"pos": Vector3(-800.0, 0.0, 253.7), "heading_deg": 90.0},
		"orbit": {"azim_deg": 0.0, "dist": 9.0, "height": 3.6}, "fov": 70.0,
		"hours": 17.45, "weather": "Cloudy", "lamp": "white",
	},
	"dusk_beltway_1747": {
		"car": {"pos": Vector3(-800.0, 0.0, 253.7), "heading_deg": 90.0},
		"orbit": {"azim_deg": 0.0, "dist": 9.0, "height": 3.6}, "fov": 70.0,
		"hours": 17.78, "weather": "Cloudy", "lamp": "white",
	},
	"plaza_lot_front": {
		"car": {"pos": Vector3(215.0, 0.0, 405.0), "heading_deg": 270.0},
		"orbit": {"azim_deg": 150.0, "dist": 10.0, "height": 3.4}, "fov": 70.0,
		"hours": 18.75, "weather": "Clear", "lamp": "white", "els": true,
	},
	"plaza_lot_rear": {
		"car": {"pos": Vector3(215.0, 0.0, 405.0), "heading_deg": 270.0},
		"orbit": {"azim_deg": 0.0, "dist": 9.0, "height": 3.0}, "fov": 70.0,
		"hours": 18.45, "weather": "Clear", "lamp": "white", "els": true,
	},
}


static func names() -> PackedStringArray:
	return PackedStringArray(PRESETS.keys())


static func info(preset_name: String) -> Dictionary:
	return PRESETS.get(preset_name, {})


## Car placement of a preset (origin when the preset has no car).
static func car_transform(preset_name: String) -> Transform3D:
	var p: Dictionary = PRESETS.get(preset_name, {})
	if not p.has("car"):
		return Transform3D(Basis(), Vector3.ZERO)
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(p.car.heading_deg)), p.car.pos + Vector3(0, 0.05, 0))


static func camera_transform(preset_name: String) -> Transform3D:
	var p: Dictionary = PRESETS.get(preset_name, {})
	if p.is_empty():
		return Transform3D(Basis(), Vector3(0, 2, 0))
	if p.has("cam"):
		var c: Dictionary = p.cam
		return Transform3D(Basis.from_euler(Vector3(deg_to_rad(c.get("pitch_deg", 0.0)), -deg_to_rad(c.heading_deg), 0.0), EULER_ORDER_YXZ), c.pos)
	# Orbit: place the camera around the car and look at its roof.
	var o: Dictionary = p.orbit
	var yaw := -deg_to_rad(p.car.heading_deg) + deg_to_rad(o.azim_deg)
	var pos: Vector3 = p.car.pos + Basis(Vector3.UP, yaw) * Vector3(0, 0, o.dist) + Vector3(0, o.height, 0)
	var target: Vector3 = p.car.pos + Vector3(0, 1.2, 0)
	return Transform3D(Basis.looking_at((target - pos).normalized(), Vector3.UP), pos)
