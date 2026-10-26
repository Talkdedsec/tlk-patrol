extends "res://scripts/game/scenes/scene_stop.gd"
## "Stolen vehicle" call (Code 3): the BOLO car stands parked at the kerb. The plate reader gives the hit, with the lights on
## close behind it the car drives off and the pursuit starts (PIT, foot chase, cuffs, booking follow in Pursuit / TrafficStop).

const MODEL_TYPES := {
	"Arden Compact": &"civ_hatchback", "Calloway Sedan": &"civ_sedan", "Brightwater Pickup": &"civ_pickup",
	"Kestrel Hatchback": &"civ_hatchback", "Tolland Coupe": &"civ_sedan",
}
const COLOR_VALUES := {
	"black": Color("1d1f24"), "white": Color("d8d2c4"), "silver": Color("b3b9bf"), "red": Color("7d1f22"),
	"blue": Color("2c4a7a"), "green": Color("3d6b4a"), "tan": Color("c9b48a"), "gray": Color("8a8f96"),
}

var _hit_given := false


func _init() -> void:
	kind = &"stolen_vehicle"


func setup(owner_director: Node, call_data: Dictionary, location: Dictionary) -> void:
	super(owner_director, call_data, location)
	flees = true
	violation = &""


func spawn() -> void:
	var away: bool = director.away_along_edge(edge, edge_s)
	var dir := edge_dir() * (1.0 if away else -1.0)
	var side := 3.2 if away else -3.2                       # the right-hand kerb of the travel direction
	var pos := roadside(side) + Vector3(0.0, 0.45, 0.0)
	var type_id: StringName = MODEL_TYPES.get(String(call.get("model", "")), &"civ_sedan")
	var paint: Color = COLOR_VALUES.get(String(call.get("color", "")), Color("8a8f96"))
	plate = String(call.get("plate", ""))
	car = Vehicles.spawn(type_id, Transform3D(Basis.looking_at(dir, Vector3.UP), pos), director.world_parent(),
		{"plate": plate, "paint": paint})
	track(car)
	plate = car.plate
	car.set_handbrake(true)
	car.set_meta("flees", true)
	car.set_meta("alpr_force", true)
	car.set_meta("call_id", call.get("id", -1))
	_prepare_record()
	link(Pursuit.started, _on_pursuit_started)
	link(Pursuit.ended, _on_pursuit_ended)
	link(TrafficStop.booking_finished, _on_booking_finished)
	link(Pursuit.suspect_cuffed, _on_cuffed)


func _on_cuffed(_npc: Node3D) -> void:
	_engaged = true


func update(_dt: float) -> void:
	if car == null or not is_instance_valid(car):
		finish(&"cancelled")
		return
	# the plate reader is off or the reading was missed: the officer reads the plate by sight when close with the lights on
	if not _hit_given and not Pursuit.is_active() and not _engaged and director.player_driving() \
			and director.player_distance(car.global_position) < 30.0 and Els.lights_active():
		_hit_given = true
		car.set_meta("alpr_checked", true)
		Pursuit.alpr_hit(car, plate, "vehicle reported stolen", true, true)


func _prepare_record() -> void:
	var rec := Records.for_plate(plate, car.display_name)
	rec["stolen"] = true
	rec["evading"] = true
	car.set_meta("mdt_record", Records.finish(rec))
