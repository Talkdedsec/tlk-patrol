extends Node
## Drives a car that the officer stopped, through the Vehicle API only (set_throttle / set_steer / set_brake / speed_mph):
## pull to the right and stop, creep forward, turn into the next street on the right, follow the patrol car, hold.
## Pure pursuit steering plus a speed profile that brakes at a constant deceleration (the car slows and parks to the right 4-6 s
## after the lights; "Pull up further" moves it about one car length).

const Adapters := preload("res://scripts/traffic_stop/adapters.gd")

signal stopped
signal arrived

enum Mode { IDLE, ROUTE, FOLLOW, HOLD }

const MPH := 0.44704
const BRAKE_DECEL := 3.5       # m/s^2 used for the stopping profile
const LANE_SHIFT := 3.2        # most metres to the right of the current line when parking
const CURB_MARGIN := 0.9       # the car stays this far (centre) inside the road edge
const PURSUIT_SPEED := 8.0     # mph limit while manoeuvring

var vehicle: Node3D
var mode: int = Mode.IDLE
var max_mph: float = 25.0

var _route: Array[Vector3] = []
var _follow_target: Node3D
var _announced := false


func attach(target: Node3D) -> void:
	vehicle = target
	set_physics_process(true)


## Pulls over to the right: S-curve into the shoulder, then stops.
func pull_over() -> void:
	var start := _flat(vehicle.global_position)
	var fwd := _flat_dir(Adapters.forward(vehicle))
	var right := _flat_dir(Adapters.right(vehicle))
	var speed := Adapters.speed_mph(vehicle) * MPH
	var run := maxf(28.0, speed * speed / (2.0 * BRAKE_DECEL) + 14.0)
	var shift := lane_shift()
	_set_route([start + fwd * run * 0.35 + right * shift * 0.35, start + fwd * run * 0.7 + right * shift * 0.9,
		start + fwd * run + right * shift], maxf(Adapters.speed_mph(vehicle), 15.0))


## Sideways move when parking: LANE_SHIFT, or less on a narrow road so the car stays on the asphalt:
## min(LANE_SHIFT, distance to the road edge - CURB_MARGIN). The edge comes from the road graph (Adapters.road_room_right).
func lane_shift() -> float:
	var room := Adapters.road_room_right(vehicle)
	if room < 0.0:
		return LANE_SHIFT
	return clampf(room - CURB_MARGIN, 0.0, LANE_SHIFT)


## Rolls forward a few metres and stops again ("Pull up further").
func creep(metres: float = 8.0) -> void:
	var start := _flat(vehicle.global_position)
	_set_route([start + _flat_dir(Adapters.forward(vehicle)) * metres], 6.0)


## Drives about 20 m ahead, then turns right into the next street and stops.
## TODO(tahmin): no road graph is read; the turn is a fixed L shape relative to the car.
func turn_right_into_side_street() -> void:
	var start := _flat(vehicle.global_position)
	var fwd := _flat_dir(Adapters.forward(vehicle))
	var right := _flat_dir(Adapters.right(vehicle))
	_set_route([start + fwd * 14.0 + right * 1.0, start + fwd * 20.0 + right * 6.0, start + fwd * 21.0 + right * 18.0], 10.0)


func follow(target: Node3D, speed_mph_limit: float = 20.0) -> void:
	Adapters.set_handbrake(vehicle, false)
	_follow_target = target
	max_mph = speed_mph_limit
	mode = Mode.FOLLOW
	_announced = false


func hold() -> void:
	mode = Mode.HOLD
	_route.clear()
	Adapters.drive(vehicle, 0.0, 0.0, 1.0)
	Adapters.set_handbrake(vehicle, true)


func is_moving() -> bool:
	return mode == Mode.ROUTE or mode == Mode.FOLLOW


func _set_route(points: Array[Vector3], limit_mph: float) -> void:
	Adapters.set_handbrake(vehicle, false)
	_route = points
	max_mph = limit_mph
	mode = Mode.ROUTE
	_announced = false


func _physics_process(_delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	match mode:
		Mode.ROUTE:
			_drive_route()
		Mode.FOLLOW:
			_drive_follow()
		Mode.HOLD:
			Adapters.drive(vehicle, 0.0, 0.0, 1.0)


func _drive_route() -> void:
	if _route.is_empty():
		hold()
		return
	var final := _route.size() == 1
	var target := _route[0]
	var pos := _flat(vehicle.global_position)
	var to := target - pos
	var distance := to.length()
	var speed := Adapters.speed_mph(vehicle) * MPH
	if not final and distance < 3.5:
		_route.pop_front()
		return
	var limit := max_mph * MPH
	var wanted := limit
	if final:
		wanted = minf(limit, sqrt(2.0 * BRAKE_DECEL * maxf(distance - 0.4, 0.0)))
	var steer := _steer_to(to)
	_apply_speed(wanted, speed, steer)
	if final and distance < 0.9 and speed < 0.4:
		hold()
		if not _announced:
			_announced = true
			stopped.emit()
			arrived.emit()


func _drive_follow() -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		hold()
		return
	var pos := _flat(vehicle.global_position)
	var to := _flat(_follow_target.global_position) - pos
	var distance := to.length()
	var speed := Adapters.speed_mph(vehicle) * MPH
	var wanted := clampf((distance - 9.0) * 0.8, 0.0, max_mph * MPH)
	_apply_speed(wanted, speed, _steer_to(to))


func _steer_to(to: Vector3) -> float:
	var fwd := _flat_dir(Adapters.forward(vehicle))
	var right := _flat_dir(Adapters.right(vehicle))
	if to.length() < 0.01:
		return 0.0
	var error := fwd.angle_to(to.normalized())
	var side := signf(to.dot(right))
	return clampf(side * error / 0.55, -1.0, 1.0)


func _apply_speed(wanted: float, speed: float, steer: float) -> void:
	var diff := wanted - speed
	var throttle := clampf(diff * 0.35, 0.0, 0.55)
	var brake := clampf(-diff * 0.4, 0.0, 1.0)
	if wanted < 0.2 and speed < 0.6:
		brake = 1.0
		throttle = 0.0
	Adapters.drive(vehicle, throttle, steer, brake)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _flat_dir(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	return flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
