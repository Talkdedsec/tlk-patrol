class_name StepUp
extends RefCounted
## Shared walking helpers for scripted characters: climb low steps (curbs) and steer around obstacles taller than a step.

const STEP_HEIGHT := 0.35
const LOOKAHEAD := 0.9
const AVOID_ANGLES: Array[float] = [45.0, 90.0, 135.0, 170.0]
const COMMIT_MSEC := 700      # keep a chosen detour direction this long (wall following instead of dithering)


## True when `motion` (horizontal) would hit something the body cannot step over.
static func blocked(body: CharacterBody3D, motion: Vector3, step_height: float = STEP_HEIGHT) -> bool:
	if not body.test_move(body.global_transform, motion):
		return false
	var raised := body.global_transform.translated(Vector3.UP * step_height)
	return body.test_move(raised, motion)


## Lifts the body over a low obstacle in its way (call before move_and_slide; floor_snap_length drops it back down).
static func step_up(body: CharacterBody3D, delta: float, step_height: float = STEP_HEIGHT) -> void:
	var motion := Vector3(body.velocity.x, 0.0, body.velocity.z) * delta
	if motion.length() < 0.0005 or not body.is_on_floor():
		return
	motion = motion.normalized() * maxf(motion.length(), 0.12)
	if not body.test_move(body.global_transform, motion):
		return
	var raised := body.global_transform.translated(Vector3.UP * step_height)
	if body.test_move(raised, motion):
		return
	body.global_position.y += step_height


## Returns `wish` or, when it runs into a tall obstacle, the closest free direction (remembers the preferred side).
static func steer(body: CharacterBody3D, wish: Vector3, lookahead: float = LOOKAHEAD) -> Vector3:
	if wish.length() < 0.01:
		return wish
	var now := Time.get_ticks_msec()
	var committed: Vector3 = body.get_meta(&"avoid_dir", Vector3.ZERO)
	if committed != Vector3.ZERO and now < int(body.get_meta(&"avoid_until", 0)):
		if not blocked(body, committed * lookahead):
			return committed * wish.length()
	var forward := wish.normalized() * lookahead
	if not blocked(body, forward):
		body.set_meta(&"avoid_dir", Vector3.ZERO)
		return wish
	var side: float = float(body.get_meta(&"avoid_side", 1.0))
	for angle in AVOID_ANGLES:
		for sign_value in [side, -side]:
			var candidate := forward.rotated(Vector3.UP, deg_to_rad(angle * float(sign_value)))
			if not blocked(body, candidate):
				body.set_meta(&"avoid_side", float(sign_value))
				body.set_meta(&"avoid_dir", candidate.normalized())
				body.set_meta(&"avoid_until", now + COMMIT_MSEC)
				return candidate.normalized() * wish.length()
	return wish
