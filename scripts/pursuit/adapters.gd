extends RefCounted
## Adapter layer between the pursuit/traffic module and the other modules (vehicles, world, characters, HUD, ELS).
## Everything is looked up dynamically so a missing or renamed API degrades to a placeholder instead of a parse error.
## Conventions used by this module: steering commands are "positive = left"; adapters translate for the real Vehicle
## (steer -1 left .. +1 right). Real APIs verified against docs/api (when present) and the module sources.

const MPH := 0.44704
const FT := 0.3048
const PlaceholderVehicle := preload("res://scripts/pursuit/placeholder_vehicle.gd")
const PlaceholderNpc := preload("res://scripts/pursuit/placeholder_npc.gd")
const Signals := preload("res://scripts/traffic/signals.gd")

## Road graph used when World.road_graph is not available (set by the test scene).
static var fallback_graph: Object = null
## -1 = ask Els, 0 = lights off, 1 = lights on (scenarios / tests).
static var lights_override: int = -1
## Parent for spawned vehicles and NPCs (defaults to the current scene).
static var spawn_parent: Node = null
## Camera used for aiming / visibility checks when the root viewport has none (sub-viewport tests).
static var camera_override: Camera3D = null
static var force_placeholders := false

static var _hud: Node = null
static var _hud_retry := 0
static var _officer: Node3D = null
static var _officer_retry := 0


static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func singleton(autoload_name: String) -> Node:
	var t := tree()
	if t == null:
		return null
	return t.root.get_node_or_null(autoload_name)


# --- world -------------------------------------------------------------------------------------------------------

static func graph() -> Object:
	var w := singleton("World")
	if w != null:
		var g: Variant = w.get("road_graph")
		if g is Object and g != null:
			return g
	return fallback_graph


## {name, limit_mph, kind} at a position (World.street_at, else the nearest edge of the graph).
static func street_at(pos: Vector3) -> Dictionary:
	var w := singleton("World")
	if w != null and w.has_method("street_at"):
		var r: Variant = w.call("street_at", pos)
		if r is Dictionary and not (r as Dictionary).is_empty():
			var d: Dictionary = r
			var lim: Variant = d.get("speed_limit_mph", d.get("limit_mph", 25))
			return {"name": String(d.get("name", "")), "limit_mph": int(lim), "kind": String(d.get("kind", ""))}
	var g := graph()
	if g != null:
		var near: Dictionary = g.nearest_edge(pos)
		if not near.is_empty():
			var e: Dictionary = near.edge
			return {"name": String(e.name), "limit_mph": int(e.limit_mph), "kind": String(e.kind)}
	return {"name": "", "limit_mph": 25, "kind": ""}


static func signal_state(node_id: StringName, approach_dir: Vector3) -> StringName:
	var w := singleton("World")
	if w != null and w.has_method("traffic_light_state_for_heading"):
		var g: Variant = w.get("road_graph")
		if g != null:
			var r: Variant = w.call("traffic_light_state_for_heading", node_id, approach_dir)
			if r != null:
				return StringName(String(r))
	return Signals.state(node_id, approach_dir, float(Engine.get_physics_frames()) / 60.0)


# --- vehicles ----------------------------------------------------------------------------------------------------

static func _default_parent() -> Node:
	if spawn_parent != null and is_instance_valid(spawn_parent):
		return spawn_parent
	var t := tree()
	if t.current_scene != null:
		return t.current_scene
	return t.root


## Spawns a vehicle through Vehicles.spawn (real models) or a placeholder box car.
## options: plate (String), paint (Color), team (&"civil" / &"police" / &"suspect"), number (String painted on the roof).
static func spawn_vehicle(type_id: StringName, xform: Transform3D, options: Dictionary = {}) -> Node3D:
	var vs := singleton("Vehicles")
	var v: Node3D = null
	if not force_placeholders and vs != null and vs.has_method("spawn"):
		var known := true
		if vs.has_method("has_type"):
			known = bool(vs.call("has_type", type_id))
		if known:
			var opts := {}
			if options.has("plate"):
				opts["plate"] = options["plate"]
			if options.has("paint"):
				opts["paint"] = options["paint"]
			var parent: Node = options.get("parent", _default_parent())
			var res: Variant = vs.call("spawn", type_id, xform, parent, opts)
			if res is Node3D:
				v = res
	if v == null:
		var pv := PlaceholderVehicle.new()
		pv.type_id = type_id
		pv.plate = String(options.get("plate", ""))
		pv.team = StringName(options.get("team", &"civil"))
		pv.unit_number = String(options.get("number", ""))
		if options.has("paint"):
			pv.paint = options["paint"]
		var host: Node = options.get("parent", _default_parent())
		host.add_child(pv)
		pv.global_transform = xform
		v = pv
	return v


## Civilian car in a random colour (Vehicles.spawn_traffic) or a placeholder.
static func spawn_traffic_vehicle(xform: Transform3D) -> Node3D:
	var vs := singleton("Vehicles")
	if not force_placeholders and vs != null and vs.has_method("spawn_traffic"):
		var res: Variant = vs.call("spawn_traffic", xform, _default_parent())
		if res is Node3D:
			return res
	return spawn_vehicle(civilian_type(), xform, {"team": &"civil"})


static func set_velocity(v: Node3D, vel: Vector3) -> void:
	if v.get("linear_velocity") is Vector3:
		v.set("linear_velocity", vel)
	elif v.get("vel") is Vector3:
		v.set("vel", vel)


static func civilian_type() -> StringName:
	var vs := singleton("Vehicles")
	if not force_placeholders and vs != null and vs.has_method("random_traffic_type"):
		return StringName(vs.call("random_traffic_type"))
	var ids: Array[StringName] = [&"civ_sedan", &"civ_hatchback", &"civ_pickup", &"civ_van"]
	return ids[randi() % ids.size()]


static func is_placeholder(v: Node) -> bool:
	return v.get_script() == PlaceholderVehicle


static func speed_ms(v: Node3D) -> float:
	if v.has_method("speed_ms"):
		return float(v.call("speed_ms"))
	return velocity(v).length()


static func speed_mph(v: Node3D) -> float:
	return speed_ms(v) / MPH


static func velocity(v: Node3D) -> Vector3:
	var lv: Variant = v.get("linear_velocity")
	if lv is Vector3:
		return lv
	var pv: Variant = v.get("vel")
	if pv is Vector3:
		return pv
	return Vector3.ZERO


## Half width (x) and half length (y) in metres.
static func half_size(v: Node3D) -> Vector2:
	var e: Variant = v.get("extents")
	if e is Vector3:
		return Vector2(e.x, e.z)
	if v.has_meta("_half_size"):
		return v.get_meta("_half_size")
	var size := Vector2(1.0, 2.45)
	var model: Variant = v.get("model")
	if model is Node3D:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var inv := v.global_transform.affine_inverse()
		for mi in (model as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null or not m.visible or String(m.name).begins_with("ELS_"):
				continue
			var box := m.get_aabb()
			for i in 8:
				var p: Vector3 = inv * (m.global_transform * box.get_endpoint(i))
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		if lo.x < INF:
			size = Vector2(clampf(maxf(absf(lo.x), absf(hi.x)), 0.8, 1.3), clampf(maxf(absf(lo.y), absf(hi.y)), 2.0, 3.0))
			v.set_meta("_half_size", size)
	return size


## Drives a vehicle: throttle 0..1, brake 0..1, steering positive = left. `steer_target` (world point) lets vehicles
## with their own pure-pursuit steering (Vehicle.steer_towards) do the steering when it is not zero.
static func drive(v: Node3D, throttle: float, brake: float, steer_left: float, steer_target: Vector3 = Vector3.ZERO) -> void:
	if v.has_method("steer_towards") and steer_target != Vector3.ZERO:
		v.call("steer_towards", steer_target)
		v.call("set_throttle", throttle)
		v.call("set_brake_pedal", brake)
	elif v.has_method("set_controls"):
		v.call("set_controls", throttle, -steer_left, brake)
	elif v.has_method("set_brake_pedal"):
		v.call("set_throttle", throttle)
		v.call("set_steer", -steer_left)
		v.call("set_brake_pedal", brake)


static func teleport(v: Node3D, xform: Transform3D) -> void:
	if v.has_method("teleport"):
		v.call("teleport", xform)
	else:
		v.global_transform = xform


static func park(v: Node3D) -> void:
	drive(v, 0.0, 1.0, 0.0)
	if v.has_method("set_handbrake"):
		v.call("set_handbrake", true)


static func lights_on() -> bool:
	if lights_override >= 0:
		return lights_override == 1
	var e := singleton("Els")
	if e != null:
		if e.has_method("lights_active"):
			return bool(e.call("lights_active"))
		var lo: Variant = e.get("lights_on")
		if typeof(lo) == TYPE_BOOL:
			return lo
	return false


static func set_vehicle_lights(v: Node3D, on: bool) -> void:
	if v.has_method("set_headlights"):
		v.call("set_headlights", on)
	if v.has_method("set_emergency_lights"):
		v.call("set_emergency_lights", on)


## Rear-corner PIT contact: side -1 = left rear struck, +1 = right rear struck.
static func pit_push(v: Node3D, side: float, dv: float) -> void:
	if v.has_method("pit_push"):
		v.call("pit_push", side, dv)


static var _scuff_t: Dictionary = {}


## Contact visual/physics for one physics tick of PIT contact. A Vehicle.pit_scuff(side, seconds) (smoke + skid mark, no impulse)
## is used when the vehicle has one (throttled to every 0.25 s); otherwise a gentle pit_push shove when `allow_push`.
static func pit_contact(v: Node3D, side: float, dt: float, allow_push := true) -> void:
	if v.has_method("pit_scuff"):
		var id := v.get_instance_id()
		var left: float = float(_scuff_t.get(id, 0.0)) - dt
		if left <= 0.0:
			v.call("pit_scuff", side, 0.6)
			left = 0.25
		_scuff_t[id] = left
	elif allow_push:
		pit_push(v, side, 0.6 * dt)


static func pit_spin(v: Node3D, side: float, strength: float) -> void:
	if v.has_method("pit_spin"):
		v.call("pit_spin", side, strength)
	if v.has_method("start_smoke"):
		v.call("start_smoke", 14.0)


static func open_driver_door(v: Node3D) -> void:
	if v.has_method("open_driver_door"):
		v.call("open_driver_door")


static func driver_exit_transform(v: Node3D) -> Transform3D:
	if v.has_method("enter_transform"):
		var t: Transform3D = v.call("enter_transform", &"driver")
		t.origin += t.basis.z * 0.7   # basis -Z faces the car: step away from the door so nobody spawns inside the body
		return t
	var xf := v.global_transform
	xf.origin = v.global_transform * Vector3(-1.5, 0.0, -0.3)
	return xf


# --- player and characters ---------------------------------------------------------------------------------------

static func hud() -> Node:
	if _hud != null and is_instance_valid(_hud):
		return _hud
	var now := Time.get_ticks_msec()
	if now < _hud_retry:
		return null
	_hud_retry = now + 1000
	var t := tree()
	var grouped := t.get_first_node_in_group("hud")
	if grouped != null and grouped.has_method("show_toast"):
		_hud = grouped
		return _hud
	var queue: Array[Node] = [t.root]
	var guard := 0
	while not queue.is_empty() and guard < 3000:
		var node: Node = queue.pop_front()
		guard += 1
		if node.has_method("set_pursuit") and node.has_method("show_toast"):
			_hud = node
			return _hud
		queue.append_array(node.get_children())
	return null


static func officer() -> Node3D:
	if _officer != null and is_instance_valid(_officer):
		return _officer
	var t := tree()
	for group in ["player", "officer"]:
		var node := t.get_first_node_in_group(group)
		if node is Node3D:
			_officer = node
			return _officer
	var now := Time.get_ticks_msec()
	if now < _officer_retry:
		return null
	_officer_retry = now + 1500
	var queue: Array[Node] = [t.root]
	var guard := 0
	while not queue.is_empty() and guard < 3000:
		var node: Node = queue.pop_front()
		guard += 1
		var sc: Script = node.get_script()
		if node is Node3D and sc != null and sc.get_global_name() == &"Officer":
			_officer = node
			return _officer
		queue.append_array(node.get_children())
	return null


static func player_vehicle() -> Node3D:
	var node := tree().get_first_node_in_group("player_vehicle")
	return node as Node3D


static func in_vehicle(who: Node) -> bool:
	if who == null:
		return true
	if who.has_method("is_in_vehicle"):
		return bool(who.call("is_in_vehicle"))
	var iv: Variant = who.get("in_vehicle")
	if typeof(iv) == TYPE_BOOL:
		return iv
	return false


static func exit_vehicle(who: Node) -> void:
	if who != null and who.has_method("exit_vehicle"):
		who.call("exit_vehicle")


static func camera() -> Camera3D:
	if camera_override != null and is_instance_valid(camera_override):
		return camera_override
	return tree().root.get_viewport().get_camera_3d()


static func spawn_npc(xform: Transform3D, kind: String = "civilian", outfit: StringName = &"red_shirt") -> Node3D:
	var path := "res://scripts/characters/npc.gd"
	var npc: Node3D = null
	if not force_placeholders and ResourceLoader.exists(path):
		var sc: GDScript = load(path)
		var real: Node3D = sc.new()
		real.set("model_kind", kind)
		if kind == "civilian":
			real.set("outfit", outfit)
		_default_parent().add_child(real)
		npc = real
	if npc == null:
		var ph := PlaceholderNpc.new()
		ph.kind = kind
		_default_parent().add_child(ph)
		npc = ph
	npc.global_transform = xform
	npc.add_to_group("npc")
	return npc


static func npc_state(npc: Node) -> StringName:
	var st: Variant = npc.get("state")
	return StringName(st) if st != null else &""


## Focus point for spawning / culling: officer, else player vehicle, else the camera.
static func focus_position() -> Vector3:
	var o := officer()
	if o != null:
		return o.global_position
	var pv := player_vehicle()
	if pv != null:
		return pv.global_position
	var cam := camera()
	if cam != null:
		return cam.global_position
	return Vector3.ZERO
