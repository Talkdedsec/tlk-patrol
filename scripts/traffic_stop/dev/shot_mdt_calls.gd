extends RefCounted
## Screenshot setup: MDT CALLS tab with a few calls and a pending offer (tahmin design).
const Common := preload("res://scripts/traffic_stop/dev/shot_common.gd")


static func run(scene: Node) -> void:
	Common.prep(scene, false)
	Calls.offer(&"trespassing")
	Calls.pass_offer()
	Calls.offer(&"noise_complaint")
	Calls.respond()
	Calls.complete()
	Calls.offer(&"stolen_vehicle")
	Mdt.open(&"calls")
