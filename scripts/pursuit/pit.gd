extends RefCounted
## PIT authorisation state machine and contact geometry.
##   IDLE ("R request PIT") --request--> REQUESTED ("PIT requested") --4..7 s--> DENIED | AUTHORIZED
##   DENIED --20 s--> IDLE;  AUTHORIZED stays until the pursuit ends.

const Adapters := preload("res://scripts/pursuit/adapters.gd")

enum S { IDLE, REQUESTED, DENIED, AUTHORIZED }

## TODO(tahmin): approval at 19-21 mph and refusal at 65-87 mph; the exact threshold is a guess.
const SPEED_LIMIT_MPH := 40.0
const DELAY_MIN := 4.0   # measured decision delays: 4.0, 6.0, 7.0, 7.0 s
const DELAY_MAX := 7.0
const COOLDOWN := 20.0   # measured 19.5-20 s after the refusal
## TODO(tahmin): sustained front-corner contact needed to spin the car (0.6 s and 2 s contacts did not spin, 6 s did).
const SPIN_CONTACT_SECONDS := 4.0
const CONTACT_DECAY := 0.75     # lost contact drains the counter slower than it fills (bodies bounce apart)
const MIN_SPIN_SPEED_MPH := 10.0
const HINT_ON_FT := 20.5
const HINT_OFF_FT := 24.0
const CONTACT_TOLERANCE := 0.8   # real bodies touch at 12-20 ft centre distance; hull sizes are estimated

signal state_changed(new_state: int)

var state: int = S.IDLE
var timer := 0.0
var forced := -1          # -1 = decide by speed, 0 = deny, 1 = authorise (scripted use)
var forced_delay := -1.0
var contact_time := 0.0
var hint_visible := false
var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func reset() -> void:
	state = S.IDLE
	timer = 0.0
	forced = -1
	forced_delay = -1.0
	contact_time = 0.0
	hint_visible = false


func _change(new_state: int) -> void:
	if state != new_state:
		state = new_state
		state_changed.emit(new_state)


## Starts a request; false when one is already pending / refused / granted.
func request() -> bool:
	if state != S.IDLE:
		return false
	_change(S.REQUESTED)
	timer = forced_delay if forced_delay >= 0.0 else rng.randf_range(DELAY_MIN, DELAY_MAX)
	return true


## Scripted outcome of the next decision; delay < 0 keeps the random 4..7 s.
func set_decision(authorized: bool, delay: float = -1.0) -> void:
	forced = 1 if authorized else 0
	forced_delay = delay
	if state == S.REQUESTED and delay >= 0.0:
		timer = delay


## Natural rule: the decision uses the player's speed at decision time (not at request time).
static func decide(player_speed_mph: float) -> bool:
	return player_speed_mph <= SPEED_LIMIT_MPH


## Returns &"authorized", &"denied", &"ready" (cooldown over) or &"".
func tick(dt: float, player_speed_mph: float) -> StringName:
	if state == S.REQUESTED:
		timer -= dt
		if timer <= 0.0:
			var ok := (forced == 1) if forced >= 0 else decide(player_speed_mph)
			forced = -1
			forced_delay = -1.0
			if ok:
				_change(S.AUTHORIZED)
				return &"authorized"
			_change(S.DENIED)
			timer = COOLDOWN
			return &"denied"
	elif state == S.DENIED:
		timer -= dt
		if timer <= 0.0:
			_change(S.IDLE)
			return &"ready"
	return &""


func status_text() -> String:
	match state:
		S.REQUESTED:
			return "PIT requested"
		S.DENIED:
			return "PIT denied: speeds are too high"
		S.AUTHORIZED:
			return "PIT authorized"
	return "R request PIT"


## Shows the "steer into the back corner" line while authorised and close (hysteresis).
func update_hint(distance_ft: float) -> bool:
	if state != S.AUTHORIZED:
		hint_visible = false
	elif hint_visible:
		hint_visible = distance_ft <= HINT_OFF_FT
	else:
		hint_visible = distance_ft <= HINT_ON_FT
	return hint_visible


## Front corner of the player's car against the rear quarter of the suspect's car.
## Returns {touching, pit (one corner on the rear quarter, or both with the player clearly beside the axis, headings similar), side}.
## side: -1 = suspect's left rear struck, +1 = right rear struck (Vehicle.pit_spin convention).
static func contact(player: Node3D, suspect: Node3D) -> Dictionary:
	var res := {"touching": false, "pit": false, "side": 0.0}
	var ph := Adapters.half_size(player)
	var sh := Adapters.half_size(suspect)
	var pt := player.global_transform
	var sinv := suspect.global_transform.affine_inverse()
	var inside := 0
	var side := 0.0
	var centre: Vector3 = sinv * pt.origin
	for sx: float in [-1.0, 1.0]:
		var corner: Vector3 = pt * Vector3(sx * ph.x, 0.5, -ph.y)
		var l: Vector3 = sinv * corner
		if absf(l.x) <= sh.x + CONTACT_TOLERANCE and l.z >= sh.y * 0.1 and l.z <= sh.y + CONTACT_TOLERANCE:
			inside += 1
			side = signf(l.x) if absf(l.x) > 0.05 else sx
	if inside == 0:
		return res
	res.touching = true
	var pf := -pt.basis.z
	var sf := -suspect.global_transform.basis.z
	pf.y = 0.0
	sf.y = 0.0
	# one corner on the rear quarter, or both corners with the player clearly beside the suspect's axis (a straight rear-end is no PIT)
	if inside == 2:
		side = signf(centre.x)
	res.side = side
	res.pit = (inside == 1 or (inside == 2 and absf(centre.x) >= 0.4)) and pf.normalized().dot(sf.normalized()) > 0.7
	return res


## Accumulates PIT contact; true once the spin threshold is reached.
func update_contact(dt: float, pit_contact: bool, suspect_speed_mph: float) -> bool:
	if pit_contact and suspect_speed_mph >= MIN_SPIN_SPEED_MPH:
		contact_time += dt
	else:
		contact_time = maxf(contact_time - dt * CONTACT_DECAY, 0.0)
	return contact_time >= SPIN_CONTACT_SECONDS
