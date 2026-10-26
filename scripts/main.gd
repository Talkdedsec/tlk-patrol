extends Node3D
## Game bootstrap: city, day start, patrol car, officer, HUD and the integration layer in scripts/game/.
## Scenarios (scripts/dev/scenario_runner.gd) read player, patrol_vehicle and hud from this node. API: docs/api/game.md.

const GameHud := preload("res://scripts/game/game_hud.gd")
const PlayerOfficer := preload("res://scripts/game/player_officer.gd")
const VehicleSeat := preload("res://scripts/game/vehicle_seat.gd")
const GameHooks := preload("res://scripts/game/game_hooks.gd")
const GameInput := preload("res://scripts/game/game_input.gd")
const PursuitAdapters := preload("res://scripts/pursuit/adapters.gd")

const OFFICER_SCENE := "res://scenes/characters/officer.tscn"
const PATROL_TYPES: Array[StringName] = [&"patrol_suv", &"patrol_sedan", &"sheriff_pickup"]
const START_SPAWN := &"hoover_st"
const START_MINUTES := 13.0 * 60.0 + 13.0
const START_WEATHER := "Cloudy"

## Officer model: &"police" (default) or &"sheriff" (traffic stop). Read when the officer is built; set_officer_model() swaps it afterwards.
var officer_model: StringName = &"police"
var player: Officer
var patrol_vehicle: Vehicle
var hud
var seat: Node
var vehicle_camera: VehicleCamera
var hooks: Node


func _ready() -> void:
	GameInput.register()
	World.build(self)
	_start_day()
	Vehicles.skid_parent = self
	PursuitAdapters.spawn_parent = self
	_spawn_patrol_vehicle()
	_spawn_player()
	_build_hud()
	_build_seat()
	_build_hooks()


## 13:13, Cloudy, clock running (1 real second = 1 game minute), score 0, Available.
func _start_day() -> void:
	World.set_weather(START_WEATHER)
	World.set_time(START_MINUTES / 60.0)
	GameState.minutes = START_MINUTES
	GameState.clock_running = true
	GameState.set_score(0)
	GameState.set_duty_status("Available")


func _spawn_patrol_vehicle() -> void:
	var spawn := World.spawn_point(START_SPAWN)
	var lifted := Transform3D(spawn.basis, spawn.origin + Vector3(0.0, 0.3, 0.0))
	var type_id: StringName = PATROL_TYPES[0]
	for candidate in PATROL_TYPES:
		if Vehicles.has_type(candidate):
			type_id = candidate
			break
	patrol_vehicle = Vehicles.spawn(type_id, lifted, self)
	patrol_vehicle.add_to_group("player_vehicle")
	patrol_vehicle.use_els(true)
	patrol_vehicle.set_handbrake(true)


func _spawn_player() -> void:
	var node := (load(OFFICER_SCENE) as PackedScene).instantiate()
	node.set_script(PlayerOfficer)
	node.set("model_kind", String(officer_model))
	player = node as Officer
	player.capture_mouse = not _no_capture()
	add_child(player)
	var door := patrol_vehicle.enter_transform(&"driver")
	var forward := -patrol_vehicle.global_transform.basis.z
	var ground := World.spawn_point(START_SPAWN).origin.y
	player.global_position = Vector3(door.origin.x, ground + 0.05, door.origin.z) - forward * 1.4
	var heading := atan2(-forward.x, -forward.z)
	player.rotation.y = heading
	player.force_look(heading, Officer.DEFAULT_PITCH)


func _build_hud() -> void:
	hud = GameHud.new()
	add_child(hud)
	hud.set_mission("")


func _build_seat() -> void:
	vehicle_camera = VehicleCamera.new()
	vehicle_camera.name = "VehicleCamera"
	add_child(vehicle_camera)
	seat = VehicleSeat.new()
	seat.name = "VehicleSeat"
	seat.officer = player
	seat.vehicle = patrol_vehicle
	seat.camera = vehicle_camera
	seat.hud = hud
	add_child(seat)
	player.set("seat", seat)


func _build_hooks() -> void:
	hooks = GameHooks.new()
	hooks.name = "GameHooks"
	hooks.main = self
	hooks.patrol = patrol_vehicle
	hooks.seat = seat
	hooks.hud = hud
	add_child(hooks)
	seat.hooks = hooks


## Swaps the officer's model (&"police" or &"sheriff") on foot: a new officer is built in the old one's place (position, heading,
## look direction), the seat and the other modules follow. Scenarios call it right after the scene is built.
func set_officer_model(model: StringName) -> void:
	if model == officer_model and player != null:
		return
	officer_model = model
	if player == null:
		return
	var old := player
	var pos := old.global_position
	var heading := old.rotation.y
	var look_yaw := old.yaw
	var look_pitch := old.pitch
	remove_child(old)
	old.queue_free()
	_spawn_player()
	player.global_position = pos
	player.rotation.y = heading
	player.force_look(look_yaw, look_pitch)
	if seat != null:
		seat.officer = player
		player.set("seat", seat)

## Screenshots and headless runs leave the mouse alone (shot.gd scenes pass --no-capture).
func _no_capture() -> bool:
	return DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--no-capture")
