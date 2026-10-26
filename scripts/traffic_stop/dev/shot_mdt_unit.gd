extends RefCounted
## Screenshot setup: MDT UNIT tab (tahmin design).
const Common := preload("res://scripts/traffic_stop/dev/shot_common.gd")


static func run(scene: Node) -> void:
	Common.prep(scene, false)
	Calls.stats["calls"] = 3
	Calls.stats["stops"] = 2
	Calls.stats["warnings"] = 1
	Mdt.open(&"unit")
