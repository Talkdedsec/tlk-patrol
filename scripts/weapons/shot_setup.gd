extends RefCounted
## Setup script for scripts/dev/shot.gd: stages a weapon situation in the test range for a screenshot.
##   araclar/godot.sh --script res://scripts/dev/shot.gd -- --scene res://scenes/weapons/test_range.tscn \
##       --setup res://scripts/weapons/shot_setup.gd --mode pistol_shot --frames 4 --out C:/tmp/w.png
## Modes: aim (pistol, crosshair on target), pistol_shot, rifle_shot, shotgun_shot, shotgun_smoke, hit_marker.
## Effects are slowed by `--fx` (default 4) so a single frame catches the flash.


static func run(scene: Node) -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var mode: String = args.get("mode", "aim")
	var fx_scale := float(args.get("fx", "4"))
	var officer: Node3D = scene.officer
	var target: Node3D = scene.targets[0]
	Weapons.fx_time_scale = fx_scale
	Weapons.casings_enabled = true
	var weapon := "pistol"
	if mode.begins_with("rifle"):
		weapon = "rifle"
	elif mode.begins_with("shotgun"):
		weapon = "shotgun"
	Weapons.equip(weapon, true)
	officer.look_at_point(target.global_position + Vector3(0.0, 1.1, 0.0))
	Weapons.set_aim(true)
	officer._aim_t = 1.0
	officer._aiming = true
	match mode:
		"pistol_shot", "rifle_shot", "shotgun_shot":
			Weapons.fire()
		"hit_marker":
			Weapons.fire()
		"shotgun_smoke":
			Weapons.fire()


static func _parse(argv: PackedStringArray) -> Dictionary:
	var result := {}
	var i := 0
	while i < argv.size():
		if argv[i].begins_with("--") and i + 1 < argv.size():
			result[argv[i].substr(2)] = argv[i + 1]
			i += 2
		else:
			i += 1
	return result
