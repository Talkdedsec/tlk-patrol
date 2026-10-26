extends Node
## Starts and holds together what runs the game beside the walk/drive loop: ambient traffic, the call director (offers and
## scenes), the RADAR / ALPR feed and the pursuit chain. Every module call goes through has_method / get on the autoload node, so a
## module that is missing or renamed only switches its hook off. Where each hook is wired: docs/api/game.md.

const CallDirector := preload("res://scripts/game/call_director.gd")
const RadarFeed := preload("res://scripts/game/radar_feed.gd")
const DutyFlow := preload("res://scripts/game/duty_flow.gd")
const TrafficRecycler := preload("res://scripts/game/traffic_recycler.gd")
const TrafficRegistry := preload("res://scripts/traffic/registry.gd")

var main: Node
var patrol: Vehicle
var seat: Node
var hud
var traffic_count := 14
var director: Node               ## CallDirector
var radar: Node                  ## RadarFeed
var duty: Node                   ## DutyFlow
var recycler: Node               ## TrafficRecycler: far ambient cars are moved around the player instead of freed and rebuilt
var recycle_traffic := true
## Plate reader scanning (scenarios switch it off).
var alpr_enabled := true:
	set(value):
		alpr_enabled = value
		if radar != null:
			radar.alpr_enabled = value


func _ready() -> void:
	_start_traffic()
	_build_nodes()


func _autoload(autoload_name: String) -> Node:
	return get_node_or_null("/root/" + autoload_name)


func _start_traffic() -> void:
	var traffic := _autoload("Traffic")
	if traffic == null or not traffic.has_method("spawn_ambient"):
		return
	if traffic_count > 0:
		traffic.call("spawn_ambient", traffic_count)
	if "siren_source" in traffic:
		traffic.set("siren_source", patrol)   # civilians yield to the patrol car while its lights are on
	if recycle_traffic and main != null:
		recycler = TrafficRecycler.new()
		recycler.name = "TrafficRecycler"
		recycler.focus = main.player
		add_child(recycler)
		recycler.adopt_ambient()
	if patrol != null:
		TrafficRegistry.add(patrol, &"player")   # ambient cars keep their distance from the patrol car even outside a pursuit


func _build_nodes() -> void:
	director = CallDirector.new()
	director.name = "CallDirector"
	director.main = main
	director.seat = seat
	director.hud = hud
	add_child(director)
	radar = RadarFeed.new()
	radar.name = "RadarFeed"
	radar.patrol = patrol
	radar.seat = seat
	radar.hud = hud
	radar.alpr_enabled = alpr_enabled
	add_child(radar)
	duty = DutyFlow.new()
	duty.name = "DutyFlow"
	duty.director = director
	add_child(duty)


## Switches the call offers (the first one and the periodic ones) on or off; scenarios turn them off.
func set_calls_enabled(on: bool) -> void:
	if director != null:
		director.enabled = on


## One call that makes the world quiet for a scripted scene: no offers, no ambient radio chatter, no plate reader scanning and no
## ambient cars (the recycler is closed and its cars go, so does what Traffic still owns and the leftovers of finished call scenes).
func quiet() -> void:
	set_calls_enabled(false)
	var calls := _autoload("Calls")
	if calls != null:
		calls.set("ambient_enabled", false)
		calls.set("auto_offers", false)
	alpr_enabled = false
	if recycler != null:
		recycler.clear()
		recycler.queue_free()
		recycler = null
	recycle_traffic = false
	Traffic.clear()
	Traffic.ambient_target = 0
	if director != null:
		director.flush_retired()

## Debug key (F9): forces an ALPR hit on the car ahead. The pursuit starts once the lights are on and the car is close.
func force_alpr_hit() -> void:
	if radar != null:
		radar.force_hit()


## Nearest civilian vehicle in a cone ahead of the patrol car.
func vehicle_ahead(max_distance: float, cone_degrees: float) -> Vehicle:
	if patrol == null or not is_instance_valid(patrol):
		return null
	var best: Vehicle = null
	var best_distance := max_distance
	var forward := -patrol.global_transform.basis.z
	for candidate: Vehicle in Vehicles.all:
		if candidate == patrol or candidate.is_police or not is_instance_valid(candidate):
			continue
		var to := candidate.global_position - patrol.global_position
		var distance := to.length()
		if distance < 2.0 or distance > best_distance:
			continue
		to.y = 0.0
		if rad_to_deg(forward.angle_to(to.normalized())) > cone_degrees:
			continue
		best = candidate
		best_distance = distance
	return best


## Removes the ambient cars (shots without traffic).
func clear_traffic() -> void:
	if recycler != null:
		recycler.clear()
	Traffic.clear()
