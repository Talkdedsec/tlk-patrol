class_name RadarPanel
extends Control
## RADAR + ALPR panel. 338x298 at (1565, 555).
## The off state is measured; the on states (speed digits, plate hits) are guesses, see docs/api/hud.md.

const PANEL_POS := Vector2(1565.0, 555.0)
const PANEL_SIZE := Vector2(338.0, 298.0)

const BG := Color(0.095, 0.092, 0.11, 0.93)
const CELL_BG := Color("040508")
const GRAY := Color("8c8c92")
const DIM_GRAY := Color("6e6e74")
const LABEL_COLORS := {
	&"red": Color("a83a30"),
	&"amber": Color("b08a30"),
	&"green": Color("3a9a4a"),
}
const ON_COLORS := {
	&"red": Color("ff5a4a"),
	&"amber": Color("ffc040"),
	&"green": Color("5aff7a"),
}
const CELLS := [
	["FRONT", &"front", &"red"], ["F FAST", &"f_fast", &"amber"], ["PATROL", &"patrol", &"green"],
	["REAR", &"rear", &"red"], ["R FAST", &"r_fast", &"amber"], ["LOCK F", &"lock_f", &"amber"],
]

var radar_on := false
var antenna := "BOTH"
var direction := "CLOSING"
var fast_on := true
var target_mph := 75
var values: Dictionary = {}  # cell id -> String (empty = "--")
var alpr_on := false
var alpr_hits: Array = []  # lines such as "TAY-6023  registered owner has a warrant"


func _init() -> void:
	position = PANEL_POS
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Radar: on/off, header fields and per-cell values ({&"front": "62", ...}).
func set_radar(on: bool, cell_values: Dictionary = {}, ant: String = "BOTH", dir: String = "CLOSING", fast: bool = true,
		target: int = 75) -> void:
	radar_on = on
	values = cell_values
	antenna = ant
	direction = dir
	fast_on = fast
	target_mph = target
	queue_redraw()


func set_alpr(on: bool, hits: Array = []) -> void:
	alpr_on = on
	alpr_hits = hits
	queue_redraw()


func _badge(rect: Rect2, text: String, on: bool) -> void:
	var edge := Color("5fc07a") if on else GRAY
	draw_rect(rect, edge, false, 2.0)
	HudStyle.draw_text(self, text, Vector2(rect.position.x, rect.position.y + 14.0), 14, edge, 600, 100,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


func _draw() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = BG
	bg.set_corner_radius_all(9)
	bg.border_color = Color(1, 1, 1, 0.16)
	bg.set_border_width_all(1)
	bg.anti_aliasing = true
	bg.draw(get_canvas_item(), Rect2(Vector2.ZERO, PANEL_SIZE))

	HudStyle.draw_text(self, "RADAR", Vector2(11, 24), 16, Color.WHITE, 700, 95)
	_badge(Rect2(289, 8, 38, 20), "ON" if radar_on else "OFF", radar_on)

	var header := ["ANT " + antenna, "DIR " + direction, "FAST " + ("ON" if fast_on else "OFF"), "TGT %d MPH" % target_mph]
	var x := 11.0
	var header_color := GRAY if not radar_on else Color("b8b8be")
	for h in header:
		HudStyle.draw_text(self, h, Vector2(x, 43), 12, header_color, 600)
		x += HudStyle.text_width(h, 12, 600) + 10.0

	for i in CELLS.size():
		var c: Array = CELLS[i]
		var col := i % 3
		var row := i / 3
		var rect := Rect2(11.6 + col * 109.4, 50.0 + row * 56.0, 96.7, 49.3)
		draw_rect(rect, CELL_BG)
		HudStyle.draw_text(self, c[0], Vector2(rect.position.x + 6.0, rect.position.y + 13.5), 11, DIM_GRAY, 600)
		var value: String = values.get(c[1], "")
		if radar_on and not value.is_empty():
			HudStyle.draw_text(self, value, Vector2(rect.position.x, rect.end.y - 9.0), 22, ON_COLORS[c[2]], 700, 100,
				HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 7.0)
		else:
			var dash: Color = LABEL_COLORS[c[2]] * Color(1, 1, 1, 0.85)
			var dx := rect.end.x - 8.7
			draw_rect(Rect2(dx - 16.0, rect.end.y - 11.7, 7.5, 2.4), dash)
			draw_rect(Rect2(dx - 7.5, rect.end.y - 11.7, 7.5, 2.4), dash)

	draw_line(Vector2(11.6, 186), Vector2(327, 186), Color(1, 1, 1, 0.16), 1.0)
	HudStyle.draw_text(self, "ALPR", Vector2(11, 215), 16, Color.WHITE, 700, 95)
	_badge(Rect2(289, 195, 38, 20), "ON" if alpr_on else "OFF", alpr_on)
	if not alpr_on:
		HudStyle.draw_text(self, "off", Vector2(11, 237), 14, Color("7c7c82"), 700)
	else:
		var y := 237.0
		if alpr_hits.is_empty():
			HudStyle.draw_text(self, "scanning", Vector2(11, y), 14, Color("9a9aa0"), 600)
		for hit in alpr_hits:
			HudStyle.draw_text(self, "HIT  " + hit, Vector2(11, y), 13, Color("f0585e"), 600)
			y += 18.0
