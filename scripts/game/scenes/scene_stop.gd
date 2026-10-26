extends "res://scripts/game/scenes/call_scene.gd"
## "Traffic stop" call: a civilian car that was reported driving badly cruises ahead of the player on the call's road.
## With the lights on and the patrol car close behind, TrafficStop's own detection pulls it over (stop flow: radio, M commands,
## talk, ruling). With `flees` the car is marked like an ALPR hit instead: lights on within 65 ft and it drives off (Pursuit).

const Records := preload("res://scripts/traffic_stop/records.gd")

const VIOLATIONS: Array[StringName] = [&"speeding", &"lane", &"seatbelt", &"equipment", &"phone", &"reckless"]

var car: Vehicle
var flees := false
var violation: StringName = &"lane"
var plate := ""
var _driver: RefCounted
var _engaged := false           # TrafficStop or Pursuit took this car
var _stopped_once := false


func _init() -> void:
	kind = &"traffic_stop"


func setup(owner_director: Node, call_data: Dictionary, location: Dictionary) -> void:
	super(owner_director, call_data, location)
	flees = bool(call_data.get("flees", false))
	violation = StringName(call_data.get("violation", VIOLATIONS[director.rng.randi() % VIOLATIONS.size()]))


func spawn() -> void:
	var forward_along_edge: bool = director.away_along_edge(edge, edge_s)
	var xf := World.lane_transform(int(edge["id"]), edge_s, forward_along_edge, 0)
	xf.origin.y += 0.45
	car = Vehicles.spawn_traffic(xf, director.world_parent())
	track(car)
	plate = car.plate
	car.set_meta("call_id", call.get("id", -1))
	TrafficStop.report_violation(car, violation)
	var limit := float(edge.get("limit_mph", 25))
	var speed := limit * 0.44704 * 0.85
	car.linear_velocity = -xf.basis.z * speed
	_driver = Traffic.adopt(car, false)
	if _driver != null:
		# TODO(tahmin): a bad driver cruises a little over the limit (speeding), the others sit at it
		_driver.set("cruise_factor", float(call.get("cruise_factor", 1.35 if violation == &"speeding" else 1.05)))
	_prepare_record()
	link(Pursuit.started, _on_pursuit_started)
	link(Pursuit.ended, _on_pursuit_ended)
	link(TrafficStop.stop_started, _on_stop_started)
	link(TrafficStop.stop_finished, _on_stop_finished)
	link(TrafficStop.booking_finished, _on_booking_finished)
	if flees:
		Pursuit.mark_target(car, plate, true, true)   # same as an ALPR hit: lights within 65 ft and it runs


## The car's record: a clean owner (the call is about the driving), or a wanted one when it flees.
func _prepare_record() -> void:
	var rec := Records.for_plate(plate, car.display_name)
	if flees:
		rec["warrant"] = true
	rec = Records.finish(rec)
	car.set_meta("mdt_record", rec)


func update(_dt: float) -> void:
	if car == null or not is_instance_valid(car):
		finish(&"cancelled")


func _on_stop_started(vehicle: Node3D) -> void:
	if vehicle == car:
		_engaged = true


func _on_stop_finished(_result: Dictionary) -> void:
	if _engaged and not done and not Pursuit.is_active():
		finish(&"cleared")


func _on_pursuit_started(target: Node3D) -> void:
	if target != car:
		return
	_engaged = true
	car.set_handbrake(false)
	car.remove_meta("stop_hold")


func _on_pursuit_ended(reason: StringName) -> void:
	if not _engaged or done:
		return
	if reason == &"processed":
		return   # the booking menu follows; booking_finished ends the call
	finish(&"cleared" if reason == &"suspect_down" else &"cancelled")


func _on_booking_finished(_result: Dictionary) -> void:
	if _engaged and not done:
		finish(&"cleared")


func cleanup() -> void:
	# the car goes back to the ambient traffic: Traffic may remove it once it is far away
	if _driver != null:
		_driver.set("owned", true)
	super()
