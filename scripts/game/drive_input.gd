extends RefCounted
## Keyboard -> Vehicle controls: W/S throttle, brake and reverse, A/D steering, Space hand brake.
## Inputs are ramped so the binary keys do not slam the pedals; Vehicle already limits the steering lock by speed.
## Rolling resistance and engine braking live in Vehicle (coast_mph_s): lifting off the throttle needs no help here.

const THROTTLE_RISE := 4.5     # 1/s
const THROTTLE_FALL := 8.0
const STEER_RISE := 3.4
const STEER_FALL := 6.0

var throttle := 0.0
var steer := 0.0


func reset() -> void:
	throttle = 0.0
	steer = 0.0


func apply(car: Vehicle, delta: float) -> void:
	var want_throttle := Input.get_axis("move_back", "move_forward")
	var want_steer := Input.get_axis("move_left", "move_right")
	throttle = move_toward(throttle, want_throttle, (THROTTLE_RISE if want_throttle != 0.0 else THROTTLE_FALL) * delta)
	steer = move_toward(steer, want_steer, (STEER_RISE if want_steer != 0.0 else STEER_FALL) * delta)
	car.set_controls(throttle, steer, 0.0)
	car.set_handbrake(Input.is_action_pressed("handbrake"))


## Parks the car (nobody at the wheel): no pedals, hand brake on.
func park(car: Vehicle) -> void:
	reset()
	car.set_controls(0.0, 0.0, 0.0)
	car.set_handbrake(true)
