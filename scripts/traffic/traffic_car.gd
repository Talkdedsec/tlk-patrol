extends "res://scripts/traffic/lane_driver.gd"
## Ambient traffic driver: keeps the lane, obeys the speed limit, signals and stop signs, follows the car ahead,
## pulls over for an approaching siren, slows or stops in Traffic zones.

const SIREN_RANGE := 70.0
const SIREN_SPEED := 5.0
const PULL_RIGHT := -2.4

var cruise_factor := 1.0
var owned := true                   # spawned by Traffic (may be despawned)
var protected := false              # held for a stop / pulled over: never freed, cleared or recycled
var siren_source: Node3D = null
var pull_over_cmd := false          # stop at the right edge (traffic stop)
var zone_cap: Callable = Callable() # (Vector3) -> float speed cap in m/s, INF when free
var _yielding := false


func attach(v: Node3D, g: Object) -> void:
	super.attach(v, g)
	cruise_factor = rng.randf_range(0.9, 1.02)
	headway = rng.randf_range(1.0, 1.5)


func _speed_cap() -> float:
	var cap := super._speed_cap() * cruise_factor
	if pull_over_cmd:
		return 0.0
	if _yielding:
		cap = minf(cap, SIREN_SPEED)
	if zone_cap.is_valid():
		cap = minf(cap, float(zone_cap.call(vehicle.global_position)))
	return cap


func _update_shift(_dt_: float, pos: Vector3, fwd: Vector3, _v: float) -> void:
	_yielding = false
	if siren_source != null and is_instance_valid(siren_source) and Adapters.lights_on():
		var to_src := siren_source.global_position - pos
		to_src.y = 0.0
		var dist := to_src.length()
		if dist < SIREN_RANGE and to_src.dot(fwd) < 0.0:
			_yielding = true
	shift_target = PULL_RIGHT if (_yielding or pull_over_cmd) else 0.0
