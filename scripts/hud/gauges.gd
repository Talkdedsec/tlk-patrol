class_name Gauges
extends Control
## Speedometer (0-140 mph) and tachometer (0-7 x1000 rpm, gear in the centre).
## Drawn with _draw on the 1920x1080 canvas: dial diameter 146 px, centres (1665, 941) and (1828, 941).

const SPEED_CENTER := Vector2(1665.0, 941.0)
const RPM_CENTER := Vector2(1828.0, 941.0)
const RADIUS := 73.0
const SWEEP_START := 135.0  # degrees, clockwise from +x: 0 sits lower-left
const SWEEP := 270.0
const SPEED_MAX := 140.0
const RPM_MAX := 7.0
const REDLINE_FROM := 6.0

const FACE := Color("1c191d")
const RING := Color("8e8a8c")
const TICK := Color("eeeeee")
const MINOR := Color("9c9a9c")
const NEEDLE := Color("ff4a1c")
const HUB := Color("2a282b")
const REDLINE := Color("cd251d")
const SUB_TEXT := Color("9a989c")

var speed := 0.0  # in the unit shown
var rpm := 0.0  # x1000
var gear := "N"
var unit := "MPH"


func _init() -> void:
	position = Vector2.ZERO
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_speed(value: float) -> void:
	speed = value
	queue_redraw()


func set_rpm(value_x1000: float) -> void:
	rpm = value_x1000
	queue_redraw()


func set_gear(value: String) -> void:
	gear = value
	queue_redraw()


func set_unit(value: String) -> void:
	unit = value
	queue_redraw()


static func _angle(frac: float) -> float:
	return deg_to_rad(SWEEP_START + SWEEP * clampf(frac, 0.0, 1.0))


func _draw() -> void:
	_dial(SPEED_CENTER, SPEED_MAX, 20.0, 10.0, 0.0, speed / SPEED_MAX)
	_dial(RPM_CENTER, RPM_MAX, 1.0, 0.5, REDLINE_FROM, rpm / RPM_MAX)
	HudStyle.draw_text(self, str(roundi(speed)), SPEED_CENTER + Vector2(-40.0, 45.5), 26, Color.WHITE, 700, 94,
		HORIZONTAL_ALIGNMENT_CENTER, 80.0, false, true)
	HudStyle.draw_text(self, unit, SPEED_CENTER + Vector2(-30, 61.5), 13, SUB_TEXT, 400, 100, HORIZONTAL_ALIGNMENT_CENTER, 60.0)
	HudStyle.draw_text(self, gear, RPM_CENTER + Vector2(-40, 45.5), 26, Color.WHITE, 700, 94, HORIZONTAL_ALIGNMENT_CENTER, 80.0)
	HudStyle.draw_text(self, "x1000 RPM", RPM_CENTER + Vector2(-40, 61.5), 13, SUB_TEXT, 400, 100, HORIZONTAL_ALIGNMENT_CENTER, 80.0)


func _dial(c: Vector2, max_value: float, major: float, minor: float, red_from: float, frac: float) -> void:
	draw_circle(c, RADIUS, FACE)
	draw_arc(c, RADIUS - 1.0, 0.0, TAU, 96, RING, 2.4, true)
	var steps := int(round(max_value / minor))
	for i in steps + 1:
		var v := i * minor
		var is_major := is_zero_approx(fposmod(v, major))
		var a := _angle(v / max_value)
		var dir := Vector2(cos(a), sin(a))
		if is_major:
			draw_line(c + dir * (RADIUS - 14.5), c + dir * (RADIUS - 2.5), TICK, 3.0, true)
			var label := str(int(round(v if max_value > 10.0 else v)))
			var center := c + dir * (RADIUS - 28.5)
			var sz := 14
			var w := HudStyle.text_width(label, sz, 500)
			HudStyle.draw_text(self, label, center + Vector2(-w * 0.5, sz * 0.36), sz, Color("dcdcdc"), 500)
		else:
			draw_line(c + dir * (RADIUS - 8.0), c + dir * (RADIUS - 2.5), MINOR, 1.4, true)
	if red_from > 0.0:
		draw_arc(c, RADIUS - 6.5, _angle(red_from / max_value), _angle(1.0), 24, REDLINE, 6.5, true)
	var na := _angle(frac)
	var nd := Vector2(cos(na), sin(na))
	draw_line(c - nd * 8.0, c + nd * (RADIUS * 0.84), NEEDLE, 2.4, true)
	draw_circle(c, 4.2, HUB)
