extends Node
## Integration check against the real characters (scenes/characters/officer.tscn + npc.tscn): auto bind, stance
## driven by Weapons, raycast hits on an Npc, flee after the first hit, downed after enough damage.
##   araclar/godot.sh --headless res://scenes/weapons/selftest_chars.tscn --quit-after 3000
## Real time (no manual tick) because the rig animations run on engine time.

var _passed := 0
var _failed := 0
var _hits := 0


func _ready() -> void:
	var officer_scene := load("res://scenes/characters/officer.tscn") as PackedScene
	var npc_scene := load("res://scenes/characters/npc.tscn") as PackedScene
	if officer_scene == null or npc_scene == null:
		print("SELFTEST_CHARS skipped: character scenes missing")
		get_tree().quit(0)
		return
	_build_ground()
	var officer := officer_scene.instantiate() as CharacterBody3D
	officer.capture_mouse = false
	add_child(officer)
	var npc := npc_scene.instantiate() as CharacterBody3D
	npc.position = Vector3(0.0, 0.0, -9.0)
	add_child(npc)
	var spy := (load("res://scripts/weapons/hud_spy.gd") as GDScript).new() as Node
	add_child(spy)
	await _frames(4)
	Weapons.reset()
	Weapons.hud = spy
	Weapons.target_hit.connect(func(_n: Node, _d: float, _p: String) -> void: _hits += 1)

	_check("officer auto-bound", Weapons.officer == officer)
	_check("officer auto visuals handed over", officer.auto_visuals == false)
	_check("direct input off", not Weapons.direct_input)
	_check("loadout set on the rig", officer.rig.loadout.has(&"pistol") and officer.rig.loadout.has(&"shotgun"))

	officer.draw_requested.emit()
	await _frames(2)
	_check("key 5 signal draws: rig drawing", officer.rig.weapon_state == &"drawing", String(officer.rig.weapon_state))
	_check("HUD line 17 / 34", spy.line == "Pistol 17 / 34", spy.line)
	await get_tree().create_timer(1.6).timeout
	_check("rig ready and Weapons ready", officer.rig.weapon_state == &"ready" and Weapons.is_ready(),
			"%s %d" % [officer.rig.weapon_state, Weapons.state])

	await _aim_camera_at(officer, npc.global_position + Vector3(0.0, 1.1, 0.0))
	var live := Weapons.fire_at(npc, "torso")
	await _frames(2)
	_check("scripted shot on the Npc", live and _hits == 1)
	_check("Npc runs after the first hit", npc.state == &"flee", String(npc.state))
	for i in 5:
		await get_tree().create_timer(0.3).timeout
		Weapons.fire_at(npc, "torso")
	await _frames(2)
	_check("Npc is down after enough hits", npc.state == &"downed", String(npc.state))
	_check("downed Npc is no longer a live target", not (Weapons.get("_adapters") as RefCounted).is_live_target(npc))

	var runner := npc_scene.instantiate() as CharacterBody3D
	runner.position = Vector3(0.0, 0.0, -12.0)
	add_child(runner)
	await _frames(3)
	await _aim_camera_at(officer, runner.global_position + Vector3(0.0, 1.1, 0.0))
	Weapons.set_aim(true)
	await get_tree().create_timer(1.5).timeout
	var before := _hits
	var tries := 0
	while _hits == before and tries < 8:
		Weapons.set_ammo(17, 34)
		Weapons.fire()
		tries += 1
		await get_tree().create_timer(0.3).timeout
	_check("real crosshair raycast hits the second Npc", _hits > before, "tries=%d" % tries)

	Weapons.holster()
	var elapsed := 0.0
	var hud_closed := -1.0
	var state_done := -1.0
	while elapsed < 1.3:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		if hud_closed < 0.0 and spy.line == "":
			hud_closed = elapsed
		if state_done < 0.0 and Weapons.state == Weapons.State.HOLSTERED:
			state_done = elapsed
	_check("HUD line closes at about 0.6 s", hud_closed > 0.5 and hud_closed < 0.68, "%.3f" % hud_closed)
	_check("holster animation (0.7 s) outlasts the HUD line", state_done >= hud_closed, "%.3f vs %.3f" % [state_done, hud_closed])
	_check("holstered: rig unarmed and HUD cleared", officer.rig.weapon_state == &"unarmed" and spy.line == "",
			"%s '%s'" % [officer.rig.weapon_state, spy.line])
	print("SELFTEST_CHARS %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label, "  ", detail)


func _aim_camera_at(officer: CharacterBody3D, point: Vector3) -> void:
	for i in 6:
		var dir: Vector3 = (point - officer.camera.global_position).normalized()
		officer.yaw = atan2(-dir.x, -dir.z)
		officer.pitch = asin(dir.y)
		await _frames(2)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	add_child(ground)
	var sun := DirectionalLight3D.new()
	add_child(sun)
