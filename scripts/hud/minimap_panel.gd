class_name MinimapPanel
extends Control
## Heading-up minimap (229x229 at (17, 750)): the map texture rotates under a fixed player arrow, "N" rides the
## ring at the north direction. World axes: x east, z south (north = -Z).

const BOX := Vector2(229.0, 229.0)
const BG := Color("12131a")
const BORDER := Color("aeb4bc")
const MAJOR_ROAD := Color("a39b6b")
const MINOR_ROAD := Color("6e747c")
const N_RING_RADIUS := 107.0
const MARKER_UNIT := Color("2c6bff")
const MARKER_TARGET := Color("ff8a1a")
const MARKER_CALL := Color("ffd21a")

var map_texture: Texture2D
var world_rect := Rect2(-512.0, -512.0, 1024.0, 1024.0)  # world xz area covered by the texture, in metres
var pixels_per_meter := 1.15

var _pos := Vector2.ZERO  # player xz
var _yaw := 0.0
var _markers: Array = []  # {pos: Vector2, kind: StringName}


func _init() -> void:
	position = Vector2(17.0, 750.0)
	size = BOX
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Sets the map image and the world rectangle (x, z in metres) it covers.
func set_map_texture(tex: Texture2D, covers: Rect2 = Rect2(-512.0, -512.0, 1024.0, 1024.0)) -> void:
	map_texture = tex
	world_rect = covers
	queue_redraw()


## Player position (Vector3 world position or Vector2 xz) and yaw (radians, rotation about Y; 0 faces north).
func set_player_state(pos: Variant, yaw: float) -> void:
	_pos = Vector2(pos.x, pos.z) if pos is Vector3 else pos
	_yaw = yaw
	queue_redraw()


## Markers: kind &"unit" (blue ring, other officers), &"target" (orange diamond), &"call" (yellow ring).
func set_markers(markers: Array) -> void:
	_markers = markers
	queue_redraw()


func add_marker(pos: Variant, kind: StringName = &"unit") -> void:
	_markers.append({"pos": Vector2(pos.x, pos.z) if pos is Vector3 else pos, "kind": kind})
	queue_redraw()


func clear_markers() -> void:
	_markers.clear()
	queue_redraw()


## World xz -> position inside this control.
func world_to_screen(p: Vector2) -> Vector2:
	var d := p - _pos
	var s := sin(_yaw)
	var c := cos(_yaw)
	return BOX * 0.5 + Vector2(d.x * c - d.y * s, d.x * s + d.y * c) * pixels_per_meter


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, BOX), BG)
	if map_texture:
		var s := sin(_yaw)
		var c := cos(_yaw)
		var ppm := pixels_per_meter
		var origin := BOX * 0.5 - Vector2(_pos.x * c - _pos.y * s, _pos.x * s + _pos.y * c) * ppm
		draw_set_transform_matrix(Transform2D(Vector2(c, s) * ppm, Vector2(-s, c) * ppm, origin))
		draw_texture_rect(map_texture, world_rect, false)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	for m in _markers:
		_draw_marker(world_to_screen(m["pos"]), m["kind"])
	# Player arrow: white triangle, fixed pointing up.
	var ctr := BOX * 0.5
	draw_colored_polygon(PackedVector2Array([ctr + Vector2(0, -8), ctr + Vector2(6.5, 7), ctr + Vector2(0, 3.5), ctr + Vector2(-6.5, 7)]), Color.WHITE)
	# North label.
	var north := Vector2(sin(_yaw), -cos(_yaw)) * N_RING_RADIUS
	HudStyle.draw_text(self, "N", ctr + north + Vector2(-5.0, 5.0), 14, Color("d8dce2"), 600)
	draw_rect(Rect2(Vector2.ZERO, BOX), BORDER, false, 1.0)


func _draw_marker(p: Vector2, kind: StringName) -> void:
	if p.x < -10.0 or p.y < -10.0 or p.x > BOX.x + 10.0 or p.y > BOX.y + 10.0:
		return
	match kind:
		&"target":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0)]), MARKER_TARGET)
		&"call":
			draw_arc(p, 7.0, 0.0, TAU, 24, MARKER_CALL, 2.5, true)
		_:
			draw_circle(p, 7.0, MARKER_UNIT)
			draw_arc(p, 6.5, 0.0, TAU, 24, Color.WHITE, 1.8, true)


## Placeholder road network for tests: highway (khaki, thick) crossing a street grid (gray, thin).
static func make_test_map(size_px: int = 1024) -> ImageTexture:
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	img.fill(BG)
	for i in range(-4, 5):
		var o := size_px / 2 + i * 130
		_line(img, Vector2(o, 0), Vector2(o, size_px), MINOR_ROAD, 3)
		_line(img, Vector2(0, o), Vector2(size_px, o + 14), MINOR_ROAD, 3)
	_line(img, Vector2(0, size_px * 0.58), Vector2(size_px, size_px * 0.52), MAJOR_ROAD, 11)
	_line(img, Vector2(size_px * 0.4, 0), Vector2(size_px * 0.46, size_px), MAJOR_ROAD, 8)
	return ImageTexture.create_from_image(img)


static func _line(img: Image, a: Vector2, b: Vector2, color: Color, width: int) -> void:
	var steps := int(a.distance_to(b))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / maxf(steps, 1))
		img.fill_rect(Rect2i(int(p.x) - width / 2, int(p.y) - width / 2, width, width), color)
