extends Node
## Dev scene root for scenes/ui/hud_test.tscn: HUD on a black background, filled with a saved HUD state.
## Pick it with `--preset silah|els|pursuit` after `--` (default: els).

var hud: Node


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(1920, 1080)
	add_child(bg)
	hud = load("res://scripts/hud/hud.gd").new()
	add_child(hud)
	var args := OS.get_cmdline_user_args()
	var preset := "els"
	var i := args.find("--preset")
	if i >= 0 and i + 1 < args.size():
		preset = args[i + 1]
	call("_preset_" + preset)


func _log(lines: Array) -> void:
	for l in lines:
		Dispatch.say(l)


func _preset_silah() -> void:
	GameState.minutes = 18.0 * 60.0 + 56.0
	GameState.clock_running = false
	GameState.set_weather("Clear")
	GameState.set_score(-2370)
	GameState.set_duty_status("Busy")
	hud.set_weapon_line("Shotgun", 4, 18)
	hud.set_street("Kiln Rd", 25)
	hud.minimap.set_map_texture(MinimapPanel.make_test_map())
	hud.minimap.set_player_state(Vector2(-30, 60), 0.0)
	hud.minimap.add_marker(Vector2(-28, 54), &"call")
	_log([
		"1-Adam-12: 10-97.",
		"Dispatch: all units, shots fired, officer needs assistance. 1-Adam-12, Eastgate. Respond Code 3.",
		"9-Henry-12, 9-Henry-27, 9-Henry-33, 9-Henry-41: en route.",
		"1-Adam-14: show me 10-8.",
		"3-Mary-41: my prisoner's booked, show me 10-8.",
		"1-Adam-22: 10-97.",
	])


func _preset_els() -> void:
	GameState.minutes = 17.0 * 60.0 + 22.0
	GameState.clock_running = true
	GameState.set_weather("Cloudy")
	GameState.set_duty_status("Busy")
	hud.set_score_visible(false)
	hud.set_vehicle_hud(true)
	hud.set_street("Davidson Beltway", 65)
	hud.set_speed(102.0)
	hud.set_rpm(4.2)
	hud.set_gear("5")
	hud.minimap.set_map_texture(MinimapPanel.make_test_map())
	hud.minimap.set_player_state(Vector2(-20, 90), deg_to_rad(8.0))
	Els.set_stage(3)
	Els.set_siren(&"yelp")
	_log([
		"Dispatch: 1-Adam-14, take the hit and run. Code 3.",
		"1-Adam-14: roger, on my way.",
	])


func _preset_pursuit() -> void:
	GameState.minutes = 11.0 * 60.0 + 47.0
	GameState.clock_running = true
	GameState.set_weather("Clear")
	GameState.set_score(115)
	GameState.set_duty_status("Available")
	hud.set_vehicle_hud(true)
	hud.set_mission("")
	hud.radar.set_radar(false, {}, "BOTH", "CLOSING", true, 70)
	hud.set_pursuit(510.0, "PIT requested")
	hud.set_street("Court St", 25)
	hud.set_speed(0.0)
	hud.set_rpm(1.3)
	hud.set_gear("N")
	hud.minimap.set_map_texture(MinimapPanel.make_test_map())
	hud.minimap.set_player_state(Vector2(0, 0), 0.0)
	Els.set_stage(3)
	Els.set_siren(&"yelp")
	_log([
		"9-Henry-27: Requesting permission to PIT.",
		"Dispatch: 9-Henry-27, stand by.",
	])


## Active/hover looks that are our own design (guesses): radar and ALPR on, toggles pressed, stage 1.
func _preset_els_on() -> void:
	_preset_els()
	hud.radar.set_radar(true, {&"front": "62", &"f_fast": "88", &"patrol": "45", &"rear": "40", &"r_fast": "--", &"lock_f": "88"})
	hud.radar.set_alpr(true, ["TAY-6023  registered owner has a warrant", "JPX-1815  owner's licence suspended"])
	Els.set_stage(1)
	Els.set_siren(&"prty")
	for id in [&"spot", &"cruise", &"rumbler", &"prog", &"warn"]:
		Els.set_toggle(id, true)
	Els.set_traffic_dir(&"left")
	Els.press(&"ah")
	hud.set_pursuit(37.0, "PIT authorized")
	hud.show_toast("Rumbler on")
