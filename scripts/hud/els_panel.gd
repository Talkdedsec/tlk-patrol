class_name ElsPanel
extends Control
## "ELS SYSTEM" panel. Pure view of the Els autoload: it draws
## Els state and forwards mouse input to Els. Size 558x248 at (993, 766) on the 1920x1080 canvas.

const PANEL_POS := Vector2(993.0, 766.0)
const PANEL_SIZE := Vector2(558.0, 248.0)

const BG := Color("16131a")
const BORDER := Color("34323a")
const SCREW := Color("6c6a70")
const STATUS_BG := Color("030d0b")
const STATUS_BORDER := Color("1b2a2a")
const STATUS_TEXT := Color("b4f7df")
const STATUS_DIM := Color("58796d")
const CELL_OFF_GRAY := Color("353236")
const CELL_OFF_BLUE := Color("1a1a3a")
const CELL_ON_BLUE := Color("2a4bff")
const TRACK := Color("050304")
const THUMB := Color("8a8c96")

const BTN_W := 58.0
const BTN_H := 33.0
const GRID_X := 26.0
const GRID_Y := [68.0, 108.0, 148.0]
const GRID_STEP_X := 64.0

# Button groups: base look, active look.
const STYLES := {
	&"slate": {"bg": "20232e", "edge": "5d6070", "text": "dadfec", "a_bg": "3d4258", "a_edge": "c0c6dc", "a_text": "ffffff"},
	&"cyan": {"bg": "0e1f30", "edge": "1c7f90", "text": "6dbec9", "a_bg": "14687e", "a_edge": "5fe3f0", "a_text": "ffffff"},
	&"red": {"bg": "211012", "edge": "6e1b1e", "text": "cb2b2a", "a_bg": "c92116", "a_edge": "ff6a50", "a_text": "fffbf3"},
	&"purple": {"bg": "1b172d", "edge": "4a4aa0", "text": "8f76d7", "a_bg": "4a3aa8", "a_edge": "9a8aff", "a_text": "ffffff"},
	&"amber": {"bg": "1e1c18", "edge": "a8631a", "text": "e18f47", "a_bg": "6e420f", "a_edge": "ffb04a", "a_text": "ffe0b0"},
}

# [id, label, kind, style, col, row]. kind: siren | toggle | hold
const GRID_BUTTONS := [
	[&"take_down", "TAKE\nDOWN", &"toggle", &"slate", 0, 0],
	[&"left_alley", "LEFT\nALLEY", &"toggle", &"slate", 1, 0],
	[&"right_alley", "RIGHT\nALLEY", &"toggle", &"slate", 2, 0],
	[&"spot", "SPOT", &"toggle", &"slate", 3, 0],
	[&"cruise", "CRUISE", &"toggle", &"cyan", 4, 0],
	[&"dim", "DIM", &"toggle", &"cyan", 5, 0],
	[&"front_cut", "FRONT\nCUT", &"toggle", &"cyan", 6, 0],
	[&"rear_cut", "REAR\nCUT", &"toggle", &"cyan", 7, 0],
	[&"wail", "WAIL", &"siren", &"red", 0, 1],
	[&"yelp", "YELP", &"siren", &"red", 1, 1],
	[&"prty", "PRTY", &"siren", &"red", 2, 1],
	[&"hilo", "HI-LO", &"siren", &"red", 3, 1],
	[&"hyper_yelp", "HYPER\nYELP", &"siren", &"red", 4, 1],
	[&"yelp2", "YELP 2", &"siren", &"red", 5, 1],
	[&"pierce", "PIERCE", &"siren", &"red", 6, 1],
	[&"hyper_hilo", "HYPER\nHI-LO", &"siren", &"red", 7, 1],
	[&"mech_wail", "MECH\nWAIL", &"siren", &"red", 0, 2],
	[&"rotor", "ROTOR", &"siren", &"red", 1, 2],
	[&"man", "MAN", &"hold", &"red", 2, 2],
	[&"ah", "A/H", &"hold", &"red", 3, 2],
	[&"rumbler", "RUMBLER", &"toggle", &"red", 4, 2],
	[&"auto_siren", "AUTO\nSIREN", &"toggle", &"red", 5, 2],
	[&"blip", "BLIP", &"hold", &"red", 6, 2],
	[&"prog", "PROG", &"toggle", &"purple", 7, 2],
]

# Bottom row: [id, label, x, w] (local coordinates, y 214..243).
const PATTERN_BUTTONS := [[&"ptrn_prev", "PTRN\n<", 171.0, 39.0], [&"ptrn_next", "PTRN\n>", 215.0, 39.0]]
const TRAFFIC_BUTTONS := [
	[&"tr_left", "", 262.0, 41.0], [&"tr_split", "", 309.0, 41.0], [&"tr_right", "", 355.0, 41.0],
	[&"warn", "WARN", 401.0, 41.0], [&"haz", "HAZ", 451.0, 39.0], [&"road_clsd", "ROAD\nCLSD", 495.0, 39.0],
]
const BOTTOM_Y := 214.0
const BOTTOM_H := 29.0
const STAGE_X := [39.4, 73.0, 107.4, 141.4]
const STAGE_TRACK := Rect2(24.0, 228.0, 132.0, 12.5)

var _buttons: Array = []  # {id, rect, label, kind, style}
var _styles: Dictionary = {}
var _hover: StringName = &""
var _down: StringName = &""
var _dragging_stage := false


func _init() -> void:
	position = PANEL_POS
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	for b in GRID_BUTTONS:
		_buttons.append({
			"id": b[0], "label": b[1], "kind": b[2], "style": b[3],
			"rect": Rect2(GRID_X + GRID_STEP_X * b[4], GRID_Y[b[5]], BTN_W, BTN_H),
		})
	for b in PATTERN_BUTTONS:
		_buttons.append({"id": b[0], "label": b[1], "kind": &"tap", "style": &"purple", "rect": Rect2(b[2], BOTTOM_Y, b[3], BOTTOM_H)})
	for b in TRAFFIC_BUTTONS:
		_buttons.append({"id": b[0], "label": b[1], "kind": &"toggle", "style": &"amber", "rect": Rect2(b[2], BOTTOM_Y, b[3], BOTTOM_H)})


func _ready() -> void:
	Els.changed.connect(queue_redraw)


func _process(_delta: float) -> void:
	if Els.lights_active() or Els.traffic_dir != &"" or Els.is_on(&"warn") or Els.is_on(&"haz") or Els.is_on(&"road_clsd"):
		queue_redraw()


# --- input ------------------------------------------------------------------------

func _button_at(p: Vector2) -> Dictionary:
	for b in _buttons:
		if (b["rect"] as Rect2).has_point(p):
			return b
	return {}


func _stage_from_x(x: float) -> int:
	var best := 0
	for i in STAGE_X.size():
		if absf(x - STAGE_X[i]) < absf(x - STAGE_X[best]):
			best = i
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var p: Vector2 = event.position
		if _dragging_stage:
			_set_stage_from_pointer(p.x)
		var b := _button_at(p)
		var id: StringName = b.get("id", &"")
		if id != _hover:
			_hover = id
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position
		if event.pressed:
			var b := _button_at(p)
			if not b.is_empty():
				_press(b)
			elif _stage_hit(p):
				_dragging_stage = true
				_set_stage_from_pointer(p.x)
		else:
			_dragging_stage = false
			if _down != &"":
				Els.release(_down)
				_down = &""
				queue_redraw()
		accept_event()


func _stage_hit(p: Vector2) -> bool:
	return STAGE_TRACK.grow(5.0).has_point(p) or Rect2(24.0, 214.0, 132.0, 16.0).has_point(p)


func _set_stage_from_pointer(x: float) -> void:
	var s := _stage_from_x(x)
	Els.set_stage(s)
	Els.set_lights(s > 0)


func _press(b: Dictionary) -> void:
	var id: StringName = b["id"]
	match b["kind"]:
		&"siren":
			Els.toggle_siren(id)
		&"hold":
			_down = id
			Els.press(id)
		&"toggle":
			match id:
				&"tr_left":
					Els.set_traffic_dir(&"left")
				&"tr_split":
					Els.set_traffic_dir(&"split")
				&"tr_right":
					Els.set_traffic_dir(&"right")
				_:
					Els.toggle(id)
		&"tap":
			Els.cycle_pattern(-1 if id == &"ptrn_prev" else 1)
	queue_redraw()


# --- drawing ----------------------------------------------------------------------

func _is_active(b: Dictionary) -> bool:
	var id: StringName = b["id"]
	match b["kind"]:
		&"siren":
			return Els.siren_tone == id
		&"hold":
			return Els.held.get(id, false)
		_:
			match id:
				&"tr_left":
					return Els.traffic_dir == &"left"
				&"tr_split":
					return Els.traffic_dir == &"split"
				&"tr_right":
					return Els.traffic_dir == &"right"
				&"ptrn_prev", &"ptrn_next":
					return false
			return Els.is_on(id)


func _box(base: String, edge: String, radius: float = 5.0, glow: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var key := "%s|%s|%s|%s" % [base, edge, radius, glow]
	if _styles.has(key):
		return _styles[key]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(base)
	sb.border_color = Color(edge)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	if glow.a > 0.0:
		sb.shadow_color = glow
		sb.shadow_size = 7
	_styles[key] = sb
	return sb


func _draw() -> void:
	var ci := get_canvas_item()
	# Frame.
	var frame := _box("16131a", "34323a", 10.0)
	frame.set_border_width_all(2)
	frame.draw(ci, Rect2(Vector2.ZERO, PANEL_SIZE))
	for c in [Vector2(8, 8), Vector2(550, 8), Vector2(8, 241), Vector2(550, 241)]:
		draw_circle(c, 3.3, SCREW)
		draw_circle(c, 1.4, Color("2a2830"))

	# Title.
	draw_rect(Rect2(17, 10, 30, 17), Color("d12a22"))
	HudStyle.draw_text(self, "BLP", Vector2(17, 23.5), 11, Color.WHITE, 800, 100, HORIZONTAL_ALIGNMENT_CENTER, 30.0)
	HudStyle.draw_text(self, "ELS SYSTEM", Vector2(56, 25.5), 17, Color("f4f4f8"), 700, 100, HORIZONTAL_ALIGNMENT_LEFT, -1.0, true)

	_draw_lightbar()
	_draw_status()
	for b in _buttons:
		_draw_button(b)
	_draw_stage()
	_draw_group_header("PATTERN", 212.0, 172.0, 253.0, Color("8b75c8"))
	_draw_group_header("TRAFFIC", 398.7, 264.0, 532.5, Color("c28a30"))
	_draw_traffic_glyphs()


func _draw_lightbar() -> void:
	var mask := Els.cell_mask(Els.now())
	for i in 10:
		var x := 17.0 + 21.0 * i
		draw_rect(Rect2(x, 34, 18, 6), CELL_OFF_GRAY)
		draw_rect(Rect2(x, 43, 18, 6), CELL_OFF_GRAY)
		var on := (mask & (1 << i)) != 0
		draw_rect(Rect2(x, 52, 18, 6), CELL_ON_BLUE if on else CELL_OFF_BLUE)


func _draw_status() -> void:
	var box := _box("030d0b", "1b2a2a", 2.0)
	box.draw(get_canvas_item(), Rect2(238, 7, 302, 52))
	var lines := Els.status_lines()
	var off := Els.siren_tone == &""
	HudStyle.draw_text(self, lines[0], Vector2(247, 24.5), 13, STATUS_TEXT, 400, 96)
	HudStyle.draw_text(self, lines[1], Vector2(247, 40.8), 13, Color("5a7a70") if off else STATUS_TEXT, 400, 96)
	HudStyle.draw_text(self, lines[2], Vector2(247, 56.5), 11, STATUS_DIM, 400, 96)


func _draw_button(b: Dictionary) -> void:
	var st: Dictionary = STYLES[b["style"]]
	var r: Rect2 = b["rect"]
	var active := _is_active(b)
	var hover: bool = b["id"] == _hover
	var base: String = st["a_bg"] if active else st["bg"]
	var edge: String = st["a_edge"] if active else st["edge"]
	var glow := Color(st["a_edge"]).darkened(0.1)
	glow.a = 0.55
	var sb := _box(base, edge, 5.0, glow if active else Color(0, 0, 0, 0))
	sb.draw(get_canvas_item(), r)
	if hover and not active:
		draw_rect(r.grow(-1), Color(1, 1, 1, 0.07))
	var color := Color(st["a_text"] if active else st["text"])
	var label: String = b["label"]
	if label.is_empty():
		return
	var lines := label.split("\n")
	var size := 12
	var wdth := 88 if label.length() < 7 else 80
	var cap := size * 0.714
	if lines.size() == 1:
		HudStyle.draw_text(self, label, Vector2(r.position.x, r.get_center().y + cap * 0.5), size, color, 650, wdth,
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	else:
		for i in lines.size():
			var y := r.get_center().y + (-5.6 if i == 0 else 5.6) + cap * 0.5
			HudStyle.draw_text(self, lines[i], Vector2(r.position.x, y), size, color, 650, wdth, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _draw_stage() -> void:
	var labels := ["OFF", "1", "2", "3"]
	var dot_on := [Color("9a9aa0"), Color("e8d020"), Color("ff9a20"), Color("ff2a2a")]
	var dot_off := [Color("48484c"), Color("4a4418"), Color("4c3418"), Color("5a1a1a")]
	var text_col := [Color("6a6a70"), Color("a89828"), Color("d08020"), Color("ee2020")]
	for i in 4:
		var on := Els.stage == i
		draw_circle(Vector2(STAGE_X[i], 206.7), 3.6, dot_on[i] if on else dot_off[i])
		HudStyle.draw_text(self, labels[i], Vector2(STAGE_X[i] - 20.0, 222.8), 11, text_col[i], 700, 100,
			HORIZONTAL_ALIGNMENT_CENTER, 40.0)
	draw_rect(STAGE_TRACK.grow(1.0), Color("2c2c30"))
	draw_rect(STAGE_TRACK, TRACK)
	var tx: float = STAGE_X[Els.stage]
	var thumb := Rect2(tx - 9.0, 226.0, 18.0, 17.0)
	draw_rect(thumb, THUMB)
	draw_rect(Rect2(thumb.position + Vector2(1, 1), Vector2(16, 1)), Color("b8bac4"))
	for k in 3:
		draw_rect(Rect2(thumb.position.x + 5.0 + k * 3.5, thumb.position.y + 3.0, 1.2, 11.0), Color("3a3c46"))


func _draw_group_header(text: String, cx: float, x0: float, x1: float, color: Color) -> void:
	var w := HudStyle.text_width(text, 9, 700)
	HudStyle.draw_text(self, text, Vector2(cx - w * 0.5, 210.0), 9, color, 700)
	var dim := Color(color, 0.75)
	draw_line(Vector2(x0, 206.0), Vector2(cx - w * 0.5 - 6.0, 206.0), dim, 1.0)
	draw_line(Vector2(cx + w * 0.5 + 6.0, 206.0), Vector2(x1, 206.0), dim, 1.0)


func _chevron(cx: float, cy: float, dir: float, color: Color) -> void:
	var pts := PackedVector2Array([Vector2(cx - 3.5 * dir, cy - 6.5), Vector2(cx + 3.5 * dir, cy), Vector2(cx - 3.5 * dir, cy + 6.5)])
	draw_polyline(pts, color, 2.6, true)


func _draw_traffic_glyphs() -> void:
	for b in _buttons:
		var id: StringName = b["id"]
		if not (id == &"tr_left" or id == &"tr_split" or id == &"tr_right"):
			continue
		var r: Rect2 = b["rect"]
		var c := r.get_center()
		var col := Color(STYLES[&"amber"]["a_text"] if _is_active(b) else STYLES[&"amber"]["text"])
		match id:
			&"tr_left":
				_chevron(c.x - 4.0, c.y, -1.0, col)
				_chevron(c.x + 3.5, c.y, -1.0, col)
			&"tr_right":
				_chevron(c.x - 3.5, c.y, 1.0, col)
				_chevron(c.x + 4.0, c.y, 1.0, col)
			&"tr_split":
				_chevron(c.x - 5.5, c.y, -1.0, col)
				_chevron(c.x + 5.5, c.y, 1.0, col)
