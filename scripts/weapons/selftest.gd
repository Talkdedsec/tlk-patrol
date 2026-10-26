extends Node
## Headless self test for the weapon module. Run:
##   araclar/godot.sh --headless res://scenes/weapons/selftest.tscn --quit-after 3000
## Uses the test range (placeholder capsule targets), a HUD spy and Weapons.manual_tick for deterministic timing.
## Checks the weapon rules plus the scenario hooks.

const TestDummy := preload("res://scripts/weapons/test_dummy.gd")
const HudSpy := preload("res://scripts/weapons/hud_spy.gd")
const OfficerStub := preload("res://scripts/weapons/officer_stub.gd")

var _passed := 0
var _failed := 0
var _spy: Node
var _range: Node3D
var _officer: Node3D
var _counts := {"shot": 0, "hit": 0, "downed": 0, "lethal": 0, "dry": 0, "aim": 0, "reload_done": 0}
var _last_shot := {}


func _ready() -> void:
	_range = (load("res://scenes/weapons/test_range.tscn") as PackedScene).instantiate()
	add_child(_range)
	_officer = _range.officer
	for target in _range.targets:
		target.queue_free()
	_spy = HudSpy.new()
	add_child(_spy)
	await _settle()
	Weapons.manual_tick = true
	Weapons.hud = _spy
	Weapons.fx_time_scale = 0.5
	Weapons.shot_fired.connect(func(origin: Vector3, dir: Vector3, weapon: StringName) -> void:
		_counts["shot"] += 1
		_last_shot = {"origin": origin, "dir": dir, "weapon": weapon})
	Weapons.target_hit.connect(func(_npc: Node, _damage: float, _part: String) -> void: _counts["hit"] += 1)
	Weapons.target_downed.connect(func(_npc: Node, _weapon: StringName, lethal: bool) -> void:
		_counts["downed"] += 1
		if lethal:
			_counts["lethal"] += 1)
	Weapons.dry_fired.connect(func(_weapon: StringName) -> void: _counts["dry"] += 1)
	Weapons.aim_changed.connect(func(_on: bool) -> void: _counts["aim"] += 1)
	Weapons.reload_finished.connect(func(_weapon: StringName) -> void: _counts["reload_done"] += 1)

	await _test_defaults_and_draw()
	await _test_pistol_clicks()
	await _test_cooldown_dry_and_reload()
	await _test_crosshair()
	await _test_rifle()
	await _test_shotgun()
	await _test_holster_and_toggle()
	await _test_officer_signals()
	await _test_dead_target_marker()
	await _test_scenario_replay()
	print("SELFTEST %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- helpers -------------------------------------------------------------------------

func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _step(seconds: float) -> void:
	var n := int(round(seconds * 120.0))
	for i in n:
		Weapons.tick(1.0 / 120.0)


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_passed += 1
		print("  ok   ", label)
	else:
		_failed += 1
		print("  FAIL ", label, "  ", detail)


func _spawn_dummy(at: Vector3) -> Node3D:
	var dummy := TestDummy.new()
	dummy.position = at
	_range.add_child(dummy)
	return dummy


func _aim_at(dummy: Node3D, part_y := 1.15) -> void:
	_officer.look_at_point(dummy.global_position + Vector3(0.0, part_y, 0.0))
	await _settle()


func _reset_counts() -> void:
	for key: String in _counts:
		_counts[key] = 0


# --- tests ---------------------------------------------------------------------------

func _test_defaults_and_draw() -> void:
	print("defaults and draw")
	Weapons.reset()
	_check("pistol 17/34", Weapons.get_ammo("pistol") == {"mag": 17, "reserve": 34})
	_check("patrol rifle 29/56", Weapons.get_ammo("Patrol rifle") == {"mag": 29, "reserve": 56})
	_check("shotgun 6/18", Weapons.get_ammo("shotgun") == {"mag": 6, "reserve": 18})
	_check("starts holstered", Weapons.equipped == &"" and Weapons.state == Weapons.State.HOLSTERED)
	_spy.clear_count = 0
	_check("equip Pistol", Weapons.equip("Pistol"))
	_check("HUD line on draw", _spy.line == "Pistol 17 / 34", _spy.line)
	_check("drawing state", Weapons.state == Weapons.State.DRAWING)
	_check("cannot fire while drawing", not Weapons.fire())
	_step(0.5)
	_check("ready after draw time", Weapons.state == Weapons.State.READY)


func _test_pistol_clicks() -> void:
	print("pistol: 12 clicks, 0.3 s apart")
	var dummy := _spawn_dummy(Vector3(0.45, 0.0, -8.0))
	await _aim_at(dummy)
	_reset_counts()
	Weapons.set_aim(true)
	_step(2.0)
	var fired := 0
	var first_hit_alive := false
	for i in 12:
		if Weapons.fire():
			fired += 1
		if i == 0:
			first_hit_alive = not dummy.downed and dummy.hits == 1
		_step(0.3)
	_check("12 shots fired", fired == 12 and _counts["shot"] == 12, str(fired))
	_check("17 -> 5, reserve stays 34", Weapons.get_ammo() == {"mag": 5, "reserve": 34}, str(Weapons.get_ammo()))
	_check("HUD shows 5 / 34", _spy.line == "Pistol 5 / 34", _spy.line)
	_check("first hit does not kill", first_hit_alive, "hits=%d downed=%s" % [dummy.hits, dummy.downed])
	_check("target goes down within the burst", dummy.downed and dummy.hits >= 4, "hits=%d" % dummy.hits)
	_check("one downed event, lethal", _counts["downed"] == 1 and _counts["lethal"] == 1)
	_check("hit events fired", _counts["hit"] >= 4, str(_counts["hit"]))


func _test_cooldown_dry_and_reload() -> void:
	print("cooldown, dry fire, reload")
	Weapons.set_ammo(17, 34)
	_step(1.0)
	_check("shot 1", Weapons.fire())
	_step(0.05)
	_check("second click inside the 0.22 s interval is ignored", not Weapons.fire())
	_step(0.2)
	_check("click after the interval fires", Weapons.fire())
	Weapons.set_ammo(0, 34)
	_reset_counts()
	_step(0.3)
	_check("empty magazine: no shot", not Weapons.fire() and Weapons.get_ammo()["mag"] == 0)
	_check("dry fire event", _counts["dry"] == 1)
	_check("reload starts", Weapons.start_reload() and Weapons.state == Weapons.State.RELOADING)
	_step(1.5)
	_check("still reloading at 1.5 s", Weapons.state == Weapons.State.RELOADING)
	_step(0.2)
	_check("reloaded 17 / 17 (34 - 17)", Weapons.get_ammo() == {"mag": 17, "reserve": 17}, str(Weapons.get_ammo()))
	_check("HUD shows 17 / 17", _spy.line == "Pistol 17 / 17", _spy.line)
	_check("full magazine: no reload", not Weapons.start_reload())
	Weapons.set_ammo(3, 0)
	_check("no reserve: no reload", not Weapons.start_reload())
	Weapons.set_ammo(-5, -1)
	_check("negative ammo clamps to 0", Weapons.get_ammo() == {"mag": 0, "reserve": 0})
	Weapons.set_ammo(17, 34)


func _test_crosshair() -> void:
	print("crosshair")
	var xh: Node = Weapons.get_crosshair()
	_check("crosshair scene exists", xh != null)
	Weapons.set_aim(false)
	_step(0.1)
	_check("hidden when not aiming", not xh.active)
	Weapons.set_aim(true)
	_step(0.02)
	_check("visible while aiming", xh.active and xh.bars_visible())
	_check("opens wide when the aim camera starts (about 30 px)", xh.spread_px > 25.0 and xh.spread_px < 34.0, str(xh.spread_px))
	_step(2.0)
	_check("calm spread +-7..12 px", xh.spread_px >= 7.0 and xh.spread_px <= 12.0, str(xh.spread_px))
	var dummy := _spawn_dummy(Vector3(-3.0, 0.0, -14.0))
	await _aim_at(dummy)
	_step(0.05)
	_check("red over a live target", xh.on_target)
	_officer.look_at_point(Vector3(10.0, 0.0, -30.0))
	await _settle()
	_step(0.05)
	_check("white (not red) off target", not xh.on_target)
	await _aim_at(dummy)
	_step(0.05)
	Weapons.equip("pistol", true)
	_step(0.3)
	var hits_before: int = _counts["hit"]
	Weapons.fire()
	_check("hit marker right after a hit", _counts["hit"] > hits_before and xh.marker_alpha() > 0.9, str(xh.marker_alpha()))
	_check("spread opens to about 50 px after a shot", xh.spread_px > 44.0 and xh.spread_px < 53.0, str(xh.spread_px))
	_check("bars hidden right after a pistol shot", not xh.bars_visible())
	_step(0.1)
	_check("hit marker fading at 0.1 s", xh.marker_alpha() > 0.3 and xh.marker_alpha() < 0.7, str(xh.marker_alpha()))
	_step(0.15)
	_check("hit marker gone after 0.2 s", xh.marker_alpha() == 0.0)
	_check("bars still hidden at 0.25 s", not xh.bars_visible())
	_step(0.12)
	_check("bars back after about 0.35 s", xh.bars_visible())
	_step(0.63)
	_check("about 1 s after the shot spread is back near 19 px", xh.spread_px > 16.0 and xh.spread_px < 23.0, str(xh.spread_px))
	_step(2.0)
	for i in 40:
		Weapons.set_movement(5.0, 0.0)
		_step(0.01)
	_check("moving opens to +-50..60 px", xh.spread_px >= 50.0 and xh.spread_px <= 60.0, str(xh.spread_px))
	Weapons.set_movement(0.0, 0.0)
	_step(1.5)
	_check("recovers when standing still", xh.spread_px < 12.0, str(xh.spread_px))


func _test_rifle() -> void:
	print("patrol rifle")
	var dummy := _spawn_dummy(Vector3(2.0, 0.0, -20.0))
	await _aim_at(dummy)
	_reset_counts()
	Weapons.equip("Patrol rifle")
	_check("HUD line 29 / 56", _spy.line == "Patrol rifle 29 / 56", _spy.line)
	_step(2.2)
	var pitch_before: float = _officer.kick_pitch
	_check("one shot", Weapons.fire())
	_check("29 -> 28", Weapons.get_ammo()["mag"] == 28)
	_check("single rifle hit downs the target", dummy.downed and _counts["lethal"] == 1, "hp=%.0f" % dummy.hp)
	_check("rifle kick applied", _officer.kick_pitch > pitch_before + 0.005, str(_officer.kick_pitch))
	_step(0.3)
	_check("rifle kick recovered", _officer.kick_pitch < 0.0005, str(_officer.kick_pitch))


func _test_shotgun() -> void:
	print("shotgun")
	Weapons.equip("Shotgun", true)
	_check("HUD line 6 / 18", _spy.line == "Shotgun 6 / 18", _spy.line)
	_step(1.0)
	var near := _spawn_dummy(Vector3(0.0, 0.0, -8.0))
	var far := _spawn_dummy(Vector3(-1.5, 0.0, -24.0))
	_reset_counts()
	_check("scripted shot at 8 m", Weapons.fire_at(near, "torso"))
	_check("close shotgun hit downs the target", near.downed, "hp=%.0f" % near.hp)
	_check("6 -> 5", Weapons.get_ammo()["mag"] == 5)
	_step(0.05)
	_check("pump interval blocks a normal click", not Weapons.fire())
	_step(1.0)
	Weapons.fire_at(far, "torso")
	_check("far shotgun hit is weaker (pattern widens, damage falls)", far.hp < 100.0 and not far.downed, "hp=%.0f" % far.hp)
	_step(1.0)
	# 70 px kick at the shotgun, 0.5 s recovery
	Weapons.fire_at(far, "torso")
	var expected := atan(70.0 / (540.0 / tan(deg_to_rad(_officer.camera.fov) * 0.5)))
	_check("shotgun kick about 70 px", absf(_officer.kick_pitch - expected) < expected * 0.1, "%.4f vs %.4f" % [_officer.kick_pitch, expected])
	_step(0.55)
	_check("shotgun kick recovered in 0.5 s", _officer.kick_pitch < 0.0005, str(_officer.kick_pitch))
	Weapons.set_ammo(4, 18)
	_step(1.0)
	_check("tube reload starts", Weapons.start_reload())
	_step(0.6)
	_check("one shell after 0.55 s", Weapons.get_ammo() == {"mag": 5, "reserve": 17}, str(Weapons.get_ammo()))
	_step(0.55)
	_check("second shell fills the tube, back to ready", Weapons.get_ammo() == {"mag": 6, "reserve": 16} \
			and Weapons.state == Weapons.State.READY, str(Weapons.get_ammo()))
	Weapons.set_ammo(3, 18)
	Weapons.start_reload()
	_step(0.6)
	_check("firing interrupts a shell reload", Weapons.fire_at(far, "torso") and Weapons.get_ammo()["mag"] == 3 \
			and Weapons.state == Weapons.State.READY, str(Weapons.get_ammo()))


func _test_holster_and_toggle() -> void:
	print("holster and key 5")
	Weapons.equip("pistol", true)
	_spy.clear_count = 0
	Weapons.holster()
	_check("holstering state", Weapons.state == Weapons.State.HOLSTERING)
	_check("HUD line stays during the lowering animation", _spy.line != "" and _spy.clear_count == 0, _spy.line)
	_check("cannot fire while holstering", not Weapons.fire())
	_step(0.55)
	_check("HUD line still open at 0.55 s", _spy.line != "", _spy.line)
	_step(0.1)
	_check("holstered after about 0.6 s", Weapons.state == Weapons.State.HOLSTERED and Weapons.equipped == &"")
	_check("HUD line cleared", _spy.line == "" and _spy.clear_count >= 1)
	_check("crosshair hidden", not Weapons.get_crosshair().active)
	Weapons.toggle_draw()
	_check("key 5 draws the selected weapon", Weapons.equipped == &"pistol")
	_step(0.5)
	Weapons.toggle_draw()
	_check("key 5 again lowers it", Weapons.state == Weapons.State.HOLSTERING)
	_step(0.7)
	_check("cycle changes the selection while holstered", Weapons.cycle_weapon(1) and Weapons.selected == &"rifle")
	Weapons.toggle_draw()
	_check("selection drawn", Weapons.equipped == &"rifle")
	_step(1.0)
	Weapons.equip("pistol", true)
	Weapons.holster_hud_time = 0.3
	Weapons.holster()
	_step(0.25)
	_check("HUD close time is independent of the animation: open at 0.25 s", _spy.line != "", _spy.line)
	_step(0.1)
	_check("... closed at 0.35 s while still lowering", _spy.line == "" and Weapons.state == Weapons.State.HOLSTERING)
	_step(0.3)
	_check("... and holstered at 0.65 s", Weapons.state == Weapons.State.HOLSTERED)
	Weapons.holster_hud_time = 0.6
	Weapons.equip("rifle", true)
	_check("redraw reopens the line", _spy.line.begins_with("Patrol rifle"), _spy.line)
	_step(1.0)
	_check("cycle while drawn switches weapon", Weapons.cycle_weapon(1) and Weapons.equipped == &"shotgun")
	_check("HUD follows the switch", _spy.line == "Shotgun 3 / 18" or _spy.line.begins_with("Shotgun"), _spy.line)
	Weapons.holster(true)


func _test_officer_signals() -> void:
	print("officer signal contract")
	var stub := OfficerStub.new()
	_range.add_child(stub)
	stub.position = Vector3(0.0, 0.0, 2.0)
	await _settle()
	Weapons.reset()
	Weapons.bind_officer(stub)
	Weapons.selected = &"pistol"
	_check("direct input off once an officer with signals is bound", not Weapons.direct_input)
	stub.draw_requested.emit()
	_check("draw_requested draws", Weapons.equipped == &"pistol")
	_step(0.5)
	stub.aim_changed.emit(true)
	_check("aim_changed(true) aims", Weapons.aiming)
	_reset_counts()
	stub.fire_requested.emit()
	_check("fire_requested fires from the officer muzzle", _counts["shot"] == 1 and _last_shot.get("weapon", &"") == &"pistol")
	_check("shot origin is the muzzle", (_last_shot["origin"] as Vector3).is_equal_approx(stub.get_muzzle_transform().origin))
	_check("kick reached the officer", stub.kick_peak > 0.0)
	Weapons.set_ammo(5, 34)
	_step(0.5)
	stub.reload_requested.emit()
	_check("reload_requested reloads", Weapons.state == Weapons.State.RELOADING)
	stub.aim_changed.emit(false)
	_check("aim_changed(false) lowers", not Weapons.aiming)
	Weapons.bind_officer(_officer)
	stub.queue_free()
	Weapons.reset()


func _test_dead_target_marker() -> void:
	print("hit marker on a downed target")
	Weapons.reset()
	Weapons.equip("Patrol rifle", true)
	var dummy := _spawn_dummy(Vector3(0.0, 0.0, -10.0))
	await _settle()
	var xh: Node = Weapons.get_crosshair()
	_check("first rifle shot downs the target", Weapons.fire_at(dummy, "torso") and dummy.downed)
	var hits_before: int = dummy.hits
	_step(0.5)
	_check("marker faded", xh.marker_alpha() == 0.0)
	_reset_counts()
	_check("second shot at the downed target fires", Weapons.fire_at(dummy, "torso"))
	_check("marker shows on the dead target (default)", xh.marker_alpha() > 0.9, str(xh.marker_alpha()))
	_check("no extra damage or downed event", dummy.hits == hits_before and _counts["downed"] == 0)
	_step(0.5)
	Weapons.hit_marker_on_dead = false
	Weapons.fire_at(dummy, "torso")
	_check("option off: no marker on a dead target", xh.marker_alpha() == 0.0, str(xh.marker_alpha()))
	Weapons.hit_marker_on_dead = true
	Weapons.reset()


func _test_scenario_replay() -> void:
	print("scenario hooks: fixed timeline")
	Weapons.reset()
	var suspect := _spawn_dummy(Vector3(0.0, 0.0, -12.0))
	await _settle()
	_check("equip instant + set_ammo", Weapons.equip("Pistol", true) and Weapons.state == Weapons.State.READY)
	Weapons.set_ammo(17, 34)
	_check("HUD 17 / 34", _spy.line == "Pistol 17 / 34", _spy.line)
	var shot_times := [3.6, 4.0, 4.4, 4.8, 5.0, 5.3, 5.6, 5.9, 6.1, 6.4, 6.7, 7.0]
	var t0 := Weapons.time
	var ok := true
	var detail := ""
	for i in shot_times.size():
		while Weapons.time < t0 + float(shot_times[i]) - 3.6:
			Weapons.tick(1.0 / 60.0)
		var fired := Weapons.fire_at(suspect, "torso")
		var mag: int = Weapons.get_ammo()["mag"]
		if not fired or mag != 16 - i:
			ok = false
			detail += " shot %d mag=%d" % [i + 1, mag]
	_check("12 scripted shots, 17 -> 5 on the recorded times", ok, detail)
	_check("HUD 5 / 34 after the burst", _spy.line == "Pistol 5 / 34", _spy.line)
	var miss_before: int = _counts["hit"]
	Weapons.set_ammo(10, 34)
	_step(0.3)
	var shots_before: int = _counts["shot"]
	_check("miss shot still fires", Weapons.fire_at(suspect, "torso", false))
	_check("miss registers no hit", _counts["hit"] == miss_before and _counts["shot"] == shots_before + 1)
	Weapons.equip("Patrol rifle", true)
	var runner := _spawn_dummy(Vector3(3.0, 0.0, -30.0))
	await _settle()
	_check("rifle replay: 29 -> 28 and downs the runner", Weapons.fire_at(runner, "torso") and Weapons.get_ammo()["mag"] == 28 and runner.downed)
	Weapons.equip("Shotgun", true)
	var tgt := _spawn_dummy(Vector3(-2.0, 0.0, -9.0))
	await _settle()
	Weapons.fire_at(tgt, "torso")
	Weapons.tick(1.36)
	Weapons.fire_at(tgt, "torso")
	_check("shotgun replay: 6 -> 4", Weapons.get_ammo()["mag"] == 4, str(Weapons.get_ammo()))
	Weapons.reset()
