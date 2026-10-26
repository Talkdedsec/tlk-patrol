extends RefCounted
## Adapter layer between Calls / TrafficStop / Mdt and modules owned by other sessions (HUD, vehicles, characters,
## world, traffic, pursuit). Everything is looked up dynamically against docs/api/{vehicles,characters,hud,world}.md and the
## pursuit/traffic sources, and degrades to placeholders so the stop flow also runs on the dev stage.
##
## Conventions (same as the pursuit module): the officer node is in group "player" (or "officer", or is an `Officer`);
## the vehicle the officer drives is in group "player_vehicle"; the HUD is found by method (show_toast / set_emergency).
## Officer glue that does not exist yet (enter/exit the car) is done here with the Vehicle API (set_driver, enter_transform,
## open_driver_door); an Officer that offers exit_vehicle()/enter_vehicle(v)/is_in_vehicle() takes precedence.

const PlaceholderNpc := preload("res://scripts/traffic_stop/placeholder_npc.gd")

const NPC_SCENE := "res://scenes/characters/npc.tscn"
const OUTFITS: Array[StringName] = [&"purple_sweater", &"red_shirt_blue_shorts", &"maroon_runner", &"orange_driver", &"white_shirt",
	&"green_hoodie", &"grey_tee_cap", &"yellow_top", &"teal_jacket", &"denim_plaid"]
const MPH := 0.44704

## Road graph used instead of World.road_graph (tests, scenarios): needs nearest_edge(pos) -> {edge {width}, dist, point}.
static var graph_override: Object = null

static var _hud: Node = null
static var _officer: Node3D = null
static var _officer_retry := 0


static func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func singleton(autoload_name: String) -> Node:
	return tree().root.get_node_or_null(autoload_name)


# --- HUD ------------------------------------------------------------------------------------------

static func hud(t: SceneTree) -> Node:
	if _hud != null and is_instance_valid(_hud):
		return _hud
	var grouped := t.get_first_node_in_group("hud")
	if grouped != null and grouped.has_method("show_toast"):
		_hud = grouped
		return _hud
	for layer in t.root.find_children("*", "CanvasLayer", true, false):
		if layer.has_method("set_emergency") and layer.has_method("set_weapon_line"):
			_hud = layer
			return _hud
	return null


static func hud_set_emergency(t: SceneTree, on: bool, overlay: CanvasLayer = null) -> void:
	var node := hud(t)
	if node != null:
		node.call("set_emergency", on)
	elif overlay != null:
		# No HUD in the scene (tests): the toast slot carries the same text.
		if on:
			overlay.call("toast_local", "EMERGENCY: all units responding", 4.0)
		else:
			overlay.call("clear_toast")


static func hud_set_mission(t: SceneTree, text: String) -> void:
	var node := hud(t)
	if node != null:
		node.call("set_mission", text)


## Shows a toast through the HUD's single toast slot. Returns false when there is no HUD (the overlay draws its own).
static func hud_toast(t: SceneTree, text: String, seconds: float) -> bool:
	var node := hud(t)
	if node != null and node.has_method("show_toast"):
		node.call("show_toast", text, seconds)
		return true
	return false


## Car-only HUD panels (RADAR/ALPR, ELS, gauges) are hidden while the officer is on foot.
static func hud_set_vehicle(t: SceneTree, on: bool) -> void:
	var node := hud(t)
	if node != null and node.has_method("set_vehicle_hud"):
		node.call("set_vehicle_hud", on)


static func hud_call_marker(t: SceneTree, position: Vector3) -> void:
	var node := hud(t)
	if node != null:
		var minimap: Variant = node.get("minimap")
		if minimap is Object and (minimap as Object).has_method("add_marker"):
			(minimap as Object).call("add_marker", position, &"call")


# --- officer and player vehicle -----------------------------------------------------------------------

static func player(t: SceneTree) -> Node3D:
	if _officer != null and is_instance_valid(_officer):
		return _officer
	for group in ["player", "officer"]:
		var node := t.get_first_node_in_group(group)
		if node is Node3D:
			_officer = node
			return _officer
	var now := Time.get_ticks_msec()
	if now < _officer_retry:
		return null
	_officer_retry = now + 1500  # the tree search is not repeated every frame
	var queue: Array[Node] = [t.root]
	var guard := 0
	while not queue.is_empty() and guard < 4000:
		var node: Node = queue.pop_front()
		guard += 1
		var script: Script = node.get_script()
		if node is Node3D and script != null and script.get_global_name() == &"Officer":
			_officer = node
			return _officer
		queue.append_array(node.get_children())
	return null


static func player_vehicle(t: SceneTree) -> Node3D:
	var node := t.get_first_node_in_group("player_vehicle")
	return node as Node3D


static func player_in_vehicle(t: SceneTree) -> bool:
	var who := player(t)
	if who == null:
		return player_vehicle(t) != null
	if who.has_method("is_in_vehicle"):
		return bool(who.call("is_in_vehicle"))
	var flag: Variant = who.get("in_vehicle")
	if typeof(flag) == TYPE_BOOL:
		return flag
	# A real Officer has no flag yet: hidden or sitting at the driver seat counts as in the car.
	var mine := player_vehicle(t)
	if mine != null and mine.has_method("seat_transform"):
		var seat: Transform3D = mine.call("seat_transform", &"driver")
		return not who.visible or who.global_position.distance_to(seat.origin) < 0.8
	return not who.visible


static func player_exit_vehicle(t: SceneTree) -> void:
	var who := player(t)
	var mine := player_vehicle(t)
	if who == null:
		return
	if who.has_method("exit_vehicle"):
		who.call("exit_vehicle")
		return
	if mine == null:
		return
	if mine.has_method("open_driver_door"):
		mine.call("open_driver_door")
	if mine.has_method("set_driver"):
		mine.call("set_driver", null)
	who.global_position = driver_door_position(mine)
	who.visible = true
	who.set("input_enabled", true)
	var cam: Variant = who.get("camera")
	if cam is Camera3D:
		(cam as Camera3D).make_current()
	if who.has_method("release_action"):
		who.call("release_action")


static func player_enter_vehicle(t: SceneTree, vehicle: Node3D) -> void:
	var who := player(t)
	if who == null or vehicle == null:
		return
	if who.has_method("enter_vehicle"):
		who.call("enter_vehicle", vehicle)
		return
	if vehicle.has_method("set_driver"):
		vehicle.call("set_driver", who)
	if vehicle.has_method("close_driver_door"):
		vehicle.call("close_driver_door")
	who.visible = false
	who.set("input_enabled", false)


## Flashlight on the officer (Officer/rig has set_flashlight in its rig; the stage player implements it directly).
static func player_flashlight(t: SceneTree, on: bool) -> void:
	var who := player(t)
	if who == null:
		return
	if who.has_method("set_flashlight"):
		who.call("set_flashlight", on)
		return
	var rig: Variant = who.get("rig")
	if rig is Object and (rig as Object).has_method("set_flashlight"):
		(rig as Object).call("set_flashlight", on)


# --- vehicles --------------------------------------------------------------------------------------------

static func all_vehicles(t: SceneTree) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var vehicles := t.root.get_node_or_null("Vehicles")
	if vehicles != null:
		var list: Variant = vehicles.get("all")
		if list is Array:
			for entry in list:
				if entry is Node3D and is_instance_valid(entry):
					found.append(entry)
	for group in ["vehicles", "traffic", "vehicle"]:
		for node in t.get_nodes_in_group(group):
			if node is Node3D and not found.has(node):
				found.append(node)
	return found


static func is_police(vehicle: Node) -> bool:
	var flag: Variant = vehicle.get("is_police")
	if typeof(flag) == TYPE_BOOL and flag:
		return true
	return vehicle.is_in_group("police") or vehicle.is_in_group("player_vehicle")


static func plate_of(vehicle: Node) -> String:
	var plate: Variant = vehicle.get("plate")
	if plate != null and String(plate) != "":
		return String(plate)
	return String(vehicle.get_meta("plate", ""))


static func model_of(vehicle: Node, fallback: String = "") -> String:
	for key in ["display_name", "model_name"]:
		var value: Variant = vehicle.get(key)
		if value != null and String(value) != "":
			return String(value)
	return String(vehicle.get_meta("model_name", fallback))


static func speed_ms(vehicle: Node) -> float:
	if vehicle.has_method("speed_ms"):
		return float(vehicle.call("speed_ms"))
	return speed_mph(vehicle) * MPH


static func speed_mph(vehicle: Node) -> float:
	if vehicle.has_method("speed_mph"):
		return float(vehicle.call("speed_mph"))
	if vehicle is RigidBody3D:
		return (vehicle as RigidBody3D).linear_velocity.length() / MPH
	return 0.0


static func forward(vehicle: Node3D) -> Vector3:
	return -vehicle.global_transform.basis.z


static func right(vehicle: Node3D) -> Vector3:
	return vehicle.global_transform.basis.x


## Drive inputs; steer_right is +1 = turn right (the Vehicle API uses the same sign).
static func drive(vehicle: Node, throttle: float, steer_right: float, brake: float) -> void:
	if vehicle.has_method("set_controls"):
		vehicle.call("set_controls", throttle, steer_right, brake)
		return
	if vehicle.has_method("set_throttle"):
		vehicle.call("set_throttle", throttle)
	if vehicle.has_method("set_steer"):
		vehicle.call("set_steer", steer_right)
	if vehicle.has_method("set_brake_pedal"):
		vehicle.call("set_brake_pedal", brake)


static func set_handbrake(vehicle: Node, on: bool) -> void:
	if vehicle.has_method("set_handbrake"):
		vehicle.call("set_handbrake", on)


## Vehicle of ambient traffic ahead of `from`: nearest in a cone, moving or not. Excludes `from` and police cars.
static func vehicle_ahead(t: SceneTree, from: Node3D, max_distance: float = 60.0, cone_degrees: float = 18.0) -> Node3D:
	var best: Node3D = null
	var best_distance := max_distance
	var fwd := forward(from)
	for candidate in all_vehicles(t):
		if candidate == from or is_police(candidate):
			continue
		var to := candidate.global_position - from.global_position
		var distance := to.length()
		if distance < 2.0 or distance > best_distance:
			continue
		to.y = 0.0
		if rad_to_deg(fwd.angle_to(to.normalized())) > cone_degrees:
			continue
		best = candidate
		best_distance = distance
	return best


## Traffic AI pulls the car over by itself (signals right, stops at the edge). Returns false for cars it does not manage.
static func traffic_pull_over(vehicle: Node3D) -> bool:
	var traffic := singleton("Traffic")
	if traffic != null and traffic.has_method("is_managed") and bool(traffic.call("is_managed", vehicle)):
		traffic.call("pull_over", vehicle)
		return true
	return false


## Hands a car to the stop (and back): traffic AI leaves it alone while the "stop_hold" meta is set.
static func hold_vehicle_ai(vehicle: Node, hold: bool) -> void:
	vehicle.set_meta("stop_hold", hold)
	if "ai_enabled" in vehicle:
		vehicle.set("ai_enabled", not hold)
	var traffic := singleton("Traffic")
	if traffic != null:
		var method := "hold_vehicle" if hold else "release_vehicle"
		if traffic.has_method(method):
			traffic.call(method, vehicle)


## Point beside the driver door (Vehicle.enter_transform(&"driver") when available).
static func driver_door_position(vehicle: Node3D) -> Vector3:
	if vehicle.has_method("enter_transform"):
		var xf: Transform3D = vehicle.call("enter_transform", &"driver")
		return xf.origin
	var marker := vehicle.get_node_or_null("DriverDoor") as Node3D
	if marker != null:
		return marker.global_position
	return vehicle.global_transform * Vector3(-1.5, 0.0, -0.3)


## Where the stopped driver stands after stepping out: beside the door, a little behind it.
static func driver_stand_position(vehicle: Node3D) -> Vector3:
	return driver_door_position(vehicle) + forward(vehicle) * -0.9


static func driver_seat_transform(vehicle: Node3D) -> Transform3D:
	if vehicle.has_method("seat_transform"):
		return vehicle.call("seat_transform", &"driver")
	return Transform3D(vehicle.global_transform.basis, vehicle.global_transform * Vector3(-0.4, 0.5, 0.2))


## Door of the patrol car for "E  Get in".
static func patrol_door_position(vehicle: Node3D) -> Vector3:
	return driver_door_position(vehicle)


static func open_driver_door(vehicle: Node, open: bool) -> void:
	var method := "open_driver_door" if open else "close_driver_door"
	if vehicle.has_method(method):
		vehicle.call(method)


# --- drivers (NPC) -------------------------------------------------------------------------------------------

## Creates the driver and seats it. Real Npc (scenes/characters/npc.tscn) when present, else a capsule placeholder.
static func spawn_driver(vehicle: Node3D, outfit: StringName = &"") -> Node3D:
	var npc: Node3D = null
	if ResourceLoader.exists(NPC_SCENE):
		var scene := load(NPC_SCENE) as PackedScene
		if scene != null:
			npc = scene.instantiate() as Node3D
	if npc == null:
		npc = PlaceholderNpc.new()
	if outfit == &"":
		outfit = OUTFITS[randi() % OUTFITS.size()]
	if "outfit" in npc:
		npc.set("outfit", outfit)
	vehicle.get_parent().add_child(npc)
	npc.add_to_group("npc")
	npc_sit(npc, vehicle)
	return npc


## Gets the NPC up and out: leaves the seat (physics and collisions back on, parented to the world again).
static func npc_stand(npc: Node3D, vehicle: Node3D = null) -> void:
	if vehicle != null and npc.get_parent() == vehicle:
		npc.reparent(vehicle.get_parent(), true)
	if npc.has_meta("seated_layers"):
		npc.set("collision_layer", int(npc.get_meta("seated_layers")))
		npc.set("collision_mask", int(npc.get_meta("seated_mask")))
		npc.remove_meta("seated_layers")
	npc.set_physics_process(true)
	if "velocity" in npc:
		npc.set("velocity", Vector3.ZERO)
	if npc.has_method("stand_up"):
		npc.call("stand_up")


## Seats the NPC at the driver seat: child of the vehicle (moves with it), no physics of its own while seated.
static func npc_sit(npc: Node3D, vehicle: Node3D) -> void:
	if "collision_layer" in npc and not npc.has_meta("seated_layers"):
		npc.set_meta("seated_layers", int(npc.get("collision_layer")))
		npc.set_meta("seated_mask", int(npc.get("collision_mask")))
		npc.set("collision_layer", 0)
		npc.set("collision_mask", 0)
	npc.set_physics_process(false)
	if npc.get_parent() != vehicle:
		npc.reparent(vehicle, true)
	npc.global_transform = driver_seat_transform(vehicle)
	if npc.has_method("sit"):
		npc.call("sit", true)


static func npc_walk(npc: Node3D, target: Vector3, speed: float = 1.6) -> void:
	if npc.has_method("walk_to"):
		npc.call("walk_to", target, speed)


static func npc_talk(npc: Node, animation: StringName = &"talk_a") -> void:
	if npc.has_method("talk"):
		npc.call("talk", animation)


static func npc_face(npc: Node3D, point: Vector3) -> void:
	var flat := Vector3(point.x, npc.global_position.y, point.z)
	if flat.distance_to(npc.global_position) > 0.05:
		npc.look_at(flat, Vector3.UP)
		npc.rotate_y(PI)


## Distance from the vehicle's centre to the right edge of the road it drives on (metres), -1 when no road is known.
## The edge comes from the road graph (nearest edge, half of its width); the sign follows the vehicle's own right side.
static func road_room_right(vehicle: Node3D) -> float:
	var graph: Object = graph_override
	if graph == null:
		var world := singleton("World")
		if world != null:
			var g: Variant = world.get("road_graph")
			if g is Object:
				graph = g
	if graph == null or not graph.has_method("nearest_edge"):
		return -1.0
	var near: Dictionary = graph.call("nearest_edge", vehicle.global_position)
	if near.is_empty():
		return -1.0
	var edge: Dictionary = near["edge"]
	var half := float(edge.get("width", 8.0)) * 0.5
	if float(near["dist"]) > half + 3.0:
		return -1.0  # not on that road (parking lot, field)
	var offset: Vector3 = vehicle.global_position - Vector3(near["point"])
	offset.y = 0.0
	var flat_right := right(vehicle)
	flat_right.y = 0.0
	return half - offset.dot(flat_right.normalized())


# --- misc world hooks ---------------------------------------------------------------------------------------------

## Area name used in radio lines ("traffic stop near the Southside").
static func district_name(t: SceneTree) -> String:
	var world := t.root.get_node_or_null("World")
	if world != null:
		var district: Variant = world.get("district")
		if district != null and String(district) != "":
			return String(district)
	return "the Southside"


static func street_name(t: SceneTree, position: Vector3) -> String:
	var world := t.root.get_node_or_null("World")
	if world != null and world.has_method("street_at"):
		var street: Variant = world.call("street_at", position)
		if street is Dictionary:
			return String((street as Dictionary).get("name", ""))
	return ""


## Traffic slow-down or closure around a point (flares, road closed). Returns true when the Traffic module took it.
## mode: &"slow", &"closed" or &"clear" (removes every zone).
static func traffic_zone(t: SceneTree, position: Vector3, radius: float, mode: StringName) -> bool:
	var traffic := t.root.get_node_or_null("Traffic")
	if traffic == null:
		return false
	if mode == &"clear":
		if traffic.has_method("clear_zones"):
			traffic.call("clear_zones")
			return true
		return false
	if traffic.has_method("set_zone"):
		traffic.call("set_zone", position, radius, mode)
		return true
	return false


## Interaction cursor: shows the mouse while a panel is open and restores the previous mode afterwards.
static var _cursor_stack: Array[int] = []


static func cursor_push() -> void:
	_cursor_stack.append(Input.mouse_mode)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


static func cursor_pop() -> void:
	if _cursor_stack.is_empty():
		return
	Input.mouse_mode = _cursor_stack.pop_back() as Input.MouseMode
