extends Control
## MDT window: header, four tabs, footer. A pure view: the Mdt autoload feeds it.
## Layout in 1920x1080 canvas pixels.

const Ui := preload("res://scripts/mdt/ui_kit.gd")

signal tab_changed(tab: StringName)
signal run_plate_pressed
signal respond_pressed
signal pass_pressed

const WIN := Rect2(402, 12, 1116, 538)
const TAB_IDS: Array[StringName] = [&"dispatch", &"calls", &"plates", &"unit"]
const TAB_TITLES: Array[String] = ["DISPATCH", "CALLS", "PLATES", "UNIT"]
const TAB_X: Array[float] = [416.0, 568.0, 720.0, 872.0]
const TAB_Y := 66.0
const TAB_SIZE := Vector2(150.0, 38.0)
const FOOTER := "Tab or Esc to close  ·  the car can still be driven"

var tab: StringName = &"dispatch"

var _tab_buttons: Dictionary = {}
var _pages: Dictionary = {}
var _status_label: Label
var _clock_label: Label
var _call_title: Label
var _call_body: Label
var _traffic: RichTextLabel
var _plate_button: Button
var _plate_text: RichTextLabel
var _calls_cols: Array[RichTextLabel] = []
var _unit_cols: Array[RichTextLabel] = []
var _offer_label: Label
var _respond_button: Button
var _pass_button: Button
var _unit_left: RichTextLabel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_frame()
	_build_tabs()
	_build_dispatch_page()
	_build_calls_page()
	_build_plates_page()
	_build_unit_page()
	var footer := Ui.label(FOOTER, 13, Ui.MDT_FOOTER, 350)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.position = Vector2(WIN.position.x, 519.0)
	footer.size = Vector2(WIN.size.x, 24.0)
	add_child(footer)
	show_tab(tab)


func _build_frame() -> void:
	var frame := Panel.new()
	frame.position = WIN.position
	frame.size = WIN.size
	frame.add_theme_stylebox_override("panel", Ui.box(Ui.MDT_BEZEL, 12, Ui.MDT_BEZEL_LINE, 2))
	add_child(frame)
	var inner := Panel.new()
	inner.position = WIN.position + Vector2(10, 10)
	inner.size = WIN.size - Vector2(20, 20)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", Ui.box(Ui.MDT_CONTENT, 5))
	add_child(inner)
	var header := Panel.new()
	header.position = Vector2(WIN.position.x + 10, 24)
	header.size = Vector2(WIN.size.x - 20, 38)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var header_style := Ui.box(Ui.MDT_HEADER, 4)
	header_style.corner_radius_bottom_left = 0
	header_style.corner_radius_bottom_right = 0
	header.add_theme_stylebox_override("panel", header_style)
	add_child(header)
	var tab_row := Panel.new()
	tab_row.position = Vector2(WIN.position.x + 10, 62)
	tab_row.size = Vector2(WIN.size.x - 20, 46)
	tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab_row.add_theme_stylebox_override("panel", Ui.box(Ui.MDT_TAB_ROW))
	add_child(tab_row)
	var title := Ui.label("MOBILE DATA TERMINAL  ·  COMPUTER AIDED DISPATCH", 15, Ui.MDT_TITLE, 600)
	title.position = Vector2(420, 32)
	add_child(title)
	_status_label = Ui.label("1-ADAM-12   AVAILABLE", 15, Ui.MDT_GREEN, 600)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_label.position = Vector2(1029, 32)
	_status_label.size = Vector2(400, 24)
	add_child(_status_label)
	_clock_label = Ui.label("02:29", 15, Ui.MDT_TITLE, 400)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.position = Vector2(1099, 32)
	_clock_label.size = Vector2(400, 24)
	add_child(_clock_label)


func _build_tabs() -> void:
	for i in TAB_IDS.size():
		var button := Button.new()
		button.text = TAB_TITLES[i]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.position = Vector2(TAB_X[i], TAB_Y)
		button.size = TAB_SIZE
		button.add_theme_font_override("font", Ui.font(600))
		button.add_theme_font_size_override("font_size", 15)
		var normal := Ui.box(Ui.MDT_TAB, 3, Ui.MDT_TAB_LINE, 1)
		var hover := Ui.box(Ui.MDT_TAB_HOVER, 3, Ui.MDT_BUTTON_LINE, 1)
		var active := Ui.box(Ui.MDT_TAB_ACTIVE, 3)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", active)
		button.add_theme_stylebox_override("hover_pressed", active)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		for color_name in ["font_color", "font_hover_color"]:
			button.add_theme_color_override(color_name, Color("DAF0FF"))
		for color_name in ["font_pressed_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(color_name, Ui.MDT_TAB_ACTIVE_TEXT)
		button.pressed.connect(show_tab.bind(TAB_IDS[i]))
		add_child(button)
		_tab_buttons[TAB_IDS[i]] = button


func _page() -> Control:
	var page := Control.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	return page


func _build_dispatch_page() -> void:
	var page := _page()
	_pages[&"dispatch"] = page
	_call_title = Ui.label("NO CALL ASSIGNED", 16, Color("AAB7D2"), 700)
	_call_title.position = Vector2(426, 120)
	page.add_child(_call_title)
	_call_body = Ui.label("", 16, Ui.MDT_TEXT, 500)
	_call_body.position = Vector2(426, 168)
	_call_body.size = Vector2(466, 300)
	_call_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_call_body)
	var heading := Ui.label("RADIO TRAFFIC", 13, Ui.MDT_STAMP, 600)
	heading.position = Vector2(912, 120)
	page.add_child(heading)
	_traffic = Ui.rich(14, Ui.MDT_UNIT, 0, 450)
	_traffic.position = Vector2(912, 143)
	_traffic.size = Vector2(590, 372)
	_traffic.scroll_following = true
	Ui.style_scrollbar(_traffic.get_v_scroll_bar(), Ui.MDT_SCROLL, 6.0)
	page.add_child(_traffic)


## TODO(tahmin): the CALLS and UNIT tabs are our own design.
func _build_calls_page() -> void:
	var page := _page()
	_pages[&"calls"] = page
	_offer_label = Ui.label("", 16, Ui.AMBER, 600)
	_offer_label.position = Vector2(426, 124)
	page.add_child(_offer_label)
	_respond_button = _make_button("RESPOND  (Y)", Vector2(1210, 118), Vector2(140, 34))
	_respond_button.pressed.connect(func() -> void: respond_pressed.emit())
	page.add_child(_respond_button)
	_pass_button = _make_button("PASS  (N)", Vector2(1360, 118), Vector2(130, 34))
	_pass_button.pressed.connect(func() -> void: pass_pressed.emit())
	page.add_child(_pass_button)
	var heads := ["TIME", "CODE", "TYPE", "LOCATION", "STATUS"]
	var xs := [426.0, 502.0, 570.0, 880.0, 1150.0]
	var widths := [70.0, 60.0, 300.0, 260.0, 340.0]
	for i in heads.size():
		var head := Ui.label(heads[i], 13, Ui.MDT_STAMP, 600)
		head.position = Vector2(xs[i], 164)
		page.add_child(head)
		var col := Ui.rich(15, Ui.MDT_UNIT, 3, 450)
		col.position = Vector2(xs[i], 188)
		col.size = Vector2(widths[i], 325)
		col.scroll_active = false
		page.add_child(col)
		_calls_cols.append(col)


func _build_plates_page() -> void:
	var page := _page()
	_pages[&"plates"] = page
	_plate_button = _make_button("RUN THE PLATE OF THE VEHICLE AHEAD", Vector2(426, 123), Vector2(1068, 36), 600)
	_plate_button.pressed.connect(func() -> void: run_plate_pressed.emit())
	page.add_child(_plate_button)
	_plate_text = Ui.rich(17, Ui.MDT_TEXT, -1, 330)
	_plate_text.position = Vector2(426, 170)
	_plate_text.size = Vector2(1068, 340)
	_plate_text.scroll_following = true
	Ui.style_scrollbar(_plate_text.get_v_scroll_bar(), Ui.MDT_SCROLL, 6.0)
	page.add_child(_plate_text)


func _build_unit_page() -> void:
	var page := _page()
	_pages[&"unit"] = page
	_unit_left = Ui.rich(16, Ui.MDT_TEXT, 3)
	_unit_left.position = Vector2(426, 118)
	_unit_left.size = Vector2(470, 395)
	page.add_child(_unit_left)
	var units_head := Ui.label("UNITS ON DUTY", 13, Ui.MDT_STAMP, 600)
	units_head.position = Vector2(912, 118)
	page.add_child(units_head)
	for x in [912.0, 1050.0]:
		var col := Ui.rich(15, Ui.MDT_UNIT, 3, 450)
		col.position = Vector2(x, 142)
		col.size = Vector2(300, 370)
		col.scroll_active = false
		page.add_child(col)
		_unit_cols.append(col)


func _make_button(text: String, pos: Vector2, size_px: Vector2, weight: int = 600) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.position = pos
	button.size = size_px
	button.add_theme_font_override("font", Ui.font(weight))
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color("DBE9F5"))
	button.add_theme_color_override("font_hover_color", Color("FFFFFF"))
	button.add_theme_color_override("font_pressed_color", Color("FFFFFF"))
	button.add_theme_color_override("font_disabled_color", Color("6F7F95"))
	button.add_theme_stylebox_override("normal", Ui.box(Ui.MDT_BUTTON, 3, Ui.MDT_BUTTON_LINE, 1))
	button.add_theme_stylebox_override("hover", Ui.box(Color("27507F"), 3, Color("73B5DF"), 1))
	button.add_theme_stylebox_override("pressed", Ui.box(Color("173152"), 3, Ui.MDT_BUTTON_LINE, 1))
	button.add_theme_stylebox_override("disabled", Ui.box(Color("0E2038"), 3, Color("27456A"), 1))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


# --- API used by the Mdt autoload ------------------------------------------------------------------

func show_tab(id: StringName) -> void:
	tab = id
	for key: StringName in _pages:
		(_pages[key] as Control).visible = key == id
	for key: StringName in _tab_buttons:
		(_tab_buttons[key] as Button).set_pressed_no_signal(key == id)
	tab_changed.emit(id)


func set_header(unit: String, status_text: String, clock: String) -> void:
	_status_label.text = "%s   %s" % [unit.to_upper(), status_text.to_upper()]
	_clock_label.text = clock


func set_call(call: Dictionary) -> void:
	if call.is_empty():
		_call_title.text = "NO CALL ASSIGNED"
		_call_body.text = "Patrol your area. New calls show here and come in over the radio."
		return
	_call_title.text = ("Code %d: %s" % [call["code"], call["title"]]).to_upper()
	var lines := PackedStringArray([String(call.get("text", "")), "", "Location: %s" % call.get("location", "")])
	if String(call.get("plate", "")) != "" and call.get("type", &"") == &"stolen_vehicle":
		lines.append("Plate: %s" % call["plate"])
	lines.append("Status: %s" % String(call.get("status", &"")).replace("_", " "))
	_call_body.text = "\n".join(lines)


## entries: Array of {stamp, kind (dispatch|unit|me), text}
func set_traffic(entries: Array) -> void:
	_traffic.clear()
	for entry in entries:
		_append_traffic_line(entry)


func add_traffic(entry: Dictionary) -> void:
	_append_traffic_line(entry)


func _append_traffic_line(entry: Dictionary) -> void:
	var color: Color = Ui.MDT_UNIT
	match entry["kind"]:
		&"dispatch":
			color = Ui.MDT_DISPATCH
		&"me":
			color = Ui.MDT_ME
	var stamp := String(entry["stamp"])
	if _traffic.get_parsed_text() != "":
		_traffic.newline()
	_traffic.append_text("%s  %s" % [Ui.tint(stamp, Ui.MDT_STAMP), Ui.tint(_escape(String(entry["text"])), color)])


## bbcode text of the plate log (the autoload builds it).
func set_plate_log(bbcode: String) -> void:
	_plate_text.clear()
	_plate_text.append_text(bbcode)


func set_plate_busy(busy: bool) -> void:
	_plate_button.disabled = busy


func set_offer(text: String, active: bool) -> void:
	_offer_label.text = text
	_respond_button.visible = active
	_pass_button.visible = active


## rows: Array of Arrays with the five column texts (BBCode) TIME, CODE, TYPE, LOCATION, STATUS.
func set_calls_table(rows: Array) -> void:
	for col in _calls_cols:
		col.clear()
	for r in rows.size():
		for c in _calls_cols.size():
			if r > 0:
				_calls_cols[c].newline()
			_calls_cols[c].append_text(String(rows[r][c]))


## left: BBCode of the unit card; units: Array of [call sign, state] BBCode pairs for the right-hand list.
func set_unit_texts(left_bbcode: String, units: Array) -> void:
	_unit_left.clear()
	_unit_left.append_text(left_bbcode)
	for col in _unit_cols:
		col.clear()
	for r in units.size():
		for c in 2:
			if r > 0:
				_unit_cols[c].newline()
			_unit_cols[c].append_text(String(units[r][c]))


func scroll_traffic_to_end() -> void:
	_traffic.scroll_to_line(maxi(_traffic.get_line_count() - 1, 0))


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")
