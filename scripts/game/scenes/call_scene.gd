extends RefCounted
## Base of the call scenes (scripts/game/scenes/*): what stands at the place of a call. The director creates a scene when a
## call is accepted; the scene puts its actors (cars, people) into the world when the player is close, reacts to the player
## and to the traffic stop / pursuit modules, and ends with finish(&"cleared" | &"cancelled"). Actors are removed in cleanup().

signal resolved(outcome: StringName)

const SPAWN_RADIUS := 230.0      # m: the actors appear when the player is this close (out of sight, the ring Traffic uses)

var director: Node               ## call_director.gd
var call: Dictionary
var origin := Vector3.ZERO       ## ground point on the road centre line
var edge: Dictionary = {}        ## road graph edge of the call
var edge_s := 0.0                ## metres along the edge
var spawned := false
var arrived := false             ## the player is on scene (10-97)
var done := false
var age := 0.0
var actors: Array[Node] = []
var kind: StringName = &"scene"

var _links: Array = []           # [signal, callable] connections removed in cleanup()


func setup(owner_director: Node, call_data: Dictionary, location: Dictionary) -> void:
	director = owner_director
	call = call_data
	origin = location["pos"]
	edge = location.get("edge", {})
	edge_s = float(location.get("s", 0.0))


func tick(dt: float) -> void:
	age += dt
	if done:
		return
	if not spawned:
		if director.player_distance(origin) <= SPAWN_RADIUS:
			spawned = true
			spawn()
		return
	update(dt)


## Puts the actors into the world.
func spawn() -> void:
	pass


func update(_dt: float) -> void:
	pass


## Calls reported 10-97 (the player is within 25 m of the call position).
func on_arrive() -> void:
	arrived = true


## R tapped on foot (order to drop the weapon) and E pressed on foot: scenes that use them return true when they took the key.
func on_order() -> bool:
	return false


func on_interact() -> bool:
	return false


func finish(outcome: StringName) -> void:
	if done:
		return
	done = true
	resolved.emit(outcome)


## Drops the signal links and hands the actors to the director, which removes them when the player is out of sight.
func cleanup() -> void:
	for entry: Array in _links:
		var sig: Signal = entry[0]
		if sig.is_connected(entry[1]):
			sig.disconnect(entry[1])
	_links.clear()
	for actor in actors:
		director.retire(actor)   # removed once the player is away from it
	actors.clear()


func link(sig: Signal, callable: Callable) -> void:
	sig.connect(callable)
	_links.append([sig, callable])


func track(node: Node) -> Node:
	actors.append(node)
	return node


## Ground point at the side of the road, `side` metres from the centre line (+ right of the travel direction a -> b).
func roadside(side: float) -> Vector3:
	if edge.is_empty():
		return origin
	var p: Dictionary = World.road_graph.point_on_edge(edge, edge_s)
	var dir: Vector3 = p["dir"]
	var right := -Vector3.UP.cross(dir)
	return (p["pos"] as Vector3) + right * side


func edge_dir() -> Vector3:
	if edge.is_empty():
		return Vector3.FORWARD
	return World.road_graph.point_on_edge(edge, edge_s)["dir"]


## Spawns a character from scenes/characters/npc.tscn and tracks it.
func spawn_npc(pos: Vector3, outfit: StringName, yaw := 0.0, kind_name := "civilian") -> Node3D:
	var packed := load("res://scenes/characters/npc.tscn") as PackedScene
	var npc := packed.instantiate() as Node3D
	npc.set("outfit", outfit)
	npc.set("model_kind", kind_name)
	director.world_parent().add_child(npc)
	npc.global_position = pos + Vector3(0.0, 0.3, 0.0)
	npc.rotation.y = yaw
	npc.add_to_group("npc")
	track(npc)
	return npc
