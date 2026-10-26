extends Node
## Ties the chain together: ALPR hit -> pursuit -> PIT -> bail -> foot chase -> cuffs -> Pursuit.process_requested ->
## TrafficStop.begin_booking, and keeps the duty status (Available / Busy), the score hints and the leftovers of
## the pursuit in order. The modules do the work themselves; this node adds what they leave open:
##   - Busy while a pursuit runs, Available again when it is over (calls and stops keep their own transitions)
##   - the booked suspect and the abandoned car are handed to the director for removal
##   - the minimap shows the pursued car; the "Chase nearby" notice of Calls does not stay on after the player joins

const BOOKED_STATUS_DELAY := 20.5   # TrafficStop says "my prisoner's booked, show me 10-8." 20 s after the ruling

signal chain_event(name: StringName)

var director: Node
var events: Array[StringName] = []     ## order of the chain events seen (tests)

var _status_token := 0


func _ready() -> void:
	Pursuit.started.connect(func(_t: Node3D) -> void: _note(&"pursuit_started"); _busy())
	Pursuit.pit_state_changed.connect(func(s: int) -> void: _note(StringName("pit_%d" % s)))
	Pursuit.pit_succeeded.connect(func(_t: Node3D) -> void: _note(&"pit_spun"))
	Pursuit.suspect_bailed.connect(func(_n: Node3D) -> void: _note(&"bailed"))
	Pursuit.suspect_downed.connect(func(_n: Node3D) -> void: _note(&"downed"))
	Pursuit.suspect_cuffed.connect(func(_n: Node3D) -> void: _note(&"cuffed"))
	Pursuit.process_requested.connect(func(_n: Node3D, _c: Array) -> void: _note(&"process_requested"))
	Pursuit.ended.connect(_on_pursuit_ended)
	TrafficStop.booking_started.connect(func(_n: Node) -> void: _note(&"booking_started"))
	TrafficStop.booking_finished.connect(_on_booking_finished)
	TrafficStop.stop_started.connect(func(_v: Node3D) -> void: _note(&"stop_started"))
	TrafficStop.stop_finished.connect(func(_r: Dictionary) -> void: _note(&"stop_finished"))


func _note(event: StringName) -> void:
	events.append(event)
	chain_event.emit(event)


func _busy() -> void:
	_status_token += 1
	if Calls.status != &"busy":
		Calls.set_status(&"busy", false)


## Back to Available when nothing keeps the officer busy any more (an assigned call or a stop does).
func _available_when_free(delay: float) -> void:
	_status_token += 1
	var token := _status_token
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if token != _status_token:
		return
	if Calls.status == &"busy" and Calls.current.is_empty() and not Pursuit.is_active() \
			and TrafficStop.state == TrafficStop.State.IDLE:
		Calls.set_status(&"available", false)


func _on_pursuit_ended(reason: StringName) -> void:
	_note(StringName("pursuit_ended_" + String(reason)))
	if reason == &"processed":
		return   # the booking menu is open: booking_finished closes the chain
	_retire_actors(reason == &"suspect_down")
	_available_when_free(1.5)


func _on_booking_finished(_result: Dictionary) -> void:
	_note(&"booking_finished")
	_retire_actors(true)
	_available_when_free(BOOKED_STATUS_DELAY)


## The suspect (cuffed, called off, shot) and the car he left behind are removed once the player is away from them.
## A lost car is back in the ambient traffic (Pursuit adopts it), so it stays.
func _retire_actors(with_car: bool) -> void:
	if director == null:
		return
	var suspect: Node = Pursuit.suspect
	if suspect != null and is_instance_valid(suspect):
		director.retire(suspect)
	var car: Node = Pursuit.target
	if with_car and car != null and is_instance_valid(car):
		director.retire(car)
