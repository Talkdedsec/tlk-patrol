extends CanvasLayer
## Pursuit overlay on the 1920x1080 canvas: the white toast slot, the red PURSUIT line, the PIT hint line,
## the red "Chase nearby" line, the Taser lines (top right) and the bottom prompt ("E  Cuff").
## When the HUD offers show_toast / set_pursuit / set_foot_chase (scripts/hud/hud.gd) the toast, PURSUIT line and
## FOOT CHASE gauge are drawn by the HUD; everything else (and all lines when there is no HUD) is drawn here.
## Layout: toast y~76, PURSUIT y~120, hint y~158.

const Adapters := preload("res://scripts/pursuit/adapters.gd")

const WHITE := Color("FDFFFF")
const RED := Color("E8505A")
const FOOT_RED := Color("F55A59")
const TASER := Color("BBF6C0")
const TASER_OUTLINE := Color("12301A")
const OUTLINE := Color(0, 0, 0, 0.85)

var use_hud := true
var _toast: Label
var _pursuit: Label
var _chase: Label
var _hint: Label
var _foot: Label
var _prompt: Label
var _taser_a: Label
var _taser_b: Label
var _toast_left := -1.0
var _toast_text := ""
var _pursuit_hud := false
var _foot_hud := false
var _chase_hud := false
var _taser_hud := false
var _hint_hud := false
var _prompt_hud := false
var _chase_str := ""
var _prompt_str := ""
var _pursuit_str := ""
var _foot_str := ""
var _hint_str := ""
var _taser_str := ""


func _init() -> void:
	layer = 11
	_toast = _label(22, 400, WHITE, Vector2(260, 62), Vector2(1400, 34), HORIZONTAL_ALIGNMENT_CENTER)
	_pursuit = _label(26, 500, RED, Vector2(260, 105), Vector2(1400, 38), HORIZONTAL_ALIGNMENT_CENTER)
	_chase = _label(26, 500, RED, Vector2(260, 105), Vector2(1400, 38), HORIZONTAL_ALIGNMENT_CENTER)
	_hint = _label(24, 500, RED, Vector2(260, 143), Vector2(1400, 34), HORIZONTAL_ALIGNMENT_CENTER)
	_foot = _label(22, 400, FOOT_RED, Vector2(460, 108), Vector2(1000, 32), HORIZONTAL_ALIGNMENT_CENTER)
	_prompt = _label(20, 400, WHITE, Vector2(660, 958), Vector2(600, 30), HORIZONTAL_ALIGNMENT_CENTER)
	_taser_a = _label(18, 400, TASER, Vector2(1204, 136), Vector2(700, 28), HORIZONTAL_ALIGNMENT_RIGHT, TASER_OUTLINE)
	_taser_b = _label(18, 400, TASER, Vector2(1204, 162), Vector2(700, 28), HORIZONTAL_ALIGNMENT_RIGHT, TASER_OUTLINE)
	for l in [_toast, _pursuit, _chase, _hint, _foot, _prompt, _taser_a, _taser_b]:
		(l as Label).visible = false


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.visible = false
			_toast_text = ""


func _font(weight: int) -> Font:
	var path := "res://scripts/hud/hud_style.gd"
	if ResourceLoader.exists(path):
		var sc: GDScript = load(path)
		var f: Variant = sc.call("font", weight)
		if f is Font:
			return f
	return null


func _label(size: int, weight: int, color: Color, pos: Vector2, area: Vector2, align: int,
		outline: Color = OUTLINE) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", 2)
	var f := _font(weight)
	if f != null:
		l.add_theme_font_override("font", f)
	l.horizontal_alignment = align as HorizontalAlignment
	l.position = pos
	l.size = area
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


static func format_distance(feet: float) -> String:
	if feet >= 528.0:
		return "%.1f mi" % (feet / 5280.0)
	if feet >= 100.0:
		return "%d ft" % (roundi(feet / 10.0) * 10)
	return "%d ft" % roundi(feet)


func _hud() -> Node:
	return Adapters.hud() if use_hud else null


## The HUD when it offers `method`, else null (the overlay draws that element itself).
func _hud_with(method: String) -> Node:
	var h := _hud()
	return h if h != null and h.has_method(method) else null


# --- toast slot (single slot: a new text replaces the old one) ---------------------------------------------------------

## One path for every white message: HUD.notify (measured font, single slot). `key` names a measured lifetime of
## HUD.NOTIFY_SECONDS ("driver_fleeing", "pit_requested", "pit_spun_out", "bailed_out", "cuff_offer", ...); 0 there means the
## text stays until replaced. `center_x` moves the line off the screen centre (the long "has them covered" line sits at x~1050).
## seconds <= 0 (without a key) keeps the text until replaced or cleared.
func toast(text: String, seconds: float = 3.0, key: StringName = &"", center_x: float = 960.0) -> void:
	var hud := _hud()
	if key != &"":
		seconds = _measured_seconds(hud, key, seconds)
	_toast_text = text
	_toast_left = seconds if seconds > 0.0 else -1.0
	if hud != null:
		if hud.has_method("notify"):
			hud.call("notify", text, seconds, center_x)
		else:
			hud.call("show_toast", text, seconds if seconds > 0.0 else 3600.0)
		_toast.visible = false
		return
	_toast.text = text
	_toast.position.x = center_x - _toast.size.x * 0.5
	_toast.visible = true


func _measured_seconds(hud: Node, key: StringName, fallback: float) -> float:
	if hud != null and hud.get_script() != null:
		var consts: Dictionary = (hud.get_script() as Script).get_script_constant_map()
		if consts.has("NOTIFY_SECONDS") and (consts["NOTIFY_SECONDS"] as Dictionary).has(String(key)):
			return float((consts["NOTIFY_SECONDS"] as Dictionary)[String(key)])
	return fallback


func clear_toast() -> void:
	_toast_text = ""
	_toast_left = -1.0
	_toast.visible = false
	var hud := _hud()
	if hud != null:
		if hud.has_method("clear_notify"):
			hud.call("clear_notify")
		else:
			hud.call("show_toast", "", 0.05)


func toast_text() -> String:
	return _toast_text


# --- red PURSUIT line --------------------------------------------------------------------------------------------------

func set_pursuit(feet: float, status: String) -> void:
	_chase.visible = false
	_chase_hud = false
	_chase_str = ""
	_pursuit_str = "PURSUIT   %s   %s" % [format_distance(feet), status]
	var hud := _hud()
	if hud != null:
		hud.call("set_pursuit", feet, status)
		_pursuit.visible = false
		_pursuit_hud = true
		return
	_pursuit.text = "PURSUIT   %s   %s" % [format_distance(feet), status]
	_pursuit.visible = true


func clear_pursuit() -> void:
	_pursuit.visible = false
	_pursuit_str = ""
	if _pursuit_hud:
		var hud := _hud()
		if hud != null:
			hud.call("clear_pursuit")
		_pursuit_hud = false


func pursuit_text() -> String:
	return _pursuit_str


## "Chase nearby, 31 ft   C join   Z call off" (replaces the PURSUIT line while the suspect is on foot).
func set_chase_nearby(feet: float) -> void:
	clear_pursuit()
	_chase_str = "Chase nearby, %s   C join   Z call off" % format_distance(feet)
	var h := _hud_with("set_chase_nearby")
	if h != null:
		h.call("set_chase_nearby", feet)
		_chase.visible = false
		_chase_hud = true
		return
	_chase.text = _chase_str
	_chase.visible = true


func clear_chase_nearby() -> void:
	_chase_str = ""
	_chase.visible = false
	if _chase_hud:
		var h := _hud()
		if h != null:
			h.call("clear_pursuit")
		_chase_hud = false


func chase_text() -> String:
	return _chase_str


## "PIT position: steer into the back corner" under the PURSUIT line.
func set_hint(text: String) -> void:
	if text == _hint_str:
		return
	_hint_str = text
	var h := _hud_with("set_pursuit_hint")
	if h != null:
		h.call("set_pursuit_hint", text)
		_hint.visible = false
		_hint_hud = true
		return
	_hint.text = text
	_hint.visible = not text.is_empty()


# --- foot chase gauge -------------------------------------------------------------------------------------------------

func set_foot_chase(feet: float) -> void:
	_foot_str = "FOOT CHASE   %d ft" % (roundi(feet / 10.0) * 10 if feet >= 100.0 else roundi(feet))
	var hud := _hud()
	if hud != null:
		hud.call("set_foot_chase", feet)
		_foot.visible = false
		_foot_hud = true
		return
	var shown := roundi(feet / 10.0) * 10 if feet >= 100.0 else roundi(feet)
	_foot.text = "FOOT CHASE   %d ft" % shown
	_foot.visible = true


func clear_foot_chase() -> void:
	_foot.visible = false
	_foot_str = ""
	if _foot_hud:
		var hud := _hud()
		if hud != null:
			hud.call("clear_foot_chase")
		_foot_hud = false


func foot_text() -> String:
	return _foot_str


func hint_text() -> String:
	return _hint_str


# --- prompt and Taser lines ------------------------------------------------------------------------------------------

func set_prompt(text: String) -> void:
	if text == _prompt_str:
		return
	_prompt_str = text
	var h := _hud_with("set_prompt")
	if h != null:
		h.call("set_prompt", text)
		_prompt.visible = false
		_prompt_hud = true
		return
	_prompt.text = text
	_prompt.visible = not text.is_empty()


func prompt_text() -> String:
	return _prompt_str


func set_taser(line_a: String, line_b: String) -> void:
	var joined := line_a if line_b.is_empty() else line_a + " | " + line_b
	if joined == _taser_str:
		return
	_taser_str = joined
	var h := _hud_with("set_equipment_lines")
	if h != null:
		if not line_a.is_empty() or _taser_hud:
			var lines: Array = []
			if not line_a.is_empty():
				lines.append(line_a)
			if not line_b.is_empty():
				lines.append(line_b)
			h.call("set_equipment_lines", lines)
		_taser_hud = not line_a.is_empty()
		_taser_a.visible = false
		_taser_b.visible = false
		return
	_taser_a.text = line_a
	_taser_a.visible = not line_a.is_empty()
	_taser_b.text = line_b
	_taser_b.visible = not line_b.is_empty()


func taser_text() -> String:
	return _taser_str


func clear_all() -> void:
	clear_toast()
	clear_pursuit()
	clear_chase_nearby()
	clear_foot_chase()
	set_hint("")
	set_prompt("")
	set_taser("", "")
