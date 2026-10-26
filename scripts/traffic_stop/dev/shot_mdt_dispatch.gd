extends RefCounted
## Screenshot setup: MDT DISPATCH tab.
const Common := preload("res://scripts/traffic_stop/dev/shot_common.gd")


static func run(scene: Node) -> void:
	Common.prep(scene, false)
	Common.seed_traffic()
	Mdt.open(&"dispatch")
