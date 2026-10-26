extends "res://scripts/characters/officer.gd"
## The player's Officer plus the vehicle contract the other modules look for (TrafficStop / Pursuit adapters call
## is_in_vehicle / enter_vehicle / exit_vehicle on the node in group "player"). The seat logic is vehicle_seat.gd.

var in_vehicle := false          ## true while seated and driving
var seat: Node                   ## VehicleSeat, assigned by main.gd


func _ready() -> void:
	super()
	add_to_group("player")


## True while seated and, once the player committed to "Get in", also during the entering animation (VehicleSeat.Mode.ENTERING = 1).
func is_in_vehicle() -> bool:
	return in_vehicle or (seat != null and int(seat.get("mode")) == 1)


func enter_vehicle(vehicle: Node3D) -> void:
	if seat != null:
		seat.call("enter", vehicle)


## Other modules ask for the exit while the car may still be rolling: the seat brakes first, then the officer gets out.
func exit_vehicle() -> void:
	if seat != null:
		seat.call("request_exit")
