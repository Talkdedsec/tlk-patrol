extends Node
## Pure-pursuit driver for scenarios and recordings: follows a list of world points with Vehicle.steer_towards and
## Vehicle.set_cruise_mph. The seat controller must be in scripted_drive mode so the keyboard does not fight it.

var vehicle: Vehicle
var points := PackedVector3Array()
var cruise_mph := 35.0
var lookahead := 7.0              # metres, grows with speed
var active := true

var _index := 0


## Straight line ahead of the vehicle's heading, `length` metres in `step` metre points.
func follow_straight(car: Vehicle, length: float, mph: float, step := 10.0) -> void:
	vehicle = car
	cruise_mph = mph
	points = PackedVector3Array()
	var forward := -car.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var start := car.global_position
	var distance := step
	while distance <= length:
		points.append(start + forward * distance)
		distance += step
	_index = 0
	active = true


func stop(brake := 1.0) -> void:
	active = false
	if vehicle != null and is_instance_valid(vehicle):
		vehicle.set_cruise_mph(-1.0)
		vehicle.set_controls(0.0, 0.0, brake)


func _physics_process(_delta: float) -> void:
	if not active or vehicle == null or not is_instance_valid(vehicle) or points.is_empty():
		return
	var pos := vehicle.global_position
	var look := lookahead + vehicle.speed_ms() * 0.5
	while _index < points.size() - 1 and pos.distance_to(points[_index]) < look * 0.5:
		_index += 1
	var target := points[points.size() - 1]
	for i in range(_index, points.size()):
		if pos.distance_to(points[i]) >= look:
			target = points[i]
			break
	vehicle.steer_towards(target)
	vehicle.set_cruise_mph(cruise_mph)
