extends CanvasLayer
## HUD built from a fixed layout (1920x1080 canvas).
## Text uses Open Sans (assets/fonts). API: docs/api/hud.md.

const WHITE := Color("FFFFFF")
const EMERGENCY_COLOR := Color("FDFFFF")
const FOOT_CHASE_COLOR := Color("D8555F")
const PURSUIT_COLOR := Color("E8505A")
const MISSION_COLOR := Color("EBDB9A")
const MISSION_OUTLINE := Color("3B2A12")
const WEAPON_COLOR := Color("BBF6C0")
const WEAPON_OUTLINE := Color("12301A")
const LOG_COLOR := Color("DCE9DA")
const MAP_HINT_COLOR := Color("9A9996")
const OUTLINE := Color(0.0, 0.0, 0.0, 0.85)

const RIGHT_EDGE := 1904.0
const LOG_X := 271.0
const LOG_WRAP_WIDTH := 470.0
const LOG_VISIBLE_LINES := 8
const LOG_LINE_HEIGHT := 26.0
const LOG_LIFETIME := 13.5  # a radio line stays this long (13.5 s)

# Text calibration: [font size, weight, label top y, width axis] per element, fitted by measurement
# (see docs/api/hud.md).
const T_CLOCK := [25, 400, 11.0, 98]
const T_WEATHER := [26, 400, 48.0, 96]
const T_SCORE := [18, 400, 84.0, 100]
const T_DUTY := [19, 400, 112.5, 98]
const T_WEAPON := [18, 400, 136.0, 97]
const T_EQUIP := [19, 400, 136.0, 96]  # flashlight / taser lines
const T_EMERGENCY := [24, 600, 61.0, 100]
const T_FOOT := [26, 600, 105.0, 100]
const T_MISSION := [21, 400, 160.0, 99]
const T_PURSUIT := [26, 550, 105.0, 100]
const T_STREET := [16, 400, 984.0, 99]
const T_HINT := [13, 400, 1004.0, 97]
const T_LOG := [17, 400, 97]
const T_HINTLINE := [26, 550, 140.0, 100]  # PIT hint line under PURSUIT
const T_OFFER := [21, 600, 160.0, 95]  # amber call offer line
const T_PROMPT := [24, 600, 960.0, 97]  # bottom-centre "E  Get in"
const T_COND := [15, 400, 1053.0, 97]  # bottom-right vehicle condition

## Lifetimes (seconds) of the toast messages; 0 = stays until replaced.
const NOTIFY_SECONDS := {
	"alpr_hit": 4.75, "alpr_hit_second": 4.5, "driver_fleeing": 1.0, "plate_reader_off": 1.75, "pit_requested": 2.25,
	"backup_on_the_way": 3.0, "rumbler_on": 1.5, "rush_hour": 4.5, "pit_spun_out": 7.0, "bailed_out": 0.0,
	"status_busy": 2.0, "pa_message": 3.0, "chase_called_off": 2.0, "stop_complete": 3.0, "cuff_offer": 0.0,
}

const OFFER_COLOR := Color("E4D794")
const ELS_NOTICE_SECONDS := 1.4  # "Stage 3: <pattern>" and "Traffic advisor: ..." toasts
const COND_COLOR := Color("B0B0B8")

var minimap: MinimapPanel
var radar: RadarPanel
var els_panel: ElsPanel
var els_panel_legacy: ElsPanelLegacy
var gauges: Gauges

var _clock: Label
var _weather: Label
var _score: Label
var _duty: Label
var _weapon: Label
var _emergency: Label
var _foot_chase: Label
var _pursuit: Label
var _mission: Label
var _toast: Label
var _street: Label
var _log_box: VBoxContainer
var _vehicle_nodes: Array[Control] = []
var _els_legacy := false
var _vehicle_active := false
var _map_hint: Label
var _overrides: Dictionary = {}
var _hintline: Label
var _offer: Label
var _prompt: Label
var _cond: Label
var _toast_timer: SceneTreeTimer
var _debug_chase := 62.0
var _debug_weapon_on := false


func _ready() -> void:
	layer = 10
	add_to_group("hud")
	_build_status_block()
	_build_top_center()
	_build_minimap()
	_build_log()
	_build_vehicle_panels()
	GameState.changed.connect(_refresh_status)
	Els.notice.connect(func(text: String) -> void: notify(text, ELS_NOTICE_SECONDS))
	Dispatch.line_added.connect(_add_log_line)
	for line in Dispatch.lines:
		_add_log_line(line)
	_refresh_status()
	set_mission("Talk to the people there and find out what happened.")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_emergency"):
		_emergency.visible = not _emergency.visible
	elif event.is_action_pressed("debug_dispatch"):
		Dispatch.say("Dispatch: all units, shots fired, officer needs assistance. 1-Adam-12, Eastgate. Respond Code 3.")
	elif event.is_action_pressed("debug_footchase"):
		if _foot_chase.visible and _debug_chase > 130.0:
			_debug_chase = 62.0
			clear_foot_chase()
		else:
			set_foot_chase(_debug_chase)
			_debug_chase += 17.0
	elif event.is_action_pressed("debug_weapon"):
		_debug_weapon_on = not _debug_weapon_on
		if _debug_weapon_on:
			set_weapon_line("Pistol", 17, 34)
		else:
			clear_weapon_line()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5: # debug: next siren
				var tones: Array = Els.SIRENS.keys()
				var i := tones.find(Els.siren_tone)
				Els.set_siren(&"" if i == tones.size() - 1 else tones[i + 1])
			KEY_F6: # debug: stage 0..3
				Els.set_stage((Els.stage + 1) % 4)
				Els.set_lights(Els.stage > 0)


# --- public API -------------------------------------------------------------

func set_emergency(active: bool) -> void:
	_emergency.visible = active


func set_foot_chase(feet: float) -> void:
	var shown := roundi(feet / 10.0) * 10 if feet >= 100.0 else roundi(feet)
	_foot_chase.text = "FOOT CHASE   %d ft" % shown
	_foot_chase.visible = true


func clear_foot_chase() -> void:
	_foot_chase.visible = false


## Vehicle pursuit line: "PURSUIT   <distance>   <status>". Distance in feet, switches to miles from 528 ft up
## (>= 100 ft is rounded to 10 ft steps). status e.g. "R request PIT", "PIT requested", "PIT authorized".
func set_pursuit(feet: float, status: String) -> void:
	_pursuit.text = "PURSUIT   %s   %s" % [_distance_text(feet), status]
	_pursuit.visible = true


## Distance text: feet below 528 ft (>= 100 ft in 10 ft steps), miles from 528 ft up.
func _distance_text(feet: float) -> String:
	if feet >= 528.0:
		return "%.1f mi" % (feet / 5280.0)
	if feet >= 100.0:
		return "%d ft" % (roundi(feet / 10.0) * 10)
	return "%d ft" % roundi(feet)


func clear_pursuit() -> void:
	_pursuit.visible = false


func set_mission(text: String) -> void:
	_mission.text = text
	_mission.visible = not text.is_empty()


## White temporary message on the toast slot (top centre, y~76). One slot: a new message replaces the previous one.
## seconds <= 0 keeps it until replaced or clear_notify() (e.g. "They bailed out of the car! Catch them.").
## center_x moves the line off the screen centre (the long "has them covered" offer sits at x~1050).
func notify(text: String, seconds: float = 3.0, center_x: float = 960.0) -> void:
	_toast.text = text
	_toast.position.x = center_x - _toast.size.x * 0.5
	_toast.visible = true
	_toast_timer = null
	if seconds <= 0.0:
		return
	_toast_timer = get_tree().create_timer(seconds)
	var timer := _toast_timer
	timer.timeout.connect(func() -> void:
		if timer == _toast_timer:
			_toast.visible = false)


func clear_notify() -> void:
	_toast_timer = null
	_toast.visible = false


func show_toast(text: String, seconds: float = 3.0) -> void:
	notify(text, seconds)


## Red line in the PURSUIT slot while a foot chase starts: "Chase nearby, 31 ft   C join   Z call off".
func set_chase_nearby(feet: float) -> void:
	_pursuit.text = "Chase nearby, %s   C join   Z call off" % _distance_text(feet)
	_pursuit.visible = true


## Second red line under PURSUIT ("PIT position: steer into the back corner"); "" hides it.
func set_pursuit_hint(text: String) -> void:
	_hintline.text = text
	_hintline.visible = not text.is_empty()


## Amber call-offer line, e.g. "Code 2: Trespassing.  Y respond  N pass  (25)"; "" hides it.
func set_offer(text: String) -> void:
	_offer.text = text
	_offer.visible = not text.is_empty()


## Bottom-centre interaction prompt, e.g. "E  Get in"; "" hides it.
func set_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = not text.is_empty()


## Small gray "Vehicle 92%   Engine 100%" text at the bottom right; -1 hides it.
func set_vehicle_condition(vehicle_pct: int, engine_pct: int) -> void:
	_cond.visible = vehicle_pct >= 0
	_cond.text = "Vehicle %d%%   Engine %d%%" % [vehicle_pct, engine_pct]


## Right-aligned green equipment lines in the weapon slot ("Flashlight on   4 off"; Taser: two lines).
func set_equipment_lines(lines: Array) -> void:
	_style_weapon(T_EQUIP)
	_weapon.text = "\n".join(PackedStringArray(lines))
	_weapon.visible = not lines.is_empty()


func _style_weapon(spec: Array) -> void:
	_weapon.add_theme_font_override("font", HudStyle.font(spec[1], spec[3]))
	_weapon.add_theme_font_size_override("font_size", spec[0])


## Appends a radio log line directly (without going through Dispatch). It expires after `lifetime` seconds
## (0 = never; state players use that).
func add_log_line(text: String, lifetime: float = LOG_LIFETIME) -> void:
	_add_log_line(text, lifetime)


func clear_log() -> void:
	for c in _log_box.get_children():
		_log_box.remove_child(c)
		c.queue_free()


func set_speed_unit(unit: String) -> void:
	gauges.set_unit(unit)


## Puts every element back to its empty state (state players call this before applying a new state).
func reset() -> void:
	set_emergency(false)
	clear_foot_chase()
	clear_pursuit()
	set_pursuit_hint("")
	set_offer("")
	set_prompt("")
	set_vehicle_condition(-1, -1)
	clear_notify()
	clear_weapon_line()
	set_mission("")
	set_score_visible(true)
	clear_log()
	clear_overrides()
	set_els_panel_style("overhaul")
	set_street_visible(true)
	set_vehicle_hud(false)
	minimap.clear_markers()
	set_speed(0.0)
	set_rpm(0.0)
	set_gear("N")
	set_speed_unit("MPH")
	radar.set_radar(false)
	radar.set_alpr(false)


func set_weapon_line(weapon_name: String, magazine: int, reserve: int) -> void:
	_style_weapon(T_WEAPON)
	_weapon.text = "%s  %d / %d   LMB fire   RMB aim   hold R reload" % [weapon_name, magazine, reserve]
	_weapon.visible = true


func clear_weapon_line() -> void:
	_weapon.visible = false


## Some states show a "Score N" line, some omit it (the status line then moves up).
func set_score_visible(visible_: bool) -> void:
	_score.visible = visible_
	_duty.position.y = T_DUTY[2] if visible_ else T_SCORE[2]


func set_street(street: String, mph: int) -> void:
	if _overrides.has("street"):
		return
	_street.text = "%s  %d mph" % [street, mph]


## The legacy layout has no street label (and no "Map [,]" hint) under the minimap.
func set_street_visible(visible_: bool) -> void:
	_street.visible = visible_
	_map_hint.visible = visible_


## Values that win over the game's own per-frame feed (a scenario replays fixed numbers): any of
## "speed", "rpm", "gear", "street" ([name, mph]). While a key is overridden, set_speed/set_rpm/set_gear/set_street
## calls for it are ignored; clear_overrides() hands control back.
func override_values(values: Dictionary) -> void:
	for key in values:
		_overrides.erase(key)
	for key in values:
		match key:
			"speed":
				gauges.set_speed(float(values[key]))
			"rpm":
				gauges.set_rpm(float(values[key]))
			"gear":
				gauges.set_gear(String(values[key]))
			"street":
				_street.text = "%s  %d mph" % [values[key][0], int(values[key][1])]
		_overrides[key] = true


func clear_overrides() -> void:
	_overrides.clear()


## Speed in the dial's unit (mph), RPM in thousands, gear text ("N", "1".."5").
func set_speed(mph: float) -> void:
	if not _overrides.has("speed"):
		gauges.set_speed(mph)


func set_rpm(thousands: float) -> void:
	if not _overrides.has("rpm"):
		gauges.set_rpm(thousands)


func set_gear(gear: String) -> void:
	if not _overrides.has("gear"):
		gauges.set_gear(gear)


func set_map_texture(tex: Texture2D, covers: Rect2 = Rect2(-512.0, -512.0, 1024.0, 1024.0)) -> void:
	minimap.set_map_texture(tex, covers)


func set_player_state(pos: Variant, yaw: float) -> void:
	minimap.set_player_state(pos, yaw)


## Shows or hides the vehicle-only panels (RADAR/ALPR, ELS, gauges). They are hidden while on foot.
func set_vehicle_hud(active: bool) -> void:
	_vehicle_active = active
	for n in _vehicle_nodes:
		n.visible = active
	els_panel.visible = active and not _els_legacy
	els_panel_legacy.visible = active and _els_legacy


## ELS panel look: "overhaul" (ELS SYSTEM, default) or "legacy" (the older LIGHTS & SIREN panel with FRONT/REAR/PODS/WIG
## rows).
func set_els_panel_style(style: String) -> void:
	_els_legacy = style == "legacy"
	set_vehicle_hud(_vehicle_active)


# --- construction -----------------------------------------------------------

func _make_label(spec: Array, color: Color, outline_color: Color = OUTLINE) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", HudStyle.font(spec[1], spec[3]))
	label.add_theme_font_size_override("font_size", spec[0])
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", outline_color)
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _place_right(label: Label, spec: Array) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.position = Vector2(RIGHT_EDGE - 700.0, spec[2])
	label.size = Vector2(700.0, 32.0)


func _place_center(label: Label, spec: Array) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(460.0, spec[2])
	label.size = Vector2(1000.0, 30.0)


func _build_status_block() -> void:
	_clock = _make_label(T_CLOCK, WHITE)
	_place_right(_clock, T_CLOCK)
	_weather = _make_label(T_WEATHER, WHITE)
	_place_right(_weather, T_WEATHER)
	_score = _make_label(T_SCORE, WHITE)
	_place_right(_score, T_SCORE)
	_duty = _make_label(T_DUTY, WHITE)
	_place_right(_duty, T_DUTY)
	_weapon = _make_label(T_WEAPON, WEAPON_COLOR, WEAPON_OUTLINE)
	_place_right(_weapon, T_WEAPON)
	_weapon.visible = false


func _build_top_center() -> void:
	_emergency = _make_label(T_EMERGENCY, EMERGENCY_COLOR)
	_emergency.text = "EMERGENCY: all units responding"
	_place_center(_emergency, T_EMERGENCY)
	_emergency.visible = false
	_toast = _make_label(T_EMERGENCY, WHITE)
	_place_center(_toast, T_EMERGENCY)
	_toast.visible = false
	_foot_chase = _make_label(T_FOOT, FOOT_CHASE_COLOR)
	_place_center(_foot_chase, T_FOOT)
	_foot_chase.visible = false
	_pursuit = _make_label(T_PURSUIT, PURSUIT_COLOR)
	_place_center(_pursuit, T_PURSUIT)
	_pursuit.visible = false
	_hintline = _make_label(T_HINTLINE, PURSUIT_COLOR)
	_place_center(_hintline, T_HINTLINE)
	_hintline.visible = false
	_offer = _make_label(T_OFFER, OFFER_COLOR)
	_place_center(_offer, T_OFFER)
	_offer.visible = false
	_mission = _make_label(T_MISSION, MISSION_COLOR, MISSION_OUTLINE)
	_place_center(_mission, T_MISSION)
	_prompt = _make_label(T_PROMPT, WHITE)
	_place_center(_prompt, T_PROMPT)
	_prompt.visible = false
	_cond = _make_label(T_COND, COND_COLOR)
	_place_right(_cond, T_COND)
	_cond.position.x += 3.0  # text ends at x~1907, past the status block edge
	_cond.visible = false


func _build_minimap() -> void:
	minimap = MinimapPanel.new()
	add_child(minimap)

	_street = _make_label(T_STREET, WHITE)
	_street.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_street.position = Vector2(17.0, T_STREET[2])
	_street.size = Vector2(229.0, 22.0)
	set_street("Hoover St", 25)

	_map_hint = _make_label(T_HINT, MAP_HINT_COLOR)
	_map_hint.text = "Map  [,]"
	_map_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_hint.position = Vector2(17.0, T_HINT[2])
	_map_hint.size = Vector2(229.0, 18.0)


func _build_log() -> void:
	_log_box = VBoxContainer.new()
	_log_box.anchor_left = 0.0
	_log_box.anchor_right = 0.0
	_log_box.anchor_top = 1.0
	_log_box.anchor_bottom = 1.0
	_log_box.offset_left = LOG_X
	_log_box.offset_right = LOG_X + LOG_WRAP_WIDTH
	_log_box.offset_top = -18.0
	_log_box.offset_bottom = -18.0
	_log_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Entries are separate labels; their gap makes the pitch of one-line entries equal the 26 px of wrapped lines.
	var log_font := HudStyle.font(T_LOG[1], T_LOG[2])
	_log_box.add_theme_constant_override("separation", roundi(LOG_LINE_HEIGHT - log_font.get_height(T_LOG[0])))
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log_box)


func _build_vehicle_panels() -> void:
	radar = RadarPanel.new()
	add_child(radar)
	els_panel = ElsPanel.new()
	add_child(els_panel)
	els_panel_legacy = ElsPanelLegacy.new()
	add_child(els_panel_legacy)
	gauges = Gauges.new()
	add_child(gauges)
	_vehicle_nodes = [radar, gauges]
	set_vehicle_hud(false)


func _add_log_line(text: String, lifetime: float = LOG_LIFETIME) -> void:
	var label := Label.new()
	var font := HudStyle.font(T_LOG[1], T_LOG[2])
	label.text = text
	label.custom_minimum_size.x = LOG_WRAP_WIDTH
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", T_LOG[0])
	label.add_theme_constant_override("line_spacing", roundi(LOG_LINE_HEIGHT - font.get_height(T_LOG[0])))
	label.add_theme_color_override("font_color", LOG_COLOR)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_box.add_child(label)
	if lifetime > 0.0:
		# bind the instance id, not the label: the label may already be freed when the timer fires
		get_tree().create_timer(lifetime).timeout.connect(_expire_log_line.bind(label.get_instance_id()))
	while _log_box.get_child_count() > LOG_VISIBLE_LINES:
		var oldest := _log_box.get_child(0)
		_log_box.remove_child(oldest)
		oldest.queue_free()


func _expire_log_line(label_id: int) -> void:
	var label := instance_from_id(label_id) as Node
	if label != null and is_instance_valid(label):
		label.queue_free()


func _refresh_status() -> void:
	_clock.text = GameState.clock_text()
	_weather.text = GameState.weather
	_score.text = "Score %d" % GameState.score
	_duty.text = GameState.duty_status
