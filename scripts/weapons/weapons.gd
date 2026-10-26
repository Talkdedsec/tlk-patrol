extends Node
## Weapon system autoload (owner: weapons session). Contract: docs/MIMARI.md, API: docs/api/weapons.md.
## Pistol 17/34, Patrol rifle 29/56, Shotgun 6/18; draw/holster (key 5), aim, fire, reload, raycast hits, crosshair,
## shot effects and sounds. Guesses are marked TODO(tahmin).

const WeaponDef := preload("res://scripts/weapons/weapon_def.gd")
const WeaponFx := preload("res://scripts/weapons/weapon_fx.gd")
const WeaponAdapters := preload("res://scripts/weapons/adapters.gd")
const WeaponAudio := preload("res://scripts/weapons/weapon_audio.gd")
const CROSSHAIR_SCENE := "res://scenes/weapons/crosshair.tscn"

enum State { HOLSTERED, DRAWING, READY, RELOADING, HOLSTERING }

## Part -> damage multiplier. TODO(tahmin): body-part rules are our own.
const PART_MULTIPLIER := {"head": 2.5, "torso": 1.0, "arms": 0.6, "legs": 0.6}
const AIM_ZOOM_TIME := 0.2           ## fallback zoom ramp (tuned aim camera moves take 0.15-0.3 s)
const DRY_CLICK_GAP := 0.3
const KICK_STACK_LIMIT := 1.6

signal shot_fired(origin: Vector3, dir: Vector3, weapon: StringName)
signal target_hit(npc: Node, damage: float, part: String)
signal target_downed(npc: Node, weapon: StringName, lethal: bool)
signal ammo_changed(weapon: StringName, magazine: int, reserve: int)
signal equipped_changed(weapon: StringName)          ## &"" when holstered
signal aim_changed(aiming: bool)
signal state_changed(state: int)
signal reload_started(weapon: StringName)
signal reload_finished(weapon: StringName)
signal dry_fired(weapon: StringName)
signal impact(position: Vector3, normal: Vector3, collider: Object)

var equipped: StringName = &""                       ## weapon id while drawn (also during holstering), else &""
var selected: StringName = &"pistol"                 ## what key 5 draws next
var state: State = State.HOLSTERED
var aiming := false
var inventory: Array[StringName] = [&"pistol", &"rifle", &"shotgun"]
var officer: Node                                    ## bound through bind_officer()
var direct_input := true                             ## read mouse/keys itself (placeholder player); off once an Officer is bound
var manual_tick := false                             ## tests call tick() themselves
var fx_time_scale := 1.0                             ## stretch effect durations (screenshots / slow motion)
var tracers_enabled := true
var casings_enabled := true
var damage_enabled := true
var hit_marker_on_dead := true                       ## the hit marker also shows on a target that is already down
var holster_hud_time := 0.6                          ## HUD weapon line closes this long after the holster starts (0.6 s); < 0 follows the animation
var auto_bind := true                                ## bind the first player officer that enters the tree
var officer_recoil := false                          ## true: leave camera kick + pump to Officer.notify_shot() (shotgun kick 23 px instead of 70)
var fallback_zoom := true                            ## zoom the FOV when aiming without an Officer
var reload_hold_time := 0.4                          ## TODO(tahmin): how long R must be held ("hold R reload")
var time := 0.0                                      ## accumulated game time (deterministic with manual_tick)
var hud: Node:
	get:
		return _adapters.hud()
	set(value):
		_adapters.hud_override = value

var _defs: Dictionary = {}
var _ammo: Dictionary = {}
var _adapters: WeaponAdapters
var _audio: WeaponAudio
var _crosshair: Node
var _ui_host: Node
var _state_left := 0.0
var _hud_close_left := 0.0
var _hud_hidden := false
var _reload_left := 0.0
var _next_fire := 0.0
var _next_dry := 0.0
var _aim_wanted := false
var _zoom := 0.0
var _kick_pitch := 0.0
var _kick_yaw := 0.0
var _kick_age := 0.0
var _kick_duration := 0.2
var _ext_move := 0.0
var _ext_move_until := -1.0
var _last_cam_origin := Vector3.ZERO
var _last_cam_forward := Vector3.FORWARD
var _have_last_cam := false
var _aim_input_prev := false
var _reload_held := 0.0
var _reload_triggered := false
var _hud_pushed: Node


func _ready() -> void:
	process_priority = 100                           # after the camera / officer update so kick offsets land last
	_adapters = WeaponAdapters.new()
	_adapters.host = self
	for id in WeaponDef.ids():
		var def: RefCounted = WeaponDef.make(id)
		_defs[id] = def
		_ammo[id] = {"mag": def.mag_size, "reserve": def.start_reserve}
	_audio = WeaponAudio.new()
	_audio.name = "Audio"
	add_child(_audio)
	_register_actions()
	get_tree().node_added.connect(_on_node_added)


## Plug and play: the first player officer (a node with the four contract signals and input enabled) that enters the tree is bound.
func _on_node_added(node: Node) -> void:
	if not auto_bind or has_officer():
		return
	if node.has_signal("fire_requested") and node.has_signal("aim_changed") and node.has_signal("draw_requested") \
			and node.has_signal("reload_requested") and bool(node.get("input_enabled") if "input_enabled" in node else true):
		_auto_bind.call_deferred(node)


func _auto_bind(node: Node) -> void:
	if is_instance_valid(node) and node.is_inside_tree() and not has_officer():
		bind_officer(node)


func _register_actions() -> void:
	var wheel := {"weapon_next": MOUSE_BUTTON_WHEEL_DOWN, "weapon_prev": MOUSE_BUTTON_WHEEL_UP}
	var keys := {"weapon_next": KEY_BRACKETRIGHT, "weapon_prev": KEY_BRACKETLEFT}   # TODO(tahmin): switch keys are our choice
	for action: String in wheel:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventMouseButton.new()
			event.button_index = wheel[action] as MouseButton
			InputMap.action_add_event(action, event)
			var key_event := InputEventKey.new()
			key_event.physical_keycode = keys[action] as Key
			InputMap.action_add_event(action, key_event)


func _process(delta: float) -> void:
	if not manual_tick:
		tick(delta)


## Advances all timers. Called every frame unless manual_tick is set (deterministic tests, scenario replays).
func tick(delta: float) -> void:
	time += delta
	if _crosshair != null and is_instance_valid(_crosshair):
		_crosshair.manual = manual_tick
		if manual_tick:
			_crosshair.tick(delta)
	_tick_state(delta)
	if direct_input and not has_officer():
		_tick_direct_input(delta)
	_refresh_aim()
	_tick_movement(delta)
	_tick_crosshair_target()
	_tick_zoom(delta)
	_tick_kick(delta)
	_tick_hud()


# --- public API: state ---------------------------------------------------------------

func has_officer() -> bool:
	return officer != null and is_instance_valid(officer)


func is_ready() -> bool:
	return state == State.READY


func is_drawn() -> bool:
	return equipped != &""


func weapon_name(weapon: Variant = &"") -> String:
	var id := _resolve(weapon)
	return (_defs[id] as RefCounted).display_name if _defs.has(id) else ""


## Draws a weapon ("Pistol", "Patrol rifle", "Shotgun" or the ids pistol/rifle/shotgun). `instant` skips the draw animation time.
func equip(weapon: Variant, instant := false) -> bool:
	var id := WeaponDef.resolve_id(weapon)
	if id == &"" or not inventory.has(id):
		return false
	if equipped == id and state != State.HOLSTERING:
		if instant and state == State.DRAWING:
			_set_state(State.READY)
		return true
	_cancel_reload()
	equipped = id
	selected = id
	_hud_hidden = false
	var def := _def()
	_ensure_ui()
	_configure_crosshair()
	_next_fire = time
	_audio.play(&"draw", -6.0)
	if instant:
		_set_state(State.READY)
	else:
		_state_left = _adapters.draw_time(id, def.draw_time)
		_set_state(State.DRAWING)
	_adapters.visual_draw(id)
	_refresh_aim()
	_push_hud()
	equipped_changed.emit(id)
	return true


## Lowers the weapon. The HUD line and the crosshair close when the animation time is over (0.6 s).
func holster(instant := false) -> void:
	if equipped == &"" or state == State.HOLSTERING:
		return
	_cancel_reload()
	if instant:
		_adapters.visual_holster()
		_finish_holster()
		return
	_state_left = _adapters.holster_time(equipped, _def().holster_time)
	_hud_close_left = holster_hud_time
	_hud_hidden = false
	_adapters.visual_holster()
	_audio.play(&"holster", -6.0)
	_set_state(State.HOLSTERING)
	_refresh_aim()


## Key `5`: draws the selected weapon, or lowers the drawn one.
func toggle_draw() -> void:
	if equipped == &"":
		equip(selected)
	elif state == State.READY or state == State.RELOADING:
		holster()


## Keys 1 / 2 / 3: draw that weapon (pistol / patrol rifle / shotgun); the same key again lowers it.
func _slot_key(id: StringName) -> void:
	if equipped == id and state != State.HOLSTERING:
		holster()
	else:
		equip(id)


## Next / previous weapon in the inventory (mouse wheel). While holstered it only changes what key 5 will draw.
func cycle_weapon(direction := 1) -> bool:
	if inventory.size() < 2:
		return false
	var index := inventory.find(selected)
	var next: StringName = inventory[posmod(index + direction, inventory.size())]
	if equipped != &"" and state != State.HOLSTERING:
		return equip(next)
	selected = next
	return true


func set_aim(on: bool) -> void:
	_aim_wanted = on
	_refresh_aim()


func set_ammo(magazine: int, reserve: int, weapon: Variant = &"") -> void:
	var id := _resolve(weapon)
	if not _ammo.has(id):
		return
	_ammo[id] = {"mag": maxi(magazine, 0), "reserve": maxi(reserve, 0)}
	_ammo_updated(id)


func get_ammo(weapon: Variant = &"") -> Dictionary:
	var id := _resolve(weapon)
	return (_ammo[id] as Dictionary).duplicate() if _ammo.has(id) else {"mag": 0, "reserve": 0}


func add_weapon(weapon: Variant) -> void:
	var id := WeaponDef.resolve_id(weapon)
	if id != &"" and not inventory.has(id):
		inventory.append(id)


func remove_weapon(weapon: Variant) -> void:
	var id := WeaponDef.resolve_id(weapon)
	if id == equipped:
		holster(true)
	inventory.erase(id)
	if selected == id and not inventory.is_empty():
		selected = inventory[0]


## Restores factory ammo and holsters everything (tests, new scenario).
func reset() -> void:
	holster(true)
	for id: StringName in _defs:
		var def: RefCounted = _defs[id]
		_ammo[id] = {"mag": def.mag_size, "reserve": def.start_reserve}
	_next_fire = 0.0
	_aim_wanted = false
	_kick_pitch = 0.0
	_kick_yaw = 0.0
	_adapters.apply_camera_kick(0.0, 0.0)


# --- public API: actions ---------------------------------------------------------------

## Trigger pull from the player. Returns true when a round was fired.
func fire() -> bool:
	return _shoot({})


## Scripted shot for scenarios: fires at a Node3D / Npc (aim point from `part`) or a world position.
## `hit = false` aims past the target on purpose. Cooldown is ignored by default so recorded shot times replay exactly.
func fire_at(target: Variant, part := "torso", hit := true, ignore_cooldown := true) -> bool:
	var point := Vector3.ZERO
	var node: Node = null
	if target is Vector3:
		point = target
	elif target is Node:
		node = target
		point = _adapters.aim_point(node, part)
	else:
		return false
	if not hit:
		point += Vector3(1.0, 0.0, 0.0) * 3.0
	return _shoot({"point": point, "target": node if hit else null, "part": part, "ignore_cooldown": ignore_cooldown})


## Starts a reload (what holding R does). Returns false when drawn weapon is full, out of reserve or busy.
func start_reload() -> bool:
	if equipped == &"" or state != State.READY:
		return false
	var def := _def()
	var ammo: Dictionary = _ammo[equipped]
	if ammo["mag"] >= def.mag_size or ammo["reserve"] <= 0:
		return false
	_reload_left = def.reload_time if def.tube_reload else _adapters.reload_time(equipped, def.reload_time)
	_set_state(State.RELOADING)
	_adapters.visual_reload()
	if not def.tube_reload:
		_audio.play(def.reload_sound, -3.0)
	reload_started.emit(equipped)
	return true


func cancel_reload() -> void:
	_cancel_reload()


## Movement input from the officer: speed in m/s and turn rate in degrees/s. Opens the crosshair (+-50-60 px).
func set_movement(speed: float, turn_deg_per_s := 0.0) -> void:
	_ext_move = clampf(maxf(speed / 2.5, turn_deg_per_s / 120.0), 0.0, 1.0)
	_ext_move_until = time + 0.25


func get_crosshair() -> Node:
	return _crosshair


## Binds the player character. Expected optional signals: fire_requested, aim_changed(aiming), draw_requested,
## reload_requested (+ holster_requested, weapon_cycle_requested(direction)). See docs/api/weapons.md.
func bind_officer(node: Node) -> void:
	unbind_officer()
	officer = node
	_adapters.officer = node
	var wired := 0
	wired += _wire(node, &"fire_requested", _on_officer_fire)
	wired += _wire(node, &"aim_changed", _on_officer_aim)
	wired += _wire(node, &"draw_requested", _on_officer_draw)
	wired += _wire(node, &"reload_requested", _on_officer_reload)
	_wire(node, &"holster_requested", _on_officer_holster)
	_wire(node, &"weapon_cycle_requested", _on_officer_cycle)
	direct_input = wired == 0
	_adapters.prepare_officer(inventory)
	if not node.tree_exiting.is_connected(unbind_officer):
		node.tree_exiting.connect(unbind_officer)
	_ui_host = null
	if equipped != &"":
		_ensure_ui()


func unbind_officer() -> void:
	if officer != null and is_instance_valid(officer):
		for pair: Array in [[&"fire_requested", _on_officer_fire], [&"aim_changed", _on_officer_aim],
				[&"draw_requested", _on_officer_draw], [&"reload_requested", _on_officer_reload],
				[&"holster_requested", _on_officer_holster], [&"weapon_cycle_requested", _on_officer_cycle]]:
			var sig_name: StringName = pair[0]
			var callable: Callable = pair[1]
			if officer.has_signal(sig_name) and officer.is_connected(sig_name, callable):
				officer.disconnect(sig_name, callable)
		if officer.tree_exiting.is_connected(unbind_officer):
			officer.tree_exiting.disconnect(unbind_officer)
	var old := officer
	officer = null
	if _adapters != null:
		_adapters.release_officer(old)
		_adapters.officer = null
	direct_input = true
	_ui_host = null


func _wire(node: Node, sig_name: StringName, callable: Callable) -> int:
	if node.has_signal(sig_name) and not node.is_connected(sig_name, callable):
		node.connect(sig_name, callable)
		return 1
	return 0


func _on_officer_fire(_arg: Variant = null) -> void:
	fire()


func _on_officer_aim(on: Variant = true) -> void:
	set_aim(bool(on))


func _on_officer_draw(arg: Variant = null) -> void:
	if arg is String or arg is StringName:
		equip(arg)
	else:
		toggle_draw()


func _on_officer_reload(_arg: Variant = null) -> void:
	start_reload()


func _on_officer_holster(_arg: Variant = null) -> void:
	holster()


func _on_officer_cycle(direction: Variant = 1) -> void:
	cycle_weapon(int(direction))


# --- firing -----------------------------------------------------------------------------

func _shoot(scripted: Dictionary) -> bool:
	var def := _def()
	if def == null:
		return false
	var is_scripted := not scripted.is_empty()
	if state == State.RELOADING and def.tube_reload:
		_cancel_reload()
	if state != State.READY:
		return false
	var ignore_cooldown: bool = is_scripted and bool(scripted.get("ignore_cooldown", true))
	if not ignore_cooldown and time < _next_fire:
		return false
	var ammo: Dictionary = _ammo[equipped]
	if int(ammo["mag"]) <= 0:
		if time >= _next_dry:
			_next_dry = time + DRY_CLICK_GAP
			_audio.play(&"dry_click", -4.0)
			dry_fired.emit(equipped)
		return false

	ammo["mag"] = int(ammo["mag"]) - 1
	_next_fire = time + def.fire_interval
	var weapon_id := equipped

	var muzzle := _adapters.muzzle_position()
	var exclude := _adapters.exclude_rids()
	var space := _adapters.space_state()
	var camera_ray := {} if is_scripted else _adapters.center_ray()
	var base_dir := Vector3.FORWARD
	if is_scripted:
		var to_point: Vector3 = Vector3(scripted["point"]) - muzzle
		base_dir = to_point.normalized() if to_point.length() > 0.001 else Vector3.FORWARD
	elif not camera_ray.is_empty():
		base_dir = camera_ray["dir"]
	elif _adapters.has_officer() and officer is Node3D:
		base_dir = -(officer as Node3D).global_basis.z

	# Crosshair spread -> bullet cone (scripted shots are exact).
	var cone := 0.0
	if is_scripted:
		if def.pellets > 1:
			cone = _adapters.px_to_rad(def.spread_rest) * def.accuracy   # fixed pellet pattern, no randomness
	else:
		var spread: float = _crosshair.spread_px if _crosshair != null else def.spread_rest
		if not aiming:
			spread = maxf(spread, def.spread_move) # hip fire is sloppy. TODO(tahmin)
		cone = _adapters.px_to_rad(spread) * def.accuracy

	var hits := {}                                   # target Node -> accumulated hit data
	var first_end: Vector3 = muzzle + base_dir * def.max_range
	var impact_shown := 0
	var skip := _adapters.ray_skip()
	for i in def.pellets:
		var dir := base_dir
		if cone > 0.0:
			dir = _pellet_dir(base_dir, cone, i, def.pellets) if is_scripted else _cone_dir(base_dir, cone)
		var end_point: Vector3 = muzzle + dir * def.max_range
		var hit := {}
		if space != null:
			if not camera_ray.is_empty():
				# Aim point: first thing under the crosshair, then trace the bullet from the muzzle to it.
				var origin: Vector3 = Vector3(camera_ray["origin"]) + dir * skip
				var cam_hit := _cast(space, origin, Vector3(camera_ray["origin"]) + dir * def.max_range, exclude)
				var aim_point: Vector3 = cam_hit["position"] if not cam_hit.is_empty() \
						else Vector3(camera_ray["origin"]) + dir * def.max_range
				var bullet_dir := (aim_point - muzzle).normalized()
				hit = _cast(space, muzzle, muzzle + bullet_dir * (def.max_range + 5.0), exclude)
				end_point = hit["position"] if not hit.is_empty() else muzzle + bullet_dir * def.max_range
			else:
				hit = _cast(space, muzzle, end_point, exclude)
				if not hit.is_empty():
					end_point = hit["position"]
		if i == 0:
			first_end = end_point
		if hit.is_empty():
			continue
		var collider: Object = hit["collider"]
		var target := _adapters.target_from(collider)
		impact.emit(hit["position"], hit["normal"], collider)
		if impact_shown < 4:
			impact_shown += 1
			if impact_shown == 1:
				_audio.play(&"impact", -9.0)
			WeaponFx.impact(_adapters.fx_parent(), hit["position"], hit["normal"], target != null, fx_time_scale)
		if target != null:
			_accumulate(hits, target, collider, hit["position"], muzzle, def)

	# Scripted hit on a target that has no collider: count it so scenarios replay deterministically.
	var forced: Variant = scripted.get("target", null)
	if forced is Node and is_instance_valid(forced) and not hits.has(forced):
		var point: Vector3 = scripted["point"]
		_accumulate(hits, forced, null, point, muzzle, def, String(scripted.get("part", "torso")))
		first_end = point

	var shot_basis := _look_basis(base_dir)
	var muzzle_xform := Transform3D(shot_basis, muzzle)
	shot_fired.emit(muzzle, base_dir, weapon_id)

	# Effects, sound, camera.
	var parent := _adapters.fx_parent()
	_adapters.visual_fire(officer_recoil)
	WeaponFx.muzzle_flash(parent, muzzle_xform, def, fx_time_scale)
	WeaponFx.smoke(parent, muzzle_xform, def, fx_time_scale)
	if tracers_enabled and def.tracer:
		WeaponFx.tracer(parent, muzzle, first_end, fx_time_scale)
	if def.pump_time > 0.0:
		get_tree().create_timer(def.pump_time * fx_time_scale).timeout.connect(_on_pump.bind(weapon_id, muzzle_xform))
	elif casings_enabled:
		WeaponFx.casing(parent, muzzle_xform, def, officer, fx_time_scale)
	_audio.play(def.shot_sound, 0.0)
	if not (officer_recoil and _adapters.has_officer() and officer.has_method("notify_shot")):
		_add_kick(def)
	if _crosshair != null:
		_crosshair.on_shot(def.hide_after_shot)

	# Damage after the shot event so listeners see shot_fired first.
	var any_hit := false
	for target: Node in hits:
		var was_live := _adapters.is_live_target(target)
		if was_live or hit_marker_on_dead:
			any_hit = true
		var entry: Dictionary = hits[target]
		var best_part := _best_part(entry["parts"])
		var info := {"weapon": weapon_id, "damage": entry["damage"], "part": best_part, "point": entry["point"],
				"dir": base_dir, "distance": entry["distance"], "origin": muzzle}
		var result := {"downed": false, "lethal": false}
		if damage_enabled and was_live:                  # a downed target takes no further damage or reaction
			result = _adapters.apply_hit(target, info)
		target_hit.emit(target, entry["damage"], best_part)
		if result["downed"]:
			target_downed.emit(target, weapon_id, bool(result["lethal"]))
	if any_hit and _crosshair != null:
		_crosshair.show_hit_marker()
	_ammo_updated(weapon_id)
	return true


func _accumulate(hits: Dictionary, target: Node, collider: Object, point: Vector3, muzzle: Vector3,
		def: RefCounted, forced_part := "") -> void:
	var part := forced_part if collider == null else _adapters.hit_part(target, collider, point)
	var distance := muzzle.distance_to(point)
	var falloff := lerpf(1.0, def.falloff_min,
			clampf((distance - def.falloff_start) / maxf(def.falloff_end - def.falloff_start, 0.001), 0.0, 1.0))
	var damage: float = def.damage * falloff * float(PART_MULTIPLIER.get(part, 1.0))
	if not hits.has(target):
		hits[target] = {"damage": 0.0, "parts": {}, "point": point, "distance": distance}
	var entry: Dictionary = hits[target]
	entry["damage"] = float(entry["damage"]) + damage
	var parts: Dictionary = entry["parts"]
	parts[part] = float(parts.get(part, 0.0)) + damage


func _best_part(parts: Dictionary) -> String:
	var best := "torso"
	var best_damage := -1.0
	for part: String in parts:
		if float(parts[part]) > best_damage:
			best_damage = float(parts[part])
			best = part
	return best


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = exclude
	query.collide_with_areas = false
	return space.intersect_ray(query)


func _cone_dir(dir: Vector3, half_angle: float) -> Vector3:
	var angle := sqrt(randf()) * half_angle
	var phi := randf() * TAU
	var basis := _look_basis(dir)
	return (basis * Vector3(sin(angle) * cos(phi), sin(angle) * sin(phi), -cos(angle))).normalized()


## Deterministic pellet pattern (sunflower spiral) used by scripted shots.
func _pellet_dir(dir: Vector3, half_angle: float, index: int, count: int) -> Vector3:
	var angle := sqrt((float(index) + 0.5) / float(count)) * half_angle
	var phi := float(index) * 2.399963
	var basis := _look_basis(dir)
	return (basis * Vector3(sin(angle) * cos(phi), sin(angle) * sin(phi), -cos(angle))).normalized()


func _look_basis(dir: Vector3) -> Basis:
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	return Basis.looking_at(dir.normalized(), up)


func _on_pump(weapon_id: StringName, muzzle_xform: Transform3D) -> void:
	if equipped != weapon_id:
		return
	_audio.play(&"shotgun_pump", -3.0)
	_adapters.visual_pump(officer_recoil)
	if casings_enabled:
		WeaponFx.casing(_adapters.fx_parent(), muzzle_xform, _defs[weapon_id], officer, fx_time_scale)


func _add_kick(def: RefCounted) -> void:
	var current := _kick_value()
	var pitch := _adapters.px_to_rad(def.kick_px)
	var yaw := _adapters.px_to_rad(def.kick_yaw_px) * randf_range(-1.0, 1.0)
	_kick_pitch = minf(current.x + pitch, pitch * KICK_STACK_LIMIT)
	_kick_yaw = current.y + yaw
	_kick_age = 0.0
	_kick_duration = maxf(def.kick_time, 0.05)
	_apply_kick()


func _kick_value() -> Vector2:
	var k := clampf(1.0 - _kick_age / _kick_duration, 0.0, 1.0)
	k *= k
	return Vector2(_kick_pitch * k, _kick_yaw * k)


func _apply_kick() -> void:
	var value := _kick_value()
	_adapters.apply_camera_kick(value.x, value.y)


func _tick_kick(delta: float) -> void:
	if _kick_age >= _kick_duration and _kick_pitch == 0.0 and _kick_yaw == 0.0:
		return
	_kick_age += delta
	_apply_kick()
	if _kick_age >= _kick_duration:
		_kick_pitch = 0.0
		_kick_yaw = 0.0


# --- state machine -----------------------------------------------------------------------

func _def() -> RefCounted:
	return _defs.get(equipped, null)


func _resolve(weapon: Variant) -> StringName:
	if weapon is String or weapon is StringName:
		if String(weapon).is_empty():
			return equipped if equipped != &"" else selected
		return WeaponDef.resolve_id(weapon)
	return equipped if equipped != &"" else selected


func _set_state(value: State) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(int(value))


func _tick_state(delta: float) -> void:
	match state:
		State.DRAWING:
			_state_left -= delta
			if _state_left <= 0.0:
				_set_state(State.READY)
		State.HOLSTERING:
			_state_left -= delta
			if holster_hud_time >= 0.0 and not _hud_hidden:
				_hud_close_left -= delta
				if _hud_close_left <= 0.0:
					_hud_hidden = true                   # line closes on its own clock, not the animation length
					_push_hud()
			if _state_left <= 0.0:
				_finish_holster()
		State.RELOADING:
			_reload_left -= delta
			if _reload_left <= 0.0:
				_finish_reload_step()


func _finish_holster() -> void:
	_cancel_reload()
	equipped = &""
	_set_state(State.HOLSTERED)
	_refresh_aim()
	_push_hud()
	_hud_hidden = false
	equipped_changed.emit(&"")


func _cancel_reload() -> void:
	if state == State.RELOADING:
		_reload_left = 0.0
		_set_state(State.READY)


func _finish_reload_step() -> void:
	var def := _def()
	var ammo: Dictionary = _ammo[equipped]
	var id := equipped
	if def.tube_reload:
		ammo["mag"] = int(ammo["mag"]) + 1
		ammo["reserve"] = int(ammo["reserve"]) - 1
		_audio.play(def.reload_sound, -2.0)
		_ammo_updated(id)
		if int(ammo["mag"]) < def.mag_size and int(ammo["reserve"]) > 0:
			_reload_left = def.reload_time
			return
	else:
		var take := mini(def.mag_size - int(ammo["mag"]), int(ammo["reserve"]))
		ammo["mag"] = int(ammo["mag"]) + take
		ammo["reserve"] = int(ammo["reserve"]) - take
		_ammo_updated(id)
	_set_state(State.READY)
	reload_finished.emit(id)


func _ammo_updated(id: StringName) -> void:
	var ammo: Dictionary = _ammo[id]
	ammo_changed.emit(id, int(ammo["mag"]), int(ammo["reserve"]))
	if id == equipped:
		_push_hud()


# --- aim / crosshair / HUD -----------------------------------------------------------------

func _refresh_aim() -> void:
	var want := _aim_wanted and equipped != &"" and state != State.HOLSTERING and state != State.HOLSTERED
	if want != aiming:
		aiming = want
		aim_changed.emit(aiming)
	if _crosshair != null and is_instance_valid(_crosshair):
		var bars_on := aiming and state != State.DRAWING
		var def := _def()
		if bars_on and not _crosshair.active and def != null:
			_crosshair.set_active(true, def.spread_aim_in)
		elif not bars_on and _crosshair.active:
			_crosshair.set_active(false)


func _ensure_ui() -> void:
	var host_node: Node = _adapters.viewport()
	if _crosshair == null or not is_instance_valid(_crosshair):
		_crosshair = (load(CROSSHAIR_SCENE) as PackedScene).instantiate()
		_crosshair.manual = manual_tick
		_ui_host = null
	if _ui_host != host_node:
		_ui_host = host_node
		_attach_ui.call_deferred()


## Deferred and idempotent: the host may still be setting up its children when equip() is called from a _ready().
func _attach_ui() -> void:
	if _crosshair == null or not is_instance_valid(_crosshair) or _ui_host == null or not is_instance_valid(_ui_host):
		return
	var parent := _crosshair.get_parent()
	if parent == _ui_host:
		return
	if parent != null:
		parent.remove_child(_crosshair)
	_ui_host.add_child(_crosshair)


func _configure_crosshair() -> void:
	var def := _def()
	if _crosshair != null and def != null:
		_crosshair.configure(def.spread_rest, def.spread_move, def.spread_shot)


func _tick_crosshair_target() -> void:
	if _crosshair == null or not is_instance_valid(_crosshair):
		return
	var on_target := false
	if aiming:
		var ray := _adapters.center_ray()
		var space := _adapters.space_state()
		if not ray.is_empty() and space != null:
			var skip := _adapters.ray_skip()
			var origin: Vector3 = Vector3(ray["origin"]) + Vector3(ray["dir"]) * skip
			var hit := _cast(space, origin, Vector3(ray["origin"]) + Vector3(ray["dir"]) * 150.0, _adapters.exclude_rids())
			if not hit.is_empty():
				var target := _adapters.target_from(hit["collider"])
				on_target = target != null and _adapters.is_live_target(target)
	_crosshair.set_on_target(on_target)


func _tick_movement(delta: float) -> void:
	if _crosshair == null or not is_instance_valid(_crosshair):
		return
	if time < _ext_move_until:
		_crosshair.set_movement(_ext_move)
		return
	var cam := _adapters.camera()
	if cam == null or delta <= 0.0:
		return
	var origin := cam.global_position
	var forward := -cam.global_basis.z
	var factor := 0.0
	if _have_last_cam:
		var speed := (origin - _last_cam_origin).length() / delta
		var turn := rad_to_deg(_last_cam_forward.angle_to(forward)) / delta
		factor = clampf(maxf(speed / 2.5, turn / 120.0), 0.0, 1.0)
	_last_cam_origin = origin
	_last_cam_forward = forward
	_have_last_cam = true
	_crosshair.set_movement(factor)


func _tick_zoom(delta: float) -> void:
	if has_officer() or not fallback_zoom:
		return
	var def := _def()
	var goal := 1.0 if aiming and def != null else 0.0
	if _zoom == goal and goal == 0.0:
		return
	_zoom = move_toward(_zoom, goal, delta / AIM_ZOOM_TIME)
	_adapters.apply_zoom(_zoom, def.aim_zoom if def != null else 1.6)


func _tick_hud() -> void:
	if equipped != &"" and _adapters.hud() != _hud_pushed and _adapters.hud() != null:
		_push_hud()


func _push_hud() -> void:
	var h := _adapters.hud()
	if h == null:
		return
	_hud_pushed = h
	if equipped == &"" or _hud_hidden:
		if h.has_method("clear_weapon_line"):
			h.call("clear_weapon_line")
		return
	var def := _def()
	var ammo: Dictionary = _ammo[equipped]
	if h.has_method("set_weapon_line"):
		h.call("set_weapon_line", def.display_name, int(ammo["mag"]), int(ammo["reserve"]))


# --- direct input (placeholder player / no Officer) -----------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("weapon_next"):          # not part of the officer signal contract: always handled here
		cycle_weapon(1)
	elif event.is_action_pressed("weapon_prev"):
		cycle_weapon(-1)
	elif event.is_action_pressed("weapon_1"):
		_slot_key(&"pistol")
	elif event.is_action_pressed("weapon_2"):
		_slot_key(&"rifle")
	elif event.is_action_pressed("weapon_3"):
		_slot_key(&"shotgun")
	elif not direct_input or has_officer():
		return
	elif event.is_action_pressed("fire"):
		fire()
	elif event.is_action_pressed("draw_weapon"):
		toggle_draw()


func _tick_direct_input(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var aim_now := captured and Input.is_action_pressed("aim")
	if aim_now != _aim_input_prev:
		_aim_input_prev = aim_now
		set_aim(aim_now)
	var def := _def()
	if captured and def != null and def.automatic and Input.is_action_pressed("fire"):
		fire()
	if captured and Input.is_action_pressed("reload"):
		_reload_held += delta
		if _reload_held >= reload_hold_time and not _reload_triggered:
			_reload_triggered = true
			start_reload()
	else:
		_reload_held = 0.0
		_reload_triggered = false
