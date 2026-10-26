extends RefCounted
## Base class for scripted demo scenarios (scenarios/*.gd, `extends "res://scripts/dev/scenario_base.gd"`).
## A scenario lists timed events; scenario_runner.gd executes them on a fixed timestep (seconds from scenario start).

var main: Node                     ## the running Main scene
var duration := 10.0               ## seconds until the runner quits
var shots: Array[float] = []       ## times at which the runner saves screenshots (for visual checks)
var _events: Array[Dictionary] = []
var _camera: Camera3D


func setup(main_scene: Node) -> void:
	main = main_scene


func at(time: float, action: Callable) -> void:
	_events.append({"t": time, "fn": action, "done": false})


func events() -> Array[Dictionary]:
	_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	return _events


func hud() -> Node:
	for child in main.get_children():
		if child.has_method("set_weapon_line"):
			return child
	return null


## Scripted camera for replays: places (and on first use creates) a Camera3D under main and makes it current.
func camera(xf: Transform3D, fov: float = 75.0) -> Camera3D:
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "ScenarioCamera"
		main.add_child(_camera)
	_camera.global_transform = xf
	_camera.fov = fov
	_camera.make_current()
	return _camera
