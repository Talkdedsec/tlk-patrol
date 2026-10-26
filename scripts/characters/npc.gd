class_name Npc
extends CharacterBody3D
## Pedestrian / suspect / AI officer base: outfit selection, state machine (idle walk flee surrender downed cuffed ...),
## walking to a target (NavigationAgent3D when a navigation map exists, straight line otherwise) and animations.
##
## States: idle, walk, flee, surrender, kneel, downed, cuffed, talk, seated.

signal state_changed(state: StringName)
signal arrived
signal walk_blocked
signal shot_fired(weapon: StringName)

const MODELS := {
	"civilian": "res://assets/models/characters/civilian.glb",
	"police": "res://assets/models/characters/officer_police.glb",
	"sheriff": "res://assets/models/characters/officer_sheriff.glb",
}
const WALK_SPEED := 1.4          # TODO(tahmin): pedestrian walking pace
const FLEE_SPEED := 4.57         # 15 ft/s, same as the officer's run
const GRAVITY := 20.0
const TURN_RATE := 10.0
const ARRIVE_DISTANCE := 0.35
const STUCK_TIME := 2.0
const STUCK_PROGRESS := 0.4
const FLEE_PROBE_ANGLES: Array[float] = [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 130.0, -130.0]
const FLEE_PROBE_HEIGHT := 0.5     # above curbs, hits hydrants / rails / cars
const WeaponDef := preload("res://scripts/weapons/weapon_def.gd")
const WeaponFx := preload("res://scripts/weapons/weapon_fx.gd")
const RUN_STATE_SPEED := 3.1
const SHOT_SOUND_DIR := "res://assets/audio/weapons/"

@export var model_kind: String = "civilian"
@export var outfit: StringName = &"white_shirt"
@export var skin_index: int = 0
@export var height_scale: float = 1.0

var rig: CharacterRig
var nav: NavigationAgent3D
var state: StringName = &"idle"

var _target := Vector3.ZERO
var _has_target := false
var _speed := WALK_SPEED
var _flee_from := Vector3.ZERO
var _path: Array[Vector3] = []
var _arrive_radius: float = ARRIVE_DISTANCE
var _anchor: Vector3 = Vector3.INF
var _stuck: float = 0.0
var _walk_time: float = 0.0
var _walk_budget: float = 0.0


func _ready() -> void:
	collision_layer = 1 << 2
	floor_snap_length = StepUp.STEP_HEIGHT + 0.1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	rig = CharacterRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.setup(MODELS.get(model_kind, MODELS["civilian"]))
	rig.scale = Vector3.ONE * height_scale
	if model_kind == "civilian":
		Outfits.apply(rig.model, outfit, skin_index)
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.4
	nav.target_desired_distance = ARRIVE_DISTANCE
	nav.radius = 0.35
	add_child(nav)


func set_outfit(new_outfit: StringName, new_skin: int = -1) -> void:
	outfit = new_outfit
	if new_skin >= 0:
		skin_index = new_skin
	if rig != null and model_kind == "civilian":
		Outfits.apply(rig.model, outfit, skin_index)


func _set_state(value: StringName) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(state)


# --- commands -----------------------------------------------------------------------------------------------------
func walk_to(position_target: Vector3, speed: float = WALK_SPEED, arrive_radius: float = ARRIVE_DISTANCE) -> void:
	if state in [&"downed", &"cuffed", &"kneel", &"seated"]:
		return
	_clear_posture()
	_path.clear()
	_arrive_radius = arrive_radius
	_anchor = Vector3.INF
	_stuck = 0.0
	_target = position_target
	_reset_walk_budget()
	_has_target = true
	_speed = speed
	nav.target_position = position_target
	_set_state(&"walk")


func flee_from(source: Vector3, distance: float = 40.0) -> void:
	if state in [&"downed", &"cuffed", &"kneel", &"seated"]:
		return
	_clear_posture()
	_flee_from = source
	var away := global_position - source
	away.y = 0.0
	if away.length() < 0.1:
		away = -global_transform.basis.z
	var run_dir := _pick_flee_direction(away.normalized(), distance)
	_path.clear()
	_arrive_radius = ARRIVE_DISTANCE
	_anchor = Vector3.INF
	_stuck = 0.0
	_target = global_position + run_dir * distance
	_reset_walk_budget()
	_has_target = true
	_speed = FLEE_SPEED
	nav.target_position = _target
	_set_state(&"flee")


## Follows waypoints in order at `speed`, emits `arrived` after the last one. run_along() uses the run speed (FLEE_SPEED).
func follow_path(points: Array, speed: float = WALK_SPEED, arrive_radius: float = ARRIVE_DISTANCE) -> void:
	if points.is_empty() or state in [&"downed", &"cuffed", &"kneel", &"seated"]:
		return
	var rest: Array[Vector3] = []
	for point: Vector3 in points:
		rest.append(point)
	var first: Vector3 = rest.pop_front()
	walk_to(first, speed, arrive_radius)
	_path = rest
	if speed >= RUN_STATE_SPEED:
		_set_state(&"flee")


func run_along(points: Array, speed: float = FLEE_SPEED, arrive_radius: float = ARRIVE_DISTANCE) -> void:
	follow_path(points, speed, arrive_radius)


func stop() -> void:
	_path.clear()
	_has_target = false
	if state == &"walk" or state == &"flee":
		_set_state(&"idle")


func surrender() -> void:
	if state in [&"downed", &"cuffed", &"kneel", &"seated"]:
		return
	_has_target = false
	rig.set_overlay(&"hands_up")
	_set_state(&"surrender")


func kneel() -> void:
	if state in [&"downed", &"seated"]:
		return
	_has_target = false
	rig.clear_overlay()
	rig.play_full(&"kneel")
	_set_state(&"kneel")
	rig.full_finished.connect(_on_kneel_done, CONNECT_ONE_SHOT)


func _on_kneel_done(_anim: StringName) -> void:
	if state == &"kneel":
		rig.play_full(&"kneel_hold")


## kind: &"shot" (death_fall, 600 ms to prone) or &"taser" (taser_fall).
func go_down(kind: StringName = &"shot") -> void:
	_has_target = false
	rig.clear_overlay()
	rig.play_full(&"death_fall" if kind == &"shot" else &"taser_fall")
	_set_state(&"downed")


func cuff() -> void:
	_has_target = false
	match state:
		&"downed":
			rig.play_full(&"cuffed_prone")
		&"kneel":
			rig.play_full(&"kneel_cuffed")
		_:
			rig.release_full()
			rig.set_overlay(&"hands_behind")
	_set_state(&"cuffed")


func talk(anim_name: StringName = &"talk_a") -> void:
	if state in [&"idle", &"talk"]:
		rig.set_overlay(anim_name)
		_set_state(&"talk")


func sit(driver: bool) -> void:
	_has_target = false
	rig.clear_overlay()
	rig.play_full(&"sit_drive" if driver else &"sit_passenger")
	_set_state(&"seated")


func stand_up() -> void:
	rig.release_full()
	rig.clear_overlay()
	_set_state(&"idle")


## Weapon in hand (AI officers / armed suspects).
func equip(weapon_id: StringName, aim: bool = false) -> void:
	rig.set_loadout([weapon_id])
	rig.draw(weapon_id)
	if aim:
		rig.weapon_state_changed.connect(func(s: StringName) -> void:
			if s == &"ready":
				rig.set_aiming(true), CONNECT_ONE_SHOT)


## Shot with effects: muzzle flash + smoke + tracer (WeaponFx), positional gun sound, recoil animation. Damage is not
## applied here (scenario / AI code decides). `target`: Vector3 or Node3D the tracer streaks towards (optional).
func fire(weapon_id: StringName = &"", target: Variant = null) -> bool:
	var id := weapon_id if weapon_id != &"" else rig.weapon
	if id == &"":
		return false
	if rig.weapon != id:
		equip(id)
	var def: RefCounted = WeaponDef.make(id)
	if def == null:
		return false
	rig.fire()
	var muzzle := rig.muzzle_transform()
	var parent: Node = get_parent() if get_parent() != null else self
	var scale := 1.0
	var weapons_node := get_node_or_null("/root/Weapons")
	if weapons_node != null and "fx_time_scale" in weapons_node:
		scale = float(weapons_node.fx_time_scale)
	WeaponFx.muzzle_flash(parent, muzzle, def, scale)
	WeaponFx.smoke(parent, muzzle, def, scale)
	if def.tracer and target != null:
		var end_point: Vector3 = target if target is Vector3 else (target as Node3D).global_position + Vector3(0.0, 1.2, 0.0)
		WeaponFx.tracer(parent, muzzle.origin, end_point, scale)
	_play_shot_sound(def, parent, muzzle.origin)
	shot_fired.emit(id)
	return true


func _play_shot_sound(def: RefCounted, parent: Node, at: Vector3) -> void:
	var path := SHOT_SOUND_DIR + String(def.shot_sound) + ".wav"
	if not ResourceLoader.exists(path):
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = load(path) as AudioStream
	player.unit_size = 12.0
	parent.add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


func _reset_walk_budget() -> void:
	_walk_time = 0.0
	var flat := _target - global_position
	flat.y = 0.0
	_walk_budget = flat.length() / WALK_SPEED * 2.0 + 5.0


## Picks the run direction closest to `away` that has free space ahead (obstacles taller than a curb count: rails,
## hydrants, cars); along a barrier the best free direction runs parallel to it.
func _pick_flee_direction(away: Vector3, distance: float) -> Vector3:
	if not is_inside_tree():
		return away
	var space := get_world_3d().direct_space_state
	var probe_length := minf(distance, 14.0)
	var origin := global_position + Vector3(0.0, FLEE_PROBE_HEIGHT, 0.0)
	var best := away
	var best_score := -INF
	for angle in FLEE_PROBE_ANGLES:
		var dir := away.rotated(Vector3.UP, deg_to_rad(angle))
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * probe_length)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		var free := probe_length if hit.is_empty() else origin.distance_to(hit["position"])
		var score := minf(free, probe_length) * (0.55 + 0.45 * away.dot(dir))
		if score > best_score:
			best_score = score
			best = dir
	return best


func _clear_posture() -> void:
	if state in [&"surrender", &"talk"]:
		rig.clear_overlay()


# --- movement -----------------------------------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	var wish := Vector3.ZERO
	if _has_target and state in [&"walk", &"flee"]:
		var next_point := _target
		if _has_navigation() and not nav.is_navigation_finished():
			next_point = nav.get_next_path_position()
		var to_next := next_point - global_position
		to_next.y = 0.0
		var distance := Vector2(_target.x - global_position.x, _target.z - global_position.z).length()
		var radius := _arrive_radius if _path.is_empty() else maxf(_arrive_radius, 0.6)
		if distance <= radius:
			if not _path.is_empty():
				_target = _path.pop_front()
				nav.target_position = _target
				_anchor = Vector3.INF
				_stuck = 0.0
				_reset_walk_budget()
			else:
				_has_target = false
				_set_state(&"idle")
				arrived.emit()
		elif to_next.length() > 0.01:
			_walk_time += delta
			if _walk_time > _walk_budget:
				_stuck = STUCK_TIME
			wish = StepUp.steer(self, to_next.normalized())
			if _anchor == Vector3.INF or global_position.distance_to(_anchor) > STUCK_PROGRESS:
				_anchor = global_position
				_stuck = 0.0
			else:
				_stuck += delta
				if _stuck >= STUCK_TIME:
					_has_target = false
					_path.clear()
					wish = Vector3.ZERO
					_set_state(&"idle")
					walk_blocked.emit()
	var target_velocity := wish * _speed
	velocity.x = move_toward(velocity.x, target_velocity.x, 30.0 * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, 30.0 * delta)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	StepUp.step_up(self, delta)
	move_and_slide()
	if wish.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-wish.x, -wish.z), minf(TURN_RATE * delta, 1.0))
	rig.set_motion(global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z))


func _has_navigation() -> bool:
	return NavigationServer3D.map_get_regions(nav.get_navigation_map()).size() > 0
