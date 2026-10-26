extends Node3D
## Character test bench. Modes (user args after `--`):
##   (none)                       interactive: controllable officer + pedestrians in different states
##   --mode sheet --anims a,b,c [--t 0.3] [--model police|sheriff|civilian] [--cam 150] [--dist 5]
##                                 line-up of rigs frozen on the given animations (use with scripts/dev/shot.gd)
##   --mode measure                prints animation lengths against the target values and times the stance state machine

# animation -> [target seconds, source]
const TARGETS := {
	&"pistol_raise": [0.44, "kaldırma ≈440 ms"],
	&"pistol_lower": [0.22, "nişan çıkışı ≈220 ms"],
	&"pistol_holster": [0.70, "kol ≈150 ms + kılıf ≈0,6 sn"],
	&"rifle_draw": [0.85, "askıdan ele ≈600 ms + alçak hazır ≈250 ms"],
	&"rifle_raise": [0.32, "alçak hazırdan ADS ≈320 ms"],
	&"rifle_lower": [0.167, "ADS çıkışı ≈167 ms"],
	&"death_fall": [0.60, "vuruştan yüzüstüne ≈600 ms (+150 ms bekleme)"],
	&"cuffing": [3.0, "'Cuffing...' ≈3 sn"],
}

var _args: Dictionary = {}


func _ready() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	_build_environment()
	match String(_args.get("mode", "play")):
		"sheet":
			_sheet()
		"measure":
			_measure()
		_:
			_play()


func _parse(argv: PackedStringArray) -> Dictionary:
	var result := {}
	var i := 0
	while i < argv.size():
		if argv[i].begins_with("--") and i + 1 < argv.size():
			result[argv[i].substr(2)] = argv[i + 1]
			i += 2
		else:
			i += 1
	return result


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("A9B6C4")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("C8D2DC")
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	collision.shape = box
	collision.position.y = -0.5
	ground.add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("6C7078")
	plane.material = material
	mesh_instance.mesh = plane
	ground.add_child(mesh_instance)
	add_child(ground)


# --- sheet --------------------------------------------------------------------------------------------------------
func _sheet() -> void:
	var names: PackedStringArray = String(_args.get("anims", "idle,walk,run")).split(",")
	var time := float(_args.get("t", "0.3"))
	var kind := String(_args.get("model", "police"))
	var spacing := float(_args.get("spacing", "1.3"))
	var weapon := StringName(String(_args.get("weapon", "")))
	var model_path := {
		"police": "res://assets/models/characters/officer_police.glb",
		"sheriff": "res://assets/models/characters/officer_sheriff.glb",
		"civilian": "res://assets/models/characters/civilian.glb",
	}[kind] as String
	var count := names.size()
	for i in count:
		var rig := CharacterRig.new()
		add_child(rig)
		rig.setup(model_path)
		rig.position.x = (i - (count - 1) * 0.5) * spacing
		rig.rotation.y = deg_to_rad(float(_args.get("rot", "0")))
		if kind == "civilian":
			Outfits.apply(rig.model, &"purple_sweater" if i % 2 == 0 else &"red_shirt_blue_shorts")
		if weapon != &"":
			rig.set_loadout([weapon])
			rig._to_hand(rig._props[CharacterRig.WEAPONS[weapon]["prop"]])
		var label := Label3D.new()
		label.text = names[i]
		label.position = Vector3(rig.position.x, 2.0, 0.0)
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		var parts := names[i].split("@")
		label.text = names[i]
		rig.preview(StringName(parts[0]), float(parts[1]) if parts.size() > 1 else time)
	var cam := Camera3D.new()
	var yaw := deg_to_rad(float(_args.get("cam", "150")))   # 180 = in front of the characters (they face -Z)
	var dist := float(_args.get("dist", str(maxf(4.0, count * spacing * 0.85))))
	cam.fov = float(_args.get("fov", "40"))
	cam.position = Vector3(sin(yaw) * dist, float(_args.get("height", "1.1")), -cos(yaw) * dist * -1.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, float(_args.get("look", "0.85")), 0.0), Vector3.UP)
	cam.make_current()


# --- interactive ----------------------------------------------------------------------------------------------------
func _play() -> void:
	var officer := Officer.new()
	officer.model_kind = String(_args.get("model", "police"))
	officer.position = Vector3(0, 0.05, 6.0)
	add_child(officer)
	officer.set_loadout([&"pistol"])
	officer.rotation.y = 0.0
	var states := [&"idle", &"walk", &"surrender", &"kneel", &"downed", &"cuffed", &"talk"]
	var outfits := Outfits.names()
	for i in states.size():
		var npc := Npc.new()
		npc.outfit = outfits[i % outfits.size()]
		npc.skin_index = i
		npc.position = Vector3((i - 3) * 1.6, 0.05, 0.0)
		add_child(npc)
		await get_tree().process_frame
		match states[i]:
			&"walk":
				npc.walk_to(npc.position + Vector3(0, 0, 18.0))
			&"surrender":
				npc.surrender()
			&"kneel":
				npc.kneel()
			&"downed":
				npc.go_down(&"shot")
			&"cuffed":
				npc.cuff()
			&"talk":
				npc.talk()
	var help := Label.new()
	help.text = "WASD move (Shift walk) | mouse look | 5 draw/holster | RMB aim | LMB fire | hold R reload | 1/2/3 pistol/rifle/shotgun | F flashlight"
	help.position = Vector2(12, 8)
	add_child(help)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var officer := get_node_or_null("Officer") as Officer
	if officer == null:
		for child in get_children():
			if child is Officer:
				officer = child
	if officer == null:
		return
	match key.keycode:
		KEY_1, KEY_2, KEY_3:
			var id := {KEY_1: &"pistol", KEY_2: &"rifle", KEY_3: &"shotgun"}[key.keycode] as StringName
			if officer.rig.is_armed():
				officer.holster_weapon()
			officer.set_loadout([id])
			officer.select_weapon(id)
		KEY_F:
			officer.rig.set_flashlight(true)


# --- measure ----------------------------------------------------------------------------------------------------------
func _measure() -> void:
	print("== animation lengths vs report targets ==")
	for anim_name: StringName in TARGETS:
		var target: float = TARGETS[anim_name][0]
		var length := CharacterRig.anim_length(anim_name)
		print("%-16s target %.3f s  actual %.3f s  diff %+.0f ms   (%s)" % [anim_name, target, length, (length - target) * 1000.0, TARGETS[anim_name][1]])
	print("== all animations ==")
	for group in ["loco", "upper", "full"]:
		for anim_name in CharacterRig.anim_names(group):
			print("%-5s %-18s %.3f s" % [group, anim_name, CharacterRig.anim_length(anim_name)])
	print("== stance state machine (wall clock) ==")
	var rig := CharacterRig.new()
	add_child(rig)
	rig.setup("res://assets/models/characters/officer_police.glb")
	rig.set_loadout([&"pistol", &"rifle"])
	await get_tree().process_frame
	await get_tree().process_frame
	for weapon_id: StringName in [&"pistol", &"rifle"]:
		var t0 := Time.get_ticks_msec()
		rig.draw(weapon_id)
		await _wait_state(rig, &"ready")
		print("%s draw -> ready: %d ms" % [weapon_id, Time.get_ticks_msec() - t0])
		t0 = Time.get_ticks_msec()
		rig.set_aiming(true)
		await _wait_state(rig, &"aiming")
		print("%s ready -> aiming: %d ms" % [weapon_id, Time.get_ticks_msec() - t0])
		t0 = Time.get_ticks_msec()
		rig.set_aiming(false)
		await _wait_state(rig, &"ready")
		print("%s aiming -> ready: %d ms" % [weapon_id, Time.get_ticks_msec() - t0])
		t0 = Time.get_ticks_msec()
		rig.holster()
		await _wait_state(rig, &"unarmed")
		print("%s holster -> unarmed: %d ms" % [weapon_id, Time.get_ticks_msec() - t0])
	print("MEASURE DONE")
	get_tree().quit()


func _wait_state(rig: CharacterRig, wanted: StringName) -> void:
	while rig.weapon_state != wanted:
		await get_tree().process_frame
