extends RefCounted
## Helpers for the screenshot setups (scripts/dev/shot.gd --setup ...): host the UI inside the shot viewport,
## fake the HUD clock/score and fill the radio log.

const Overlay := preload("res://scripts/traffic_stop/stop_overlay.gd")
const HUD := preload("res://scripts/hud/hud.gd")


static func prep(scene: Node, with_hud: bool = true) -> void:
	Mdt.ui_parent = scene
	TrafficStop.ui_parent = scene
	Overlay.reparent_to(scene)
	GameState.minutes = 2.0 * 60.0 + 29.0
	GameState.clock_running = false
	GameState.set_weather("Cloudy")
	GameState.set_score(15)
	GameState.set_duty_status("Busy")
	if with_hud:
		scene.add_child(HUD.new())


static func seed_traffic() -> void:
	var lines := [
		["00:35", "Dispatch: 10-4, 6-Adam-15."], ["00:52", "5-Adam-23: gone on arrival."],
		["01:05", "5-Adam-11: my prisoner's booked, show me 10-8."], ["01:05", "Dispatch: 1-Adam-22, take the trespassing. Code 2."],
		["01:05", "1-Adam-22: 10-4, 10-76."], ["01:11", "Dispatch: Code 2, Suspicious person. A caller saw someone trying car doors near the Southside."],
		["01:14", "Dispatch: 1-Adam-14, take the noise complaint. Code 2."], ["01:14", "1-Adam-14: 10-4, 10-76."],
		["01:36", "Dispatch: 5-Adam-23, take the suspicious person. Code 2."], ["01:36", "5-Adam-23: 10-4, 10-76."],
		["01:40", "5-Lincoln-18: 10-97."],
		["02:17", "Dispatch: Code 2, Trespassing. A caller says a person is on private property near the Southside and will not leave."],
		["02:19", "1-Adam-12: unable, I'm tied up."], ["02:19", "Dispatch: 10-22, another unit will handle the trespassing."],
		["02:23", "5-Lincoln-18: clearing."], ["02:25", "1-Adam-14: 10-97."],
	]
	Mdt.clear_traffic()
	for entry in lines:
		Mdt.add_traffic(entry[1], entry[0])


## Starts the showcase stop instantly and opens the dialog panel. Coroutine: call without await from a setup.
static func open_showcase(scene: Node) -> void:
	prep(scene, true)
	Calls.voice.enabled = false
	TrafficStop.dialog_voice.enabled = false
	var target: Node3D = scene.target
	target.plate = "KEA-9291"
	target.ai_enabled = false
	TrafficStop.begin(target, {"instant": true, "announce": false, "lights": false})
	await scene.get_tree().process_frame
	await scene.get_tree().process_frame
	TrafficStop.open_dialog()
	await scene.get_tree().process_frame
