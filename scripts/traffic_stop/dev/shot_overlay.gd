extends RefCounted
## Screenshot setup: top-centre prompts, bottom prompt and the SCENE COMMANDS box.
const Common := preload("res://scripts/traffic_stop/dev/shot_common.gd")
const Overlay := preload("res://scripts/traffic_stop/stop_overlay.gd")


static func run(scene: Node) -> void:
	Common.prep(scene, true)
	Calls.voice.enabled = false
	TrafficStop.set_process(false)  # it would clear the faked prompt every frame
	var overlay := Overlay.of(scene.get_tree())
	overlay.toast("Status: Busy", 60.0)
	overlay.set_offer("Code 3: Stolen vehicle.   Y respond   N pass   (22)")
	overlay.set_chase_miles(0.2)
	overlay.set_prompt("E  Talk to the driver")
	overlay.set_flashlight_line(true)
	overlay.show_scene_commands("KEA-9291")
