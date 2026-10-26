extends RefCounted
## Screenshot setup: citation form.
const Common := preload("res://scripts/traffic_stop/dev/shot_common.gd")


static func run(scene: Node) -> void:
	steps(scene)


static func steps(scene: Node) -> void:
	await Common.open_showcase(scene)
	var d = TrafficStop.dialog
	for id in [&"why", &"drink", &"illegal", &"docs", &"search", &"fst", &"breath", &"cite"]:
		d.choose(id)
	await scene.get_tree().process_frame
