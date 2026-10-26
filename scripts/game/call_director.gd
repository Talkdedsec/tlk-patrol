extends Node
## Call loop: offers calls that can be played (Calls.offer with a world position), builds the scene when the player accepts
## (scripts/game/scenes/*), points the minimap at the place, ends the call when the scene is resolved and clears the actors
## once the player has left. Call types with a scene: traffic stop (erratic driver), stolen vehicle (flees), armed robbery
## (suspect on foot, foot chase), and the talk calls (collision, trespassing, disturbance, suspicious person, noise, welfare, shoplifting).
## Calls.simulate_response is switched off: arrival is the player's distance (25 m) and the end is the scene's.

const SceneStop := preload("res://scripts/game/scenes/scene_stop.gd")
const SceneStolen := preload("res://scripts/game/scenes/scene_stolen.gd")
const SceneArmed := preload("res://scripts/game/scenes/scene_armed.gd")
const SceneTalk := preload("res://scripts/game/scenes/scene_talk.gd")
const TrafficRegistry := preload("res://scripts/traffic/registry.gd")

signal scene_started(kind: StringName)
signal scene_resolved(kind: StringName, outcome: StringName)

const MIN_DISTANCE := 260.0       # m from the player to the call
const MAX_DISTANCE := 650.0
const FIRST_KINDS: Array[StringName] = [&"traffic_stop", &"stolen_vehicle", &"armed_robbery", &"traffic_collision"]
const BAG: Array[StringName] = [&"traffic_stop", &"traffic_stop", &"stolen_vehicle", &"stolen_vehicle", &"armed_robbery",
	&"armed_robbery", &"traffic_collision", &"trespassing", &"disturbance", &"suspicious_person"]
const ASSIGN_TIMEOUT := 480.0     # s: an assigned call the player never reaches is given to another unit
const ABANDON_DISTANCE := 450.0   # m: the player is this far from a placed scene
const ABANDON_SECONDS := 90.0     # ...for this long (and nothing is running) and the call goes to another unit
const RETIRE_AFTER := 12.0        # s before a retired actor may be removed
const RETIRE_DISTANCE := 70.0     # m: ...and only when the player is this far from it
const DISTRICTS: Array[String] = ["the Southside", "Oak Hills", "Eastgate", "Davidson Blvd"]

var main: Node
var seat: Node
var hud
var enabled := true
var first_delay := 10.0
var interval := Vector2(70.0, 130.0)
var rng := RandomNumberGenerator.new()
var scene                          ## the scene of the assigned call (null when none)
var scene_call: Dictionary = {}
var completed := 0
var cancelled := 0

var _timer := 0.0
var _bag: Array[StringName] = []
var _first_index := 0
var _retired: Array = []          # [{node, age}]
var _retire_timer := 0.0
var _assigned_age := 0.0
var _abandoned_for := 0.0
var _skip_next := false


func _ready() -> void:
	rng.randomize()
	_timer = first_delay
	Calls.simulate_response = false
	Calls.auto_offers = false
	Calls.ambient_enabled = true
	Calls.call_started.connect(_on_call_started)
	Calls.call_ended.connect(_on_call_ended)
	Calls.offer_ended.connect(_on_offer_ended)


# --- helpers for the scenes ----------------------------------------------------------------------------------------

func world_parent() -> Node:
	return main


func player_pos() -> Vector3:
	return main.player.global_position


func player_distance(point: Vector3) -> float:
	var d := player_pos() - point
	d.y = 0.0
	return d.length()


func player_driving() -> bool:
	return seat != null and bool(seat.call("is_driving"))


## True when travelling along the edge from end a to b moves away from the player (so the player drives up behind).
func away_along_edge(edge: Dictionary, s: float) -> bool:
	var p: Dictionary = World.road_graph.point_on_edge(edge, s)
	var dir: Vector3 = p["dir"]
	var to_car: Vector3 = (p["pos"] as Vector3) - player_pos()
	to_car.y = 0.0
	return dir.dot(to_car) >= 0.0


func hint(text: String, seconds := 3.0) -> void:
	if hud != null:
		hud.show_toast(text, seconds)


func set_scene_prompt(text: String) -> void:
	if hud != null and hud.has_method("set_prompt_from"):
		hud.set_prompt_from(&"scene", text)


func speak_line(text: String) -> void:
	var voice: Variant = TrafficStop.get("dialog_voice")
	if voice is Node and (voice as Node).has_method("speak"):
		(voice as Node).call("speak", &"driver", text)


## Removes every retired actor now (a scripted scene that wants the street empty), except the ones the stop or pursuit still use.
func flush_retired() -> void:
	for i in range(_retired.size() - 1, -1, -1):
		var node: Node = _retired[i]["node"]
		if is_instance_valid(node) and not _in_use(node):
			if node is Node3D:
				TrafficRegistry.remove(node as Node3D)
				Traffic.release(node as Node3D)
			node.queue_free()
			_retired.remove_at(i)


## Actors of a finished scene stay until the player is out of sight, then they are removed.
func retire(node: Node) -> void:
	if node != null and is_instance_valid(node):
		_retired.append({"node": node, "age": 0.0})


# --- offering -------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if scene != null:
		scene.tick(delta)   # may resolve the scene (scene becomes null)
	if scene != null:
		var status: Variant = Calls.current.get("status", &"")
		if not scene.arrived and status == &"on_scene":
			scene.on_arrive()
		_assigned_age += delta
		if not scene.arrived and _assigned_age > ASSIGN_TIMEOUT and not scene.spawned:
			_timeout_call()
		if scene != null and scene.spawned and not Pursuit.is_active() and TrafficStop.state == TrafficStop.State.IDLE \
				and player_distance(scene.origin) > ABANDON_DISTANCE:
			_abandoned_for += delta
			if _abandoned_for > ABANDON_SECONDS:
				_abandoned_for = 0.0
				_timeout_call()
		else:
			_abandoned_for = 0.0
	elif enabled:
		_timer -= delta
		if _timer <= 0.0 and _can_offer():
			offer(_next_kind())
	_retire_timer -= delta
	if _retire_timer <= 0.0:
		_retire_timer = 1.0
		_sweep_retired(1.0)


func _can_offer() -> bool:
	return Calls.offer_call.is_empty() and Calls.current.is_empty() and not Pursuit.is_active() \
		and TrafficStop.state == TrafficStop.State.IDLE and main != null and main.player != null


func _next_kind() -> StringName:
	if _first_index < FIRST_KINDS.size():
		_first_index += 1
		return FIRST_KINDS[_first_index - 1]
	if _bag.is_empty():
		_bag = BAG.duplicate()
		_bag.shuffle()
	return _bag.pop_back()


## Offers a playable call of `kind` (a call type id). opts: position (Vector3 on the road: the place of the call),
## min_distance, max_distance; scene settings cruise_factor (speed of the stopped car, 1 = the limit), violation, flees, surrender_chance. Returns the call dictionary.
func offer(kind: StringName, opts: Dictionary = {}) -> Dictionary:
	var location := _pick_location(opts)
	var call := _make_call(kind, location)
	for key: String in ["cruise_factor", "violation", "flees", "surrender_chance"]:
		if opts.has(key):
			call[key] = opts[key]
	_timer = rng.randf_range(interval.x, interval.y)
	return Calls.offer(call)


func _make_call(kind: StringName, location: Dictionary) -> Dictionary:
	var extra := {"location": location["district"]}
	if kind == &"stolen_vehicle":
		var color: String = ["black", "white", "silver", "red", "blue", "green", "tan", "gray"][rng.randi() % 8]
		var model: String = ["Arden Compact", "Calloway Sedan", "Brightwater Pickup", "Kestrel Hatchback", "Tolland Coupe"][rng.randi() % 5]
		extra["text"] = "BOLO, %s %s, plate {plate}, last seen near {loc}. Occupant may flee." % [color, model]
		extra["color"] = color
		extra["model"] = model
	var call: Dictionary = Calls.make_call(kind, extra)
	for key: String in ["color", "model"]:
		if extra.has(key):
			call[key] = extra[key]
	call["position"] = location["pos"]
	call["street"] = location["street"]
	call["location_info"] = location
	call["playable"] = true
	return call


## A point on a street that is MIN_DISTANCE..MAX_DISTANCE from the player. {pos, edge, s, street, district}
func _pick_location(opts: Dictionary) -> Dictionary:
	var graph: RoadGraph = World.road_graph
	var origin := player_pos()
	if opts.has("position"):
		var near: Dictionary = graph.nearest_edge(opts["position"])
		return _location_from(near["edge"], float(near["t"]) * float(near["edge"]["length"]))
	var min_d: float = opts.get("min_distance", MIN_DISTANCE)
	var max_d: float = opts.get("max_distance", MAX_DISTANCE)
	for attempt in 60:
		var e: Dictionary = graph.edges[rng.randi() % graph.edges.size()]
		if not (String(e["kind"]) in ["residential", "arterial"]) or float(e["length"]) < 90.0:
			continue
		var s := rng.randf_range(30.0, float(e["length"]) - 30.0)
		var pos: Vector3 = graph.point_on_edge(e, s)["pos"]
		var d := Vector2(pos.x - origin.x, pos.z - origin.z).length()
		var slack := 1.0 + float(attempt) / 30.0
		if d >= min_d / slack and d <= max_d * slack:
			return _location_from(e, s)
	return _location_from(graph.edges[0], 40.0)


func _location_from(e: Dictionary, s: float) -> Dictionary:
	var pos: Vector3 = World.road_graph.point_on_edge(e, s)["pos"]
	var district := "the Southside"
	if String(e["name"]) == "Davidson Blvd":
		district = "Davidson Blvd"
	elif pos.x < -80.0:
		district = "Oak Hills"
	elif pos.x > 80.0:
		district = "Eastgate"
	return {"pos": pos, "edge": e, "s": s, "street": String(e["name"]), "district": district}


# --- call life cycle ------------------------------------------------------------------------------------------------

func _on_offer_ended(call: Dictionary, result: StringName) -> void:
	if not bool(call.get("playable", false)):
		return
	if result != &"responded":
		_timer = rng.randf_range(interval.x * 0.6, interval.y * 0.6)


func _on_call_started(call: Dictionary) -> void:
	if not bool(call.get("playable", false)) or scene != null:
		return
	var location: Dictionary = call["location_info"]
	var instance
	match StringName(call["type"]):
		&"traffic_stop":
			instance = SceneStop.new()
		&"stolen_vehicle":
			instance = SceneStolen.new()
		&"armed_robbery":
			instance = SceneArmed.new()
		_:
			instance = SceneTalk.new()
	instance.setup(self, call, location)
	instance.resolved.connect(_on_scene_resolved)
	scene = instance
	scene_call = call
	_assigned_age = 0.0
	if seat != null:
		seat.call("set_destination", location["pos"], location["street"])
	scene_started.emit(StringName(call["type"]))


func _on_scene_resolved(outcome: StringName) -> void:
	var kind: StringName = scene.kind if scene != null else &""
	if not Calls.current.is_empty() and Calls.current == scene_call:
		Calls.complete(outcome)
	_end_scene()
	if outcome == &"cleared":
		completed += 1
	else:
		cancelled += 1
	scene_resolved.emit(kind, outcome)


## Something else ended the call (scenarios): the scene goes with it.
func _on_call_ended(call: Dictionary, outcome: StringName) -> void:
	if scene != null and call == scene_call:
		if not scene.done:
			scene.done = true
		_end_scene()


func _end_scene() -> void:
	if scene == null:
		return
	if seat != null:
		seat.call("clear_destination")
	scene.cleanup()
	scene = null
	scene_call = {}
	_timer = rng.randf_range(interval.x, interval.y)


func _timeout_call() -> void:
	Calls.radio_dispatch("%s, we are sending another unit to the %s." % [Calls.unit_name, scene_call.get("noun", "call")])
	Calls.complete(&"cancelled")


# --- retired actors ------------------------------------------------------------------------------------------------------

func _sweep_retired(step: float) -> void:
	for i in range(_retired.size() - 1, -1, -1):
		var entry: Dictionary = _retired[i]
		var node: Node = entry["node"]
		if not is_instance_valid(node):
			_retired.remove_at(i)
			continue
		entry["age"] = float(entry["age"]) + step
		if float(entry["age"]) < RETIRE_AFTER or _in_use(node):
			continue
		if node is Node3D and player_distance((node as Node3D).global_position) < RETIRE_DISTANCE:
			continue
		_retired.remove_at(i)
		if node is Node3D:
			TrafficRegistry.remove(node as Node3D)   # the traffic drivers read this list: no freed entries
			Traffic.release(node as Node3D)
		node.queue_free()


## The stop and the pursuit still need these.
func _in_use(node: Node) -> bool:
	if node == TrafficStop.vehicle or node == TrafficStop.driver:
		return true
	if Pursuit.is_active() and (node == Pursuit.target or node == Pursuit.suspect):
		return true
	return false


# --- input ----------------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if scene == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.is_action("interact"):
		if scene.on_interact():
			get_viewport().set_input_as_handled()
	elif event.is_action("reload"):
		if scene.on_order():
			get_viewport().set_input_as_handled()
