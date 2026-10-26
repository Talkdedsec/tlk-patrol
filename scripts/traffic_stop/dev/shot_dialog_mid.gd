extends RefCounted
## Screenshot setup: dialog after questions, documents and the search.
const Common := preload("res://scripts/traffic_stop/dev/shot_common.gd")


static func run(scene: Node) -> void:
	await_steps(scene)


static func await_steps(scene: Node) -> void:
	await Common.open_showcase(scene)
	var d = TrafficStop.dialog
	for id in [&"why", &"drink", &"illegal", &"docs", &"search"]:
		d.choose(id)
	await scene.get_tree().process_frame
	await scene.get_tree().process_frame
	TrafficStop._panel.list().scroll = 50.0
	TrafficStop._panel.list().queue_redraw()
