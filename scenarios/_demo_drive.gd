extends "res://scripts/dev/scenario_base.gd"
## Playable-loop smoke test: the officer walks to the patrol car, gets in, switches on lights and siren, drives about
## 15 s straight up Hoover St, stops and gets out again. Frame times are printed by the probe ("PERF ...").
## Record: araclar/kayit.sh _demo_drive

const AutoDrive := preload("res://scripts/game/auto_drive.gd")
const PerfProbe := preload("res://scripts/game/perf_probe.gd")

var _driver: Node


func _init() -> void:
	duration = 29.0
	shots = [1.0, 2.2, 3.0, 3.8, 4.6, 5.8, 8.0, 13.0, 19.0, 23.0, 25.8, 26.6, 28.0]
	if OS.get_cmdline_user_args().has("--noshots"):   # clean frame-time measurement: screenshots cause hitches
		shots = []


func setup(main_scene: Node) -> void:
	super(main_scene)
	main.add_child(PerfProbe.new())
	main.hooks.set_calls_enabled(false)
	main.hooks.alpr_enabled = false
	TrafficStop.auto_detect = false                                                      # no random stop while the lights are on
	at(0.2, func() -> void: main.seat.scripted_drive = true)                          # the scenario drives, not the keyboard
	at(1.5, func() -> void: main.seat.enter(main.patrol_vehicle))                       # walk to the door, door opens, sits
	at(5.2, func() -> void: Els.set_siren(&"yelp"))                                    # lights + siren
	at(6.0, func() -> void: _start_driving())
	at(21.0, func() -> void: _driver.stop(0.8))                                        # 15 s of driving
	at(25.0, func() -> void: main.seat.exit())


func _start_driving() -> void:
	_driver = AutoDrive.new()
	main.add_child(_driver)
	_driver.follow_straight(main.patrol_vehicle, 700.0, 42.0)
