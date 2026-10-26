extends Node
## Plays a scenario (scenarios/<name>.gd) on a fixed timestep, saves screenshots at the times the scenario lists
## and quits when it ends. Normally started through araclar/kayit.sh (Movie Maker); directly:
## araclar/godot.sh res://scenes/dev/scenario_main.tscn -- --scenario <name> [--out <absolute dir>]

const MAIN_SCENE := "res://scenes/main.tscn"

var _scenario: RefCounted
var _events: Array[Dictionary] = []
var _time := 0.0
var _next_shot := 0
var _out_dir := ""
var _finished := false
var _wall_deadline_ms := 0


func _ready() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var scenario_name: String = args.get("scenario", "")
	if scenario_name.is_empty():
		push_error("scenario_runner: --scenario <name> is required")
		get_tree().quit(1)
		return
	_out_dir = String(args.get("out", ProjectSettings.globalize_path("user://scenario_shots")))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_fit_window()
	var script := load("res://scenarios/%s.gd" % scenario_name) as GDScript
	if script == null or not script.can_instantiate():
		push_error("scenario_runner: scenarios/%s.gd not found" % scenario_name)
		get_tree().quit(1)
		return
	var main_scene := (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main_scene)
	_scenario = script.new()
	if _scenario == null:
		push_error("scenario_runner: scenarios/%s.gd could not be instantiated" % scenario_name)
		get_tree().quit(1)
		return
	_scenario.setup(main_scene)
	_events = _scenario.events()
	# Wall-clock watchdog: a stuck scenario must never keep a Godot process (and the araclar/godot.sh lock) alive.
	var max_wall := float(args.get("max-wall", float(_scenario.duration) * 12.0 + 120.0))
	_wall_deadline_ms = Time.get_ticks_msec() + int(max_wall * 1000.0)
	print("SCENARIO ", scenario_name, " duration=", _scenario.duration, " screen=", DisplayServer.screen_get_size())


func _process(_delta: float) -> void:
	if _wall_deadline_ms > 0 and not _finished and Time.get_ticks_msec() > _wall_deadline_ms:
		_finished = true
		push_error("scenario_runner: wall-clock limit reached, quitting")
		get_tree().quit(2)


func _physics_process(delta: float) -> void:
	if _scenario == null or _finished:
		return
	_time += delta
	for event in _events:
		if not event["done"] and _time >= event["t"]:
			event["done"] = true
			var action: Callable = event["fn"]
			action.call()
	var shots: Array[float] = _scenario.shots
	while _next_shot < shots.size() and _time >= shots[_next_shot]:
		var shot_time: float = shots[_next_shot]
		_next_shot += 1
		_save_shot(shot_time)
	if _time >= _scenario.duration:
		_finished = true
		get_tree().quit()


func _save_shot(shot_time: float) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%07.3f.png" % [_out_dir, shot_time]
	image.save_png(path)
	print("SHOT t=", shot_time, " ", image.get_size(), " -> ", path)


func _fit_window() -> void:
	var window := get_window()
	window.borderless = true
	window.size = Vector2i(1920, 1080)
	window.position = DisplayServer.screen_get_position()


func _parse(argv: PackedStringArray) -> Dictionary:
	var result := {}
	var i := 0
	while i < argv.size():
		if argv[i].begins_with("--") and i + 1 < argv.size():
			result[argv[i].substr(2)] = argv[i + 1]
			i += 2
		else:
			i += 1
	return result
