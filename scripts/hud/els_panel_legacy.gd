class_name ElsPanelLegacy
extends Control
## The older "LIGHTS & SIREN" panel. Same data source as ElsPanel (Els autoload): rows FRONT, REAR, PODS, WIG come from
## Els.row_colors(t). 378x262 at (1173, 753). Select it with hud.set_els_panel_style("legacy").

const PANEL_POS := Vector2(1173.0, 753.0)
const PANEL_SIZE := Vector2(378.0, 262.0)

const BG := Color(0.133, 0.122, 0.145, 0.93)
const BORDER := Color("3a3840")
const GRAY := Color("9a9aa0")
const DIM_TEXT := Color("7c7c82")
const GREEN := Color("5bfd71")
const ORANGE := Color("dfa044")
const CHIP_ORANGE := Color("f5a025")
const CELL_X0 := 56.0
const CELL_STEP := 31.0
const CELL_W := 30.0
const ROW_Y := [35.0, 55.0, 79.0, 98.0]
const ROW_H := [16.0, 16.0, 17.0, 11.0]
const POD_LABELS := "CGVQRRQVGC"

const OFF_RED := Color("33151a")
const OFF_BLUE := Color("142038")
const OFF_GRAY := Color("343338")
const OFF_WIG := Color("0d0b0f")

const STAGE_BOXES := [Rect2(10.5, 124.5, 30, 21), Rect2(44.5, 124.5, 30, 21), Rect2(78.5, 124.5, 30, 21)]
# id, label, rect (local), kind: toggle | hold
const CHIPS := [
	[&"auto_siren", "AUTO", Rect2(66, 205.5, 42, 15), &"toggle"],
	[&"rumbler", "RUMBLER", Rect2(113, 205.5, 63, 15), &"toggle"],
	[&"man", "MANUAL", Rect2(181, 205.5, 59, 15), &"hold"],
	[&"blip", "BLIP", Rect2(245, 205.5, 35, 15), &"hold"],
	[&"haz", "HAZARD", Rect2(170.5, 234, 53.5, 16), &"toggle"],
	[&"road_clsd", "CLOSED", Rect2(231, 234, 52, 16), &"toggle"],
	[&"cruise", "CRUISE", Rect2(289, 234, 49, 16), &"toggle"],
]

var _down: StringName = &""


func _init() -> void:
	position = PANEL_POS
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	Els.changed.connect(queue_redraw)


func _process(_delta: float) -> void:
	if visible and Els.lights_active():
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var p: Vector2 = event.position
	if event.pressed:
		for i in 3:
			if (STAGE_BOXES[i] as Rect2).has_point(p):
				Els.set_stage(i + 1)
				Els.set_lights(true)
				accept_event()
				return
		for c in CHIPS:
			if (c[2] as Rect2).has_point(p):
				if c[3] == &"hold":
					_down = c[0]
					Els.press(c[0])
				else:
					Els.toggle(c[0])
				accept_event()
				return
	elif _down != &"":
		Els.release(_down)
		_down = &""
		accept_event()


func _draw() -> void:
	var ci := get_canvas_item()
	var frame := StyleBoxFlat.new()
	frame.bg_color = BG
	frame.border_color = BORDER
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(8)
	frame.anti_aliasing = true
	frame.draw(ci, Rect2(Vector2.ZERO, PANEL_SIZE))

	HudStyle.draw_text(self, "LIGHTS & SIREN", Vector2(11, 23), 17, Color("f4f4f6"), 500, 96)
	var active := Els.lights_active()
	_draw_badge(active)

	var rows := Els.row_colors(Els.now())
	var labels := ["FRONT", "REAR", "PODS", "WIG"]
	for r in 4:
		HudStyle.draw_text(self, labels[r], Vector2(11, ROW_Y[r] + ROW_H[r] - 4.0), 11 if r < 3 else 10, GRAY, 400, 96)
		for i in 10:
			_draw_cell(r, i, rows[r][i])

	draw_line(Vector2(11, 117), Vector2(367, 117), BORDER, 1.0)
	for i in 3:
		var rect: Rect2 = STAGE_BOXES[i]
		var on := active and Els.stage == i + 1
		draw_rect(rect, GREEN if on else Color("17171d"))
		draw_rect(rect, GREEN if on else Color("4a4a52"), false, 1.0)
		HudStyle.draw_text(self, str(i + 1), Vector2(rect.position.x, rect.position.y + 15.0), 14, Color("102014") if on else GRAY,
			500, 100, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	var stage_text := "Stage %d" % Els.stage if active else "Off (stage %d)" % maxi(Els.stage, 1)
	HudStyle.draw_text(self, stage_text, Vector2(119, 139), 14, Color("f0f0f2") if active else GRAY, 400, 96)

	var lines := Els.status_lines()
	var pattern_line: String = lines[0].substr(lines[0].find("  ") + 2)  # "Auto: <name>" or the bare name
	HudStyle.draw_text(self, pattern_line, Vector2(11, 167), 15, Color("f4f4f6") if active else GRAY, 400, 97)

	HudStyle.draw_text(self, "SIREN", Vector2(11, 198), 11, GRAY, 400, 96)
	var siren := Els.siren_label()
	if not Els.siren_note.is_empty():
		siren += "  " + Els.siren_note
	HudStyle.draw_text(self, siren, Vector2(67, 197.5), 15, ORANGE if Els.siren_tone != &"" else Color("8c8a92"), 400, 98)
	HudStyle.draw_text(self, "TRAFFIC", Vector2(11, 246), 11, GRAY, 400, 96)
	var traffic := "--"
	if Els.traffic_dir != &"":
		traffic = String(Els.traffic_dir)
	HudStyle.draw_text(self, traffic, Vector2(67, 247), 15, Color("8c8a92"), 400, 96)

	for c in CHIPS:
		_draw_chip(c)


func _draw_badge(active: bool) -> void:
	var rect := Rect2(304, 9, 63, 19)
	if not active:
		draw_rect(rect, GRAY, false, 2.0)
		HudStyle.draw_text(self, "OFF", Vector2(rect.position.x, rect.position.y + 14.0), 12, GRAY, 600, 100,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		return
	var text := "STAGE %d" % Els.stage
	if Els.stage == 3:
		draw_rect(rect, GREEN)
		HudStyle.draw_text(self, text, Vector2(rect.position.x, rect.position.y + 14.0), 12, Color("0c2a12"), 700, 100,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	else:
		draw_rect(rect, GREEN, false, 2.0)
		HudStyle.draw_text(self, text, Vector2(rect.position.x, rect.position.y + 14.0), 12, GREEN, 700, 100,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


func _off_color(row: int, i: int) -> Color:
	if row == 3:
		return OFF_WIG
	if row == 2:
		return OFF_GRAY if (i == 2 or i == 7) else (OFF_RED if i < 5 else OFF_BLUE)
	return OFF_GRAY if (i == 4 or i == 5) else (OFF_RED if i < 4 else OFF_BLUE)


func _draw_cell(row: int, i: int, color: Color) -> void:
	var rect := Rect2(CELL_X0 + CELL_STEP * i, ROW_Y[row], CELL_W, ROW_H[row])
	var lit := color.r + color.g + color.b > 0.05
	draw_rect(rect, color if lit else _off_color(row, i))
	if lit and (color.g > 0.8 and color.b > 0.7):  # white and cream cells get a light border
		draw_rect(rect, Color("c8c8cc"), false, 1.0)
	if row == 2 and not lit:
		HudStyle.draw_text(self, POD_LABELS[i], Vector2(rect.position.x, rect.position.y + 12.0), 10, Color("8a8a90"), 400, 100,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


func _draw_chip(c: Array) -> void:
	var rect: Rect2 = c[2]
	var on: bool = Els.held.get(c[0], false) if c[3] == &"hold" else Els.is_on(c[0])
	if on:
		draw_rect(rect, CHIP_ORANGE)
	else:
		draw_rect(rect, Color("55555a"), false, 1.0)
	HudStyle.draw_text(self, c[1], Vector2(rect.position.x, rect.position.y + 11.5), 10, Color("101010") if on else DIM_TEXT, 500, 96,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
