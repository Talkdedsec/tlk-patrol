extends RefCounted
## Feeds the HUD every frame: minimap (north-up road crop from World.minimap_image, rotated by the HUD), the markers
## (yellow call destination pinned to the map edge when it is far away, orange target of an ALPR hit), street and limit
## label, and the dial values while driving. API of the HUD: docs/api/hud.md.

const MAP_EXTENT := 640.0      # metres covered by the cached crop (1 px per metre)
const MAP_PX := 640
const MAP_RECENTER := 100.0    # rebuild the crop when the player is this far from its centre
const STREET_INTERVAL := 0.2
const DIAL_SMOOTH := 14.0      # 1/s, the dial needles are not filtered by the HUD
const PIN_RADIUS := 92.0       # m: markers farther than this ride the edge of the minimap (it shows about 99 m each way)

var hud  # HUD node (scripts/hud/hud.gd), untyped on purpose
var destination := Vector3.ZERO      ## yellow call marker (world position); has_destination turns it on
var has_destination := false
var highlight_street := ""           ## street drawn in yellow on the minimap (the route to the call)
var target_vehicle: Node3D           ## orange diamond: the ALPR-marked / pursued vehicle

var _tex: ImageTexture
var _center := Vector2(INF, INF)
var _street_timer := 0.0
var _street := "Hoover St"
var _limit := 25
var _speed := 0.0
var _rpm := 0.0
var _drawn_highlight := ""
var _markers_empty := true


## Yellow marker and street highlight for the assigned call; clear_destination() removes both.
func set_destination(pos: Vector3, street := "") -> void:
	destination = pos
	has_destination = true
	highlight_street = street


func clear_destination() -> void:
	has_destination = false
	highlight_street = ""


## pos / yaw: the player's position and heading (yaw 0 = north, rotation about Y). car: the driven vehicle or null.
func update(delta: float, pos: Vector3, yaw: float, car: Vehicle, throttle: float) -> void:
	if hud == null:
		return
	if World.is_built:
		_update_map(pos)
		_street_timer -= delta
		if _street_timer <= 0.0:
			_street_timer = STREET_INTERVAL
			var info: Dictionary = World.street_at(pos)
			if not String(info.get("name", "")).is_empty():
				_street = String(info["name"])
				_limit = int(info.get("speed_limit_mph", 25))
				hud.set_street(_street, _limit)
	hud.set_player_state(pos, yaw)
	_update_markers(pos)
	if car != null:
		var k := 1.0 - exp(-DIAL_SMOOTH * delta)
		_speed = lerpf(_speed, car.speed_mph(), k)
		_rpm = lerpf(_rpm, car.rpm() / 1000.0, k)
		hud.set_speed(_speed)
		hud.set_rpm(_rpm)
		hud.set_gear(_gear_text(car, throttle))


static func _gear_text(car: Vehicle, throttle: float) -> String:
	if car.forward_speed_mph() < -1.0:
		return "R"
	if car.speed_mph() < 1.0 and throttle < 0.05:
		return "N"
	return str(car.gear())


func _update_map(pos: Vector3) -> void:
	var here := Vector2(pos.x, pos.z)
	if _tex != null and here.distance_to(_center) < MAP_RECENTER and _drawn_highlight == highlight_street:
		return
	_center = here
	_drawn_highlight = highlight_street
	var img: Image = World.minimap_image(pos, MAP_EXTENT, MAP_PX, highlight_street)
	if _tex == null:
		_tex = ImageTexture.create_from_image(img)
	else:
		_tex.update(img)
	hud.set_map_texture(_tex, Rect2(here.x - MAP_EXTENT * 0.5, here.y - MAP_EXTENT * 0.5, MAP_EXTENT, MAP_EXTENT))


func _update_markers(pos: Vector3) -> void:
	var minimap: Variant = hud.get("minimap")
	if not (minimap is Object):
		return
	var list: Array = []
	var here := Vector2(pos.x, pos.z)
	if has_destination:
		list.append({"pos": _pinned(here, Vector2(destination.x, destination.z)), "kind": &"call"})
	if target_vehicle != null and is_instance_valid(target_vehicle):
		var p := target_vehicle.global_position
		list.append({"pos": _pinned(here, Vector2(p.x, p.z)), "kind": &"target"})
	if list.is_empty() and _markers_empty:
		return
	_markers_empty = list.is_empty()
	(minimap as Object).call("set_markers", list)


## A far marker is moved onto the edge of the minimap along the line to the real position.
static func _pinned(from: Vector2, to: Vector2) -> Vector2:
	var d := to - from
	if d.length() <= PIN_RADIUS:
		return to
	return from + d.normalized() * PIN_RADIUS
