extends RefCounted
## Adapter layer between Weapons and the modules it touches (Officer, Npc, HUD, camera). Everything is looked up by
## duck typing so the weapon module works before docs/api/characters.md exists; when the real APIs land only this
## file changes. Expected optional Officer members are listed in docs/api/weapons.md.

const TargetHealth := preload("res://scripts/weapons/target_health.gd")

const DEFAULT_HEIGHT := 1.75
const HEAD_FROM := 0.86       ## hit height / body height above which a hit counts as head
const LEGS_UNTIL := 0.45      ## ... and below which it counts as legs
const HUD_RETRY_MSEC := 1000

var host: Node                ## the Weapons autoload (tree access)
var officer: Node
var hud_override: Node
var viewport_override: Viewport
var fallback_muzzle_offset := Vector3(0.3, -0.3, -3.7)   ## camera space; used when no officer provides a muzzle
var fallback_ray_skip := 3.6  ## metres of the camera ray ignored without an officer (the placeholder body is in front)

var _hud: Node
var _hud_search_msec := -100000
var _kick_camera: Camera3D
var _kick_pitch := 0.0
var _kick_yaw := 0.0
var _zoom_camera: Camera3D
var _base_fov := 75.0
var _zoom_applied := false


# --- officer / camera -------------------------------------------------------------

func has_officer() -> bool:
	return officer != null and is_instance_valid(officer)


func viewport() -> Viewport:
	if viewport_override != null and is_instance_valid(viewport_override):
		return viewport_override
	if has_officer() and officer.is_inside_tree():
		return officer.get_viewport()
	return host.get_viewport()


func camera() -> Camera3D:
	if has_officer():
		if officer.has_method("get_aim_camera"):
			var cam := officer.call("get_aim_camera") as Camera3D
			if cam != null:
				return cam
		var prop: Variant = officer.get("camera")
		if prop is Camera3D:
			return prop
	return viewport().get_camera_3d()


func space_state() -> PhysicsDirectSpaceState3D:
	var cam := camera()
	if cam != null:
		return cam.get_world_3d().direct_space_state
	if has_officer() and officer is Node3D:
		return (officer as Node3D).get_world_3d().direct_space_state
	return null


## Screen-centre camera ray {"origin", "dir"} or {} when there is no camera.
func center_ray() -> Dictionary:
	var cam := camera()
	if cam == null:
		return {}
	var center := cam.get_viewport().get_visible_rect().size * 0.5
	return {"origin": cam.project_ray_origin(center), "dir": cam.project_ray_normal(center)}


func ray_skip() -> float:
	return 0.0 if has_officer() else fallback_ray_skip


func exclude_rids() -> Array[RID]:
	var rids: Array[RID] = []
	if has_officer():
		if officer.has_method("get_collision_rids"):
			for rid: RID in officer.call("get_collision_rids"):
				rids.append(rid)
		elif officer is CollisionObject3D:
			rids.append((officer as CollisionObject3D).get_rid())
	return rids


## World position bullets and effects start from. Priority: officer.get_muzzle_transform(), a "Muzzle" child,
## the officer body, then a camera-relative guess (placeholder player without an Officer).
func muzzle_position() -> Vector3:
	if has_officer():
		if officer.has_method("get_muzzle_transform"):
			return (officer.call("get_muzzle_transform") as Transform3D).origin
		if officer.has_method("muzzle_transform") and officer.has_method("draw_weapon"):
			var rig_node := rig()
			if rig_node != null and String(rig_node.get("weapon")) != "":
				return (officer.call("muzzle_transform") as Transform3D).origin   # Officer: tip of the weapon in hand
		var muzzle := officer.get_node_or_null("Muzzle") as Node3D
		if muzzle != null:
			return muzzle.global_position
		var prop: Variant = officer.get("muzzle")
		if prop is Node3D:
			return (prop as Node3D).global_position
		if officer is Node3D:
			var body := officer as Node3D
			var ray := center_ray()
			var forward := Vector3(ray.get("dir", -body.global_basis.z)) * Vector3(1, 0, 1)
			forward = forward.normalized() if forward.length() > 0.01 else -body.global_basis.z
			return body.global_position + Vector3.UP * 1.4 + forward * 0.6 + forward.cross(Vector3.UP) * 0.25
	var cam := camera()
	if cam != null:
		return cam.global_transform * fallback_muzzle_offset
	return Vector3.ZERO


func officer_velocity() -> Vector3:
	if has_officer():
		var v: Variant = officer.get("velocity")
		if v is Vector3:
			return v
	return Vector3.ZERO


## Parent for 3D effects (same World3D as the officer / camera).
func fx_parent() -> Node:
	if has_officer() and officer.is_inside_tree() and officer.get_parent() != null:
		return officer.get_parent()
	var scene := host.get_tree().current_scene
	if scene != null:
		return scene
	return viewport()


# --- HUD ----------------------------------------------------------------------------

## The HUD node (anything with set_weapon_line); group "hud" first, then a breadth-first search, cached.
func hud() -> Node:
	if hud_override != null and is_instance_valid(hud_override):
		return hud_override
	if _hud != null and is_instance_valid(_hud):
		return _hud
	var now := Time.get_ticks_msec()
	if now - _hud_search_msec < HUD_RETRY_MSEC:
		return null
	_hud_search_msec = now
	var tree := host.get_tree()
	var grouped := tree.get_first_node_in_group("hud")
	if grouped != null and grouped.has_method("set_weapon_line"):
		_hud = grouped
		return _hud
	var queue: Array[Node] = [tree.root]
	var guard := 0
	while not queue.is_empty() and guard < 4000:
		var node: Node = queue.pop_front()
		guard += 1
		if node.has_method("set_weapon_line") and node.has_method("clear_weapon_line"):
			_hud = node
			return _hud
		queue.append_array(node.get_children())
	return null


# --- targets ------------------------------------------------------------------------

## Walks up from a collider to the node that represents a shootable target (NPC root), or null.
func target_from(collider: Object) -> Node:
	var node := collider as Node
	while node != null:
		if _is_target(node):
			return node
		node = node.get_parent()
	return null


func _is_target(node: Node) -> bool:
	return node.is_in_group("npc") or node.is_in_group("shootable") \
			or node.has_method("apply_weapon_hit") or node.has_method("take_damage") \
			or (node.has_method("go_down") and node.has_method("flee_from"))     # characters/npc.gd


## True while the target can still be hurt (the crosshair turns red only on live targets).
func is_live_target(target: Node) -> bool:
	if target.has_method("is_downed"):
		return not bool(target.call("is_downed"))
	var npc_state: Variant = target.get("state")
	if npc_state is StringName and (npc_state == &"downed" or npc_state == &"cuffed"):
		return false
	var health := target.get_node_or_null("WeaponHealth")
	if health != null:
		return not bool(health.get("is_downed"))
	return true


func target_height(target: Node) -> float:
	var h: Variant = target.get("height")
	if h is float or h is int:
		return float(h)
	if target.has_meta("height"):
		return float(target.get_meta("height"))
	var scale_factor: Variant = target.get("height_scale")
	if scale_factor is float:
		return 1.8 * float(scale_factor)               # characters/npc.gd capsule is 1.8 m
	return DEFAULT_HEIGHT


func hit_part(target: Node, collider: Object, point: Vector3) -> String:
	var hitbox := collider as Node
	if hitbox != null:
		var label := String(hitbox.name).to_lower()
		if "head" in label:
			return "head"
		if "arm" in label or "hand" in label:
			return "arms"
		if "leg" in label or "foot" in label or "thigh" in label:
			return "legs"
		if "torso" in label or "chest" in label:
			return "torso"
	if target is Node3D:
		var rel := (point.y - (target as Node3D).global_position.y) / target_height(target)
		if rel > HEAD_FROM:
			return "head"
		if rel < LEGS_UNTIL:
			return "legs"
	return "torso"


func aim_point(target: Variant, part: String) -> Vector3:
	var node := target as Node
	if node == null:
		return Vector3.ZERO
	if node.has_method("get_aim_point"):
		return node.call("get_aim_point", part)
	var node3d := node as Node3D
	if node3d == null:
		return Vector3.ZERO
	var factor := 0.68
	match part:
		"head":
			factor = 0.93
		"legs":
			factor = 0.25
	return node3d.global_position + Vector3.UP * target_height(node) * factor


## Delivers one hit. `info`: weapon, damage, part, point, dir, distance. Returns {"downed", "lethal", "hp"}.
## Order: target.apply_weapon_hit(info) -> target.take_damage(damage, part, info) -> built-in WeaponHealth.
## TODO(characters): bind to docs/api/characters.md once Npc exists (state names idle/walk/flee/surrender/downed/cuffed).
func apply_hit(target: Node, info: Dictionary) -> Dictionary:
	var result := {"downed": false, "lethal": false, "hp": -1.0}
	if target.has_method("apply_weapon_hit"):
		var reply: Variant = target.call("apply_weapon_hit", info)
		if reply is Dictionary:
			result.merge(reply, true)
		return result
	if target.has_method("take_damage"):
		var reply2: Variant = target.call("take_damage", info["damage"], info["part"], info)
		if reply2 is Dictionary:
			result.merge(reply2, true)
		elif reply2 is bool:
			result["downed"] = reply2
			result["lethal"] = reply2
		return result
	var health := _health_for(target)
	result.merge(health.take(float(info["damage"]), String(info["part"])), true)
	if target.has_method("react_to_shot"):
		target.call("react_to_shot", info, result)
	if result["downed"]:
		if target.has_method("go_down"):
			target.call("go_down", &"shot")                         # characters/npc.gd: death fall, state downed
		elif target.has_method("set_state"):
			target.call("set_state", &"downed")
	elif target.has_method("flee_from") and target.get("state") != &"flee":
		target.call("flee_from", info.get("origin", Vector3.ZERO))  # the first hit did not stop the runner
	return result


func _health_for(target: Node) -> Node:
	var health := target.get_node_or_null("WeaponHealth")
	if health == null:
		health = TargetHealth.new()
		health.name = "WeaponHealth"
		target.add_child(health)
	return health


# --- officer visuals (characters/officer.gd; every call is skipped when the officer lacks it) ----------------------------

const HOLSTER_ANIM := {&"pistol": "holster", &"rifle": "sling", &"shotgun": "sling"}

var _officer_visuals_off := false


func rig() -> Node:
	if has_officer():
		var r: Variant = officer.get("rig")
		if r is Node:
			return r
	return null


## Called when an officer is bound: Weapons drives the stance, so the officer's own auto reactions are switched off.
func prepare_officer(weapon_ids: Array) -> void:
	if not has_officer():
		return
	if "auto_visuals" in officer and bool(officer.get("auto_visuals")):
		officer.set("auto_visuals", false)
		_officer_visuals_off = true
	if officer.has_method("set_loadout"):
		officer.call("set_loadout", weapon_ids)


func release_officer(old: Node) -> void:
	if _officer_visuals_off and old != null and is_instance_valid(old):
		old.set("auto_visuals", true)
	_officer_visuals_off = false


func _anim_seconds(anim_name: String, fallback: float) -> float:
	var r := rig()
	if r == null or not r.has_method("anim_length"):
		return fallback
	var length := float(r.call("anim_length", StringName(anim_name)))
	return length if length > 0.0 else fallback


func draw_time(id: StringName, fallback: float) -> float:
	var total := _anim_seconds("%s_draw" % id, fallback)
	var r := rig()
	if r != null and String(r.get("weapon_state")) in ["ready", "aiming", "raising", "lowering"] and r.get("weapon") != id:
		total += holster_time(StringName(r.get("weapon")), 0.0)   # switching: lower the old one first
	return total


func holster_time(id: StringName, fallback: float) -> float:
	return _anim_seconds("%s_%s" % [id, HOLSTER_ANIM.get(id, "holster")], fallback)


func reload_time(id: StringName, fallback: float) -> float:
	return _anim_seconds("%s_reload" % id, fallback)


func visual_draw(id: StringName) -> void:
	var r := rig()
	if r == null or not officer.has_method("draw_weapon"):
		return
	var state := String(r.get("weapon_state"))
	if state == "unarmed":
		officer.call("draw_weapon", id)
	elif r.get("weapon") != id and officer.has_method("holster_weapon"):
		officer.call("holster_weapon")                               # switch: holster first, draw when unarmed
		r.connect("weapon_state_changed", func(new_state: StringName) -> void:
			if new_state == &"unarmed" and has_officer():
				officer.call("draw_weapon", id), CONNECT_ONE_SHOT)


func visual_holster() -> void:
	if has_officer() and officer.has_method("holster_weapon"):
		officer.call("holster_weapon")


## Recoil animation. With `use_officer_recoil` the officer's own notify_shot() (animation + measured camera kick + shotgun
## pump) runs instead; otherwise only the animation plays and Weapons applies its own kick.
func visual_fire(use_officer_recoil := false) -> void:
	if use_officer_recoil and has_officer() and officer.has_method("notify_shot"):
		officer.call("notify_shot")
		return
	var r := rig()
	if r != null and r.has_method("fire"):
		r.call("fire")


func visual_reload() -> void:
	var r := rig()
	if r != null and r.has_method("reload"):
		r.call("reload")


func visual_pump(use_officer_recoil := false) -> void:
	var r := rig()
	if not use_officer_recoil and r != null and r.has_method("pump"):
		r.call("pump")


# --- camera effects -----------------------------------------------------------------

## Absolute camera kick offset in radians (pitch up, yaw). The officer handles it when it has set_camera_kick().
func apply_camera_kick(pitch: float, yaw: float) -> void:
	if has_officer() and officer.has_method("set_camera_kick"):
		officer.call("set_camera_kick", pitch, yaw)
		return
	var cam := camera()
	if cam == null:
		return
	if cam != _kick_camera:
		_kick_camera = cam
		_kick_pitch = 0.0
		_kick_yaw = 0.0
	cam.rotation.x += pitch - _kick_pitch
	cam.rotation.y += yaw - _kick_yaw
	_kick_pitch = pitch
	_kick_yaw = yaw


## Aim zoom for setups where nothing else zooms the camera (no officer): narrows the FOV so objects look `zoom` times closer.
func apply_zoom(amount: float, zoom: float) -> void:
	var cam := camera()
	if cam == null:
		return
	if cam != _zoom_camera:
		_zoom_camera = cam
		_zoom_applied = false
		_base_fov = cam.fov
	if amount <= 0.0:
		if _zoom_applied:
			cam.fov = _base_fov
			_zoom_applied = false
		else:
			_base_fov = cam.fov
		return
	if not _zoom_applied:
		_base_fov = cam.fov
		_zoom_applied = true
	var factor := lerpf(1.0, zoom, amount)
	cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(_base_fov) * 0.5) / factor))


## Vertical image shift in pixels (at 1080p) -> camera angle in radians for the current FOV.
func px_to_rad(px: float) -> float:
	var cam := camera()
	var fov := cam.fov if cam != null else 75.0
	var focal := 540.0 / tan(deg_to_rad(fov) * 0.5)
	return atan(px / focal)
