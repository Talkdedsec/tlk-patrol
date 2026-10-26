extends Node3D
## Bare-bones officer double for headless tests: the four contract signals, a muzzle and a kick recorder.
## No camera, no input; tests emit the signals themselves.

signal fire_requested
signal aim_changed(aiming: bool)
signal draw_requested
signal reload_requested

var muzzle_position := Vector3(0.3, 1.4, -0.6)
var kick_pitch := 0.0
var kick_yaw := 0.0
var kick_peak := 0.0


func get_muzzle_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, global_position + muzzle_position)


func set_camera_kick(pitch: float, yaw: float) -> void:
	kick_pitch = pitch
	kick_yaw = yaw
	kick_peak = maxf(kick_peak, pitch)
