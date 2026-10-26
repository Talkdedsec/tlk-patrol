extends CanvasLayer
## Screen-centre crosshair: 4 bars + centre diamond, spread dynamics, red on target and the 4-line hit marker.
## Numbers for a 1920x1080 canvas. Drawn by the child Control "View".
## Weapons drives it; it only keeps state (works before it enters the tree).

const COLOR_NORMAL := Color("FFFFFF")
const COLOR_TARGET := Color("FF5A5F")        # red/pink while the aim ray is on a hittable target
const COLOR_OUTLINE := Color(0.0, 0.0, 0.0, 0.8)
const BAR_LENGTH := 9.0                      # horizontal bars 9x2 px, vertical 2x9 px
const BAR_WIDTH := 2.0
const DOT_RADIUS := 3.5
const MARKER_GAP := 12.0                     # hit marker lines start about 12 px from the centre
const MARKER_LENGTH := 6.0
const MARKER_TIME := 0.2                     # about 0.2 s, fading
const RECOVER_TAU := 0.7                     # 50 px -> about 19 px after 1 s
const MAX_SPREAD := 70.0
const MOVE_SMOOTH := 8.0                     # movement factor smoothing (1/s)

var manual := false                          ## when true the owner calls tick(); used by deterministic tests
var active := false                          ## weapon drawn and aiming: bars visible
var on_target := false
var spread_px := 9.0                         ## current inner-edge distance of the bars

var _rest := 9.0
var _move_spread := 55.0
var _shot_spread := 50.0
var _movement := 0.0                         ## smoothed 0..1
var _movement_goal := 0.0
var _extra := 0.0                            ## decaying extra spread (shots, aim opening)
var _time := 0.0
var _hidden_until := -1.0
var _hit_start := -10.0
var _view: Control


func _ready() -> void:
	layer = 9                                # below the HUD (10), above the 3D world
	_view = get_node_or_null("View") as Control
	if _view == null:
		_view = Control.new()
		_view.name = "View"
		_view.set_anchors_preset(Control.PRESET_FULL_RECT)
		_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_view)
	_view.draw.connect(_draw_view)
	_view.queue_redraw()


func _process(delta: float) -> void:
	if not manual:
		tick(delta)


func tick(delta: float) -> void:
	_time += delta
	_movement = move_toward(_movement, _movement_goal, MOVE_SMOOTH * delta)
	_extra *= exp(-delta / RECOVER_TAU)
	spread_px = minf(lerpf(_rest, _move_spread, _movement) + _extra, MAX_SPREAD)
	if _view != null:
		_view.queue_redraw()


## Applies the per-weapon numbers (rest / move / shot spread and hide time come from the weapon def).
func configure(rest: float, move: float, shot: float) -> void:
	_rest = rest
	_move_spread = move
	_shot_spread = shot
	spread_px = lerpf(_rest, _move_spread, _movement) + _extra


func set_active(value: bool, enter_spread := -1.0) -> void:
	if value and not active and enter_spread > 0.0:
		_extra = maxf(enter_spread - lerpf(_rest, _move_spread, _movement), 0.0)
		spread_px = minf(lerpf(_rest, _move_spread, _movement) + _extra, MAX_SPREAD)
	active = value


func set_on_target(value: bool) -> void:
	on_target = value


## Movement factor 0..1 (1 = running or turning fast: spread opens to the move value).
func set_movement(factor: float) -> void:
	_movement_goal = clampf(factor, 0.0, 1.0)


## A shot opens the spread to the shot value and hides the bars for `hide_time` seconds.
func on_shot(hide_time: float) -> void:
	var base := lerpf(_rest, _move_spread, _movement)
	_extra = maxf(_extra, _shot_spread - base)
	_hidden_until = _time + hide_time
	spread_px = minf(base + _extra, MAX_SPREAD)


func show_hit_marker() -> void:
	_hit_start = _time


func bars_visible() -> bool:
	return active and _time >= _hidden_until


func marker_alpha() -> float:
	var age := _time - _hit_start
	if age < 0.0 or age >= MARKER_TIME:
		return 0.0
	return 1.0 - age / MARKER_TIME


func current_color() -> Color:
	return COLOR_TARGET if on_target else COLOR_NORMAL


func _draw_view() -> void:
	var center := _view.size * 0.5
	var marker := marker_alpha()
	var show_bars := bars_visible() and marker <= 0.0
	if show_bars or marker > 0.0:
		_draw_dot(center, current_color())
	if show_bars:
		var color := current_color()
		var s := spread_px
		_draw_bar(Rect2(center.x + s, center.y - BAR_WIDTH * 0.5, BAR_LENGTH, BAR_WIDTH), color)
		_draw_bar(Rect2(center.x - s - BAR_LENGTH, center.y - BAR_WIDTH * 0.5, BAR_LENGTH, BAR_WIDTH), color)
		_draw_bar(Rect2(center.x - BAR_WIDTH * 0.5, center.y - s - BAR_LENGTH, BAR_WIDTH, BAR_LENGTH), color)
		_draw_bar(Rect2(center.x - BAR_WIDTH * 0.5, center.y + s, BAR_WIDTH, BAR_LENGTH), color)
	if marker > 0.0:
		var white := Color(1.0, 1.0, 1.0, marker)
		var dark := Color(0.0, 0.0, 0.0, 0.8 * marker)
		for sign_x in [-1.0, 1.0]:
			for sign_y in [-1.0, 1.0]:
				var dir := Vector2(sign_x, sign_y).normalized()
				var a: Vector2 = center + dir * MARKER_GAP
				var b: Vector2 = center + dir * (MARKER_GAP + MARKER_LENGTH)
				_view.draw_line(a, b, dark, 4.0)
				_view.draw_line(a, b, white, 2.0)


func _draw_bar(rect: Rect2, color: Color) -> void:
	_view.draw_rect(rect.grow(1.0), COLOR_OUTLINE)
	_view.draw_rect(rect, color)


func _draw_dot(center: Vector2, color: Color) -> void:
	var r := DOT_RADIUS
	var outer := PackedVector2Array([center + Vector2(0, -r - 1), center + Vector2(r + 1, 0),
			center + Vector2(0, r + 1), center + Vector2(-r - 1, 0)])
	var inner := PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0),
			center + Vector2(0, r), center + Vector2(-r, 0)])
	_view.draw_colored_polygon(outer, COLOR_OUTLINE)
	_view.draw_colored_polygon(inner, color)
