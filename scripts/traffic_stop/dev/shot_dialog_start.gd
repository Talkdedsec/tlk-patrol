extends RefCounted
## Screenshot setup: dialog panel as opened.
const Common := preload("res://scripts/traffic_stop/dev/shot_common.gd")


static func run(scene: Node) -> void:
	Common.open_showcase(scene)
