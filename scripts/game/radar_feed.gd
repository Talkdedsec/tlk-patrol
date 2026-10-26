extends Node
## RADAR (speed gun) and ALPR (plate reader) of the patrol car: reads the civilian cars around the player, fills the HUD
## panel (hud.radar.set_radar / set_alpr) and hands plate hits to Pursuit. Panels are visible only while driving (the
## seat switches them). Keys (TODO(tahmin)): V radar on/off, G lock the front reading,
## P plate reader on/off.

const GameInput := preload("res://scripts/game/game_input.gd")

const RADAR_RANGE := 170.0      # m, TODO(tahmin): moving radar reach
const RADAR_CONE := 9.0         # degrees either side of the heading
const SPEEDING_OVER := 8        # mph over the limit that marks a car with the "speeding" violation
const ALPR_RANGE := 55.0        # m ahead (a hit shows at roughly 150 ft)
const ALPR_CONE := 22.0
const ALPR_COOLDOWN := 30.0     # s between two random hits
const ALPR_PERIOD := 0.35
const RADAR_PERIOD := 0.12
const FLEE_CHANCE := 0.7        # a car with a wanted-person hit runs when the lights come on
const FLEE_HITS: Array[String] = ["registered owner has a warrant", "vehicle reported stolen", "owner has prior arrests for evading"]

signal alpr_hit_found(vehicle: Node3D, plate: String, reason: String)

var patrol: Vehicle
var seat: Node
var hud
var alpr_enabled := true         ## scenarios and menus switch the scanning off
var alpr_on := true              ## the panel switch (P)
var radar_on := false            ## the panel switch (V)
var hit_lines: Array[String] = []
var front_reading := ""          ## text of the FRONT cell, for tests
var last_hit_plate := ""

var _rng := RandomNumberGenerator.new()
var _alpr_timer := 0.5
var _radar_timer := 0.0
var _cooldown := 8.0
var _locked := ""
var _last_panel := ""
var _alpr_pushed := false


func _ready() -> void:
	_rng.randomize()


func is_driving() -> bool:
	return seat != null and seat.has_method("is_driving") and bool(seat.call("is_driving"))


func _unhandled_input(event: InputEvent) -> void:
	if not is_driving() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action("radar_toggle"):
		radar_on = not radar_on
		_locked = ""
		_toast("Radar on" if radar_on else "Radar off")
		_radar_timer = 0.0
	elif event.is_action("alpr_toggle"):
		set_alpr_on(not alpr_on)
	elif event.is_action("radar_lock") and radar_on:
		_locked = "" if not _locked.is_empty() else front_reading
		_radar_timer = 0.0


func set_alpr_on(on: bool) -> void:
	if on == alpr_on and _alpr_pushed:
		return
	alpr_on = on
	_toast("Plate reader on" if on else "Plate reader off")
	_push_alpr()


func _toast(text: String) -> void:
	if hud != null:
		hud.show_toast(text, 1.75)


func _push_alpr() -> void:
	_alpr_pushed = true
	if hud != null and hud.get("radar") is RadarPanel:
		(hud.radar as RadarPanel).set_alpr(alpr_on, hit_lines.duplicate())


func _process(delta: float) -> void:
	if hud == null or patrol == null or not is_instance_valid(patrol):
		return
	if not _alpr_pushed:
		_push_alpr()
	_cooldown = maxf(_cooldown - delta, 0.0)
	_radar_timer -= delta
	if _radar_timer <= 0.0:
		_radar_timer = RADAR_PERIOD
		_update_radar()
	_alpr_timer -= delta
	if _alpr_timer <= 0.0:
		_alpr_timer = ALPR_PERIOD
		_scan_plates()
	_update_target_marker()


# --- RADAR --------------------------------------------------------------------------------------------------------

## Fills the six cells: nearest and fastest car ahead, own speed, nearest and fastest car behind, the locked reading.
func _update_radar() -> void:
	var radar: Variant = hud.get("radar")
	if not (radar is RadarPanel):
		return
	if not radar_on or not is_driving():
		if _last_panel != "off":
			_last_panel = "off"
			front_reading = ""
			(radar as RadarPanel).set_radar(false)
		return
	var to_local := patrol.global_transform.affine_inverse()
	var info: Dictionary = World.street_at(patrol.global_position)
	var limit := int(info.get("speed_limit_mph", 25))
	var front: Array = []
	var rear: Array = []
	for v: Vehicle in Vehicles.all:
		if v == patrol or v.is_police or not is_instance_valid(v):
			continue
		var local := to_local * v.global_position
		var ahead := -local.z
		if absf(ahead) < 3.0 or absf(ahead) > RADAR_RANGE:
			continue
		if absf(local.x) > maxf(3.2, absf(ahead) * tan(deg_to_rad(RADAR_CONE))):
			continue
		var mph := roundi(v.speed_mph())
		var entry := [absf(ahead), mph, v]
		(front if ahead > 0.0 else rear).append(entry)
		if ahead > 0.0 and mph >= limit + SPEEDING_OVER and not v.has_meta("violation"):
			TrafficStop.report_violation(v, &"speeding")   # the stop panel then says what was seen before the lights
	front.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	rear.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var values := {"patrol": str(roundi(patrol.speed_mph()))}
	front_reading = ""
	if not front.is_empty():
		front_reading = str(front[0][1])
		values["front"] = front_reading
		values["f_fast"] = str(_fastest(front))
	if not rear.is_empty():
		values["rear"] = str(rear[0][1])
		values["r_fast"] = str(_fastest(rear))
	if not _locked.is_empty():
		values["lock_f"] = _locked
	var target := int(ceil(float(limit + 10) / 5.0)) * 5
	var key := str(values) + str(target)
	if key != _last_panel:
		_last_panel = key
		(radar as RadarPanel).set_radar(true, values, "BOTH", "CLOSING", true, target)


static func _fastest(list: Array) -> int:
	var best := 0
	for e: Array in list:
		best = maxi(best, int(e[1]))
	return best


# --- ALPR ---------------------------------------------------------------------------------------------------------

func _scan_plates() -> void:
	if not alpr_on or not alpr_enabled or not is_driving():
		return
	if Pursuit.is_active() or TrafficStop.state != TrafficStop.State.IDLE:
		return
	var car := _car_in_view()
	if car == null:
		return
	car.set_meta("alpr_checked", true)
	var record: Dictionary = TrafficStop.record_for(car)
	var hits: Array = record.get("hits", [])
	if hits.is_empty():
		return
	var forced := bool(car.get_meta("alpr_force", false))
	if _cooldown > 0.0 and not forced:
		car.remove_meta("alpr_checked")   # read it again once the cooldown is over
		return
	_report_hit(car, String(hits[0]), record)


## Nearest civilian car ahead, inside the reader's cone and not read yet.
func _car_in_view() -> Vehicle:
	var forward := -patrol.global_transform.basis.z
	var best: Vehicle = null
	var best_distance := ALPR_RANGE
	for v: Vehicle in Vehicles.all:
		if v == patrol or v.is_police or not is_instance_valid(v) or v.has_meta("alpr_checked"):
			continue
		var to := v.global_position - patrol.global_position
		var distance := to.length()
		if distance < 4.0 or distance > best_distance:
			continue
		to.y = 0.0
		if rad_to_deg(forward.angle_to(to.normalized())) > ALPR_CONE:
			continue
		best = v
		best_distance = distance
	return best


func _report_hit(car: Vehicle, reason: String, record: Dictionary) -> void:
	_cooldown = ALPR_COOLDOWN
	var flees: bool
	if car.has_meta("flees"):
		flees = bool(car.get_meta("flees"))
	else:
		flees = FLEE_HITS.has(reason) and _rng.randf() < FLEE_CHANCE
	hit_lines.push_front("%s  %s" % [car.plate, reason])
	while hit_lines.size() > 2:
		hit_lines.pop_back()
	_push_alpr()
	last_hit_plate = car.plate
	Pursuit.alpr_hit(car, car.plate, reason, flees, bool(record.get("evading", false)))
	alpr_hit_found.emit(car, car.plate, reason)


## Debug key (F9): the car ahead gets a wanted-person hit. The pursuit starts once the lights are on and the car is close.
func force_hit() -> bool:
	var best: Vehicle = null
	var best_distance := 90.0
	var forward := -patrol.global_transform.basis.z
	for v: Vehicle in Vehicles.all:
		if v == patrol or v.is_police or not is_instance_valid(v):
			continue
		var to := v.global_position - patrol.global_position
		var distance := to.length()
		to.y = 0.0
		if distance < best_distance and distance > 3.0 and rad_to_deg(forward.angle_to(to.normalized())) < 30.0:
			best = v
			best_distance = distance
	if best == null:
		return false
	best.set_meta("alpr_checked", true)
	var record: Dictionary = TrafficStop.record_for(best)
	_report_hit(best, "registered owner has a warrant", record)
	return true


## Orange minimap diamond on the marked or pursued car.
func _update_target_marker() -> void:
	if seat == null or not seat.has_method("set_target_marker"):
		return
	var target: Node3D = null
	if Pursuit.state == Pursuit.State.PURSUIT or Pursuit.state == Pursuit.State.SUSPECT_DOWN:
		target = Pursuit.target
	else:
		var marked: Variant = Pursuit.get("_marked")
		if marked is Dictionary and (marked as Dictionary).has("vehicle"):
			target = (marked as Dictionary)["vehicle"]
	seat.call("set_target_marker", target)
