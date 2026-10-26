extends RefCounted
## Screenshot setup: MDT PLATES tab after a plate run.
const Common := preload("res://scripts/traffic_stop/dev/shot_common.gd")


static func run(scene: Node) -> void:
	Common.prep(scene, false)
	GameState.minutes = 2.0 * 60.0 + 37.0
	Mdt.clear_plate_log()
	Mdt.add_plate_line("02:30  Running plate KEA-9291...")
	Mdt.add_plate_line("[b]KEA-9291[/b], Halvorsen Ranger SUV")
	Mdt.add_plate_line("Owner: Darnell Foster")
	Mdt.add_plate_line("No hits.")
	Mdt.open(&"plates")
