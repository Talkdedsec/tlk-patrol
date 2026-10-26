extends Node3D
## Pursuit / traffic test scene. Real World + Vehicles when they exist, placeholders with --fallback 1.
## Args (after --): --auto 1 (scripted run with checks, then quits)  --speed N (time scale)  --fallback 1
##   --hold <stage> (stop the script at pursuit|denied|authorized|hint|spun|bailed|tased|cuffing|cuffed, for screenshots)
##   --traffic N (ambient cars)
## Manual play: R request PIT, B backup, C join, Z call off, E interact, LMB Taser; arrow keys drive the player car.

const Adapters := preload("res://scripts/pursuit/adapters.gd")
const TestRoad := preload("res://scripts/pursuit/test_road.gd")
const ChaseDriver := preload("res://scripts/pursuit/chase_driver.gd")
const Pit := preload("res://scripts/pursuit/pit.gd")
const Registry := preload("res://scripts/traffic/registry.gd")
const HudScript := preload("res://scripts/hud/hud.gd")

var args := {}
var player: Node3D
var suspect_car: Node3D
var officer: Node3D
var chaser: ChaseDriver
var cam: Camera3D
var _checks := 0
var _fails := 0
var _bailed := 0
var _cuffed := 0
var _processed := 0
var _ended: Array[StringName] = []
var _hint_seen := false
var _officer_follow := false
var _foot_cam := false
var _walk_t := 0.0
var _manual := false
var _simt := 0.0
var _start_origin := Vector3.ZERO
var _dbg_t := 0.0


func _ready() -> void:
	args = _parse(OS.get_cmdline_user_args())
	if args.has("seed"):
		ChaseDriver.seed_base = int(args["seed"])
		seed(int(args["seed"]))
	if args.has("speed"):
		Engine.time_scale = float(args["speed"])
		Engine.max_physics_steps_per_frame = 64
	var fallback := String(args.get("fallback", "0")) == "1"
	var start := Transform3D.IDENTITY
	Adapters.spawn_parent = self
	if fallback:
		Adapters.force_placeholders = true
		_environment()
		Adapters.fallback_graph = TestRoad.build(self)
		start = Transform3D(Basis.looking_at(Vector3.RIGHT, Vector3.UP), Vector3(-82.0, 0.35, -97.8))
	else:
		World.build(self)
		start = World.spawn_point(&"hoover_st")
		start.origin.y += 0.3
	_start_origin = start.origin
	add_child(HudScript.new())
	Pursuit.bind_ui(self)
	player = Adapters.spawn_vehicle(&"patrol_suv", start, {"team": &"police", "number": "12"})
	player.add_to_group("player_vehicle")
	var s_xf := start
	s_xf.origin = start * Vector3(0.0, 0.0, -14.3)
	suspect_car = Adapters.spawn_vehicle(&"ranger_suv_wood", s_xf, {"plate": "TAY-6023", "team": &"suspect"})
	var dir := -start.basis.z
	Adapters.set_velocity(player, dir * 9.0)
	Adapters.set_velocity(suspect_car, dir * 9.0)
	if String(args.get("debug", "0")) == "5" and suspect_car.has_signal("collided"):
		suspect_car.connect("collided", func(other: Node, mph: float) -> void:
			print("[DBG5] suspect collided with %s (%s) at %.0f mph, pos=%s" % [other.name, other.get_path(), mph, str(suspect_car.global_position)]))
		player.connect("collided", func(other: Node, mph: float) -> void:
			print("[DBG5] player collided with %s (%s) at %.0f mph, pos=%s" % [other.name, other.get_path(), mph, str(player.global_position)]))
	var car: RefCounted = Traffic.adopt(suspect_car)
	if car != null:
		car.cruise_factor = 0.8
	chaser = ChaseDriver.new()
	chaser.attach(player, Adapters.graph())
	chaser.target = suspect_car
	chaser.target_driver = car
	Traffic.focus_node = player
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 3000.0
	add_child(cam)
	cam.make_current()
	Adapters.camera_override = cam
	_manual = not (String(args.get("auto", "0")) == "1" or String(args.get("soak", "0")) == "1" or String(args.get("braketest", "0")) == "1")
	Pursuit.suspect_bailed.connect(_on_bailed)
	Pursuit.suspect_cuffed.connect(func(_n: Node3D) -> void: _cuffed += 1)
	Pursuit.process_requested.connect(func(_n: Node3D, _c: Array) -> void: _processed += 1)
	Pursuit.ended.connect(func(r: StringName) -> void: _ended.append(r))
	Pursuit.pit_succeeded.connect(func(_t: Node3D) -> void:
		chaser.gap = 6.5
		chaser.mode = ChaseDriver.Mode.FOLLOW)
	if args.has("traffic"):
		Traffic.spawn_ambient(int(args["traffic"]))
	if String(args.get("nobot", "0")) == "1":
		Pursuit.lost_enabled = false
	if String(args.get("braketest", "0")) == "1":
		_run_braketest()
	elif String(args.get("soak", "0")) == "1":
		_run_soak()
	elif not _manual:
		_run_auto()


func _environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("05070d")
	sky_material.sky_horizon_color = Color("141a26")
	sky_material.ground_horizon_color = Color("141a26")
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 0.35
	add_child(sun)


func _physics_process(dt: float) -> void:
	_simt += dt
	if String(args.get("braketest", "0")) == "1" or String(args.get("nobot", "0")) == "1":
		pass
	elif not _manual:
		if Pursuit.driver != null:
			chaser.target_driver = Pursuit.driver
		chaser.update(dt)
	else:
		_manual_drive()
	if String(args.get("debug", "0")) == "1" and Pursuit.state == Pursuit.State.PURSUIT and chaser.mode == ChaseDriver.Mode.PIT:
		_dbg_t -= dt
		if _dbg_t <= 0.0:
			_dbg_t = 0.5
			var loc := suspect_car.global_transform.affine_inverse() * player.global_position
			var ci := Pit.contact(player, suspect_car)
			print("[DBG] t=%.1f local=(%.2f, %.2f) dist=%.1fft pv=%.0f sv=%.0f contact=%s ct=%.2f" % [_simt, loc.x, loc.z, Pursuit.distance_ft, Adapters.speed_mph(player), Adapters.speed_mph(suspect_car), str(ci), Pursuit.pit.contact_time])
	if String(args.get("debug", "0")) == "2" and Pursuit.state == Pursuit.State.PURSUIT and Pursuit.driver != null:
		_dbg_t -= dt
		if _dbg_t <= 0.0:
			_dbg_t = 1.0
			var d: Object = Pursuit.driver
			var rt: RefCounted = d.get("route")
			var fwd := -suspect_car.global_transform.basis.z
			var nxt := Registry.nearest_ahead(suspect_car, fwd, 60.0, 0.0, 2.1)
			print("[DBG2] t=%.0f sv=%.0f vt=%.1f edge=%s s=%.0f/%.0f legs=%d lastd=%.1f esc=%.2f ovr=%.0f curve=%.1f ahead=%s pos=(%.0f,%.0f)" % [_simt, Adapters.speed_mph(suspect_car), d.get("debug_target_speed"), String(d.call("current_edge").get("name", "?")), float(d.get("s_now")), rt.call("total"), rt.get("legs").size(), rt.get("last_dist"), d.get("escalation"), d.get("speed_override_mph"), rt.call("curve_limit", float(d.get("s_now")), 120.0, 7.5, 8.0), str(nxt.found), suspect_car.global_position.x, suspect_car.global_position.z])
	if String(args.get("debug", "0")) == "3":
		_dbg_t -= dt
		if _dbg_t <= 0.0:
			_dbg_t = 2.0
			var drv: Object = Pursuit.driver
			var vt3 := float(drv.get("debug_target_speed")) if drv != null else -1.0
			var en: String = String(drv.call("current_edge").get("name", "?")) if drv != null else "-"
			print("[DBG3] t=%.0f P=(%.0f,%.0f) pv=%.0f pvt=%.1f pedge=%s S=(%.0f,%.0f) sv=%.0f vt=%.1f edge=%s dist=%.0fft st=%s" % [_simt, player.global_position.x, player.global_position.z, Adapters.speed_mph(player), chaser.debug_target_speed, String(chaser.current_edge().get("name", "?")), suspect_car.global_position.x, suspect_car.global_position.z, Adapters.speed_mph(suspect_car), vt3, en, Pursuit.distance_ft, Pursuit.State.keys()[Pursuit.state]])
	if String(args.get("debug", "0")) == "6" and Pursuit.driver != null and Pursuit.driver.route != null and (Pursuit.driver.route.last_dist > 1.0 or (_simt > float(args.get("dbg-from", "1e9")) and _simt < float(args.get("dbg-to", "0")))):
		_dbg_t -= dt
		if _dbg_t <= 0.0:
			_dbg_t = 0.25
			var dr = Pursuit.driver
			var fw := -suspect_car.global_transform.basis.z
			var ah := Registry.nearest_ahead(suspect_car, fw, 90.0, 0.0, 3.0)
			print("[DBG6] ahead=%s gap=%.1f kind=%s" % [str(ah.node.name) if ah.node != null else "-", float(ah.gap), str(Registry.kind_of(ah.node)) if ah.node != null else "-"])
			print("[DBG6] t=%.1f pos=(%.1f,%.1f) lastd=%.1f sv=%.1f vt=%.1f shift=%.1f edge=%s s=%.0f fwd=(%.2f,%.2f) thr=%.2f brk=%.2f tgt=%s" % [_simt, suspect_car.global_position.x, suspect_car.global_position.z, dr.route.last_dist, Adapters.speed_mph(suspect_car), dr.debug_target_speed, dr.shift, String(dr.current_edge().get("name", "?")), dr.s_now, fw.x, fw.z, dr.debug_thr, dr.debug_brk, str(dr._last_steer_target)])
	var hint: String = Pursuit.banner.call("hint_text") if Pursuit.banner != null else ""
	if hint != "":
		_hint_seen = true
	if _officer_follow and officer != null and is_instance_valid(officer) and Pursuit.suspect != null and is_instance_valid(Pursuit.suspect):
		_walk_t -= dt
		if _walk_t <= 0.0:
			_walk_t = 0.25
			var to_s := Pursuit.suspect.global_position - officer.global_position
			to_s.y = 0.0
			if to_s.length() > 2.2:
				officer.call("walk_to", Pursuit.suspect.global_position, 4.57)
			else:
				officer.call("stop")


func _process(_dt: float) -> void:
	if cam == null:
		return
	if _foot_cam and officer != null and is_instance_valid(officer) and Pursuit.suspect != null and is_instance_valid(Pursuit.suspect):
		var o := officer.global_position
		var s := Pursuit.suspect.global_position
		var back := (o - s)
		back.y = 0.0
		back = back.normalized()
		cam.global_position = cam.global_position.lerp(o + back * 3.2 + Vector3(0, 2.0, 0), 0.25)
		cam.look_at(s + Vector3(0, 1.0, 0), Vector3.UP)
		return
	if player == null or not is_instance_valid(player):
		return
	var target_pos := player.global_position + player.global_transform.basis.z * 10.0 + Vector3(0, 4.2, 0)
	cam.global_position = cam.global_position.lerp(target_pos, 0.18)
	cam.look_at(player.global_position + Vector3(0, 1.2, 0), Vector3.UP)


func _manual_drive() -> void:
	var t := Input.get_axis("ui_down", "ui_up")
	var s := Input.get_axis("ui_right", "ui_left")
	Adapters.drive(player, maxf(t, 0.0), maxf(-t, 0.0), s)


func _on_bailed(_npc: Node3D) -> void:
	_bailed += 1
	var o_xf := Adapters.driver_exit_transform(player)
	var away := o_xf.origin - _npc.global_position
	away.y = 0.0
	if away.length() > 8.5:   # the chasing car may be far behind a sliding suspect car: the officer starts about 8 m from the runner
		o_xf.origin = _npc.global_position + away.normalized() * 8.5
	officer = Adapters.spawn_npc(o_xf, "police")
	Pursuit.officer = officer
	_officer_follow = true
	_foot_cam = true


# --- scripted run ------------------------------------------------------------------------------------------------

func _sim_t() -> float:
	return _simt


func _wait(seconds: float) -> void:
	var end := _sim_t() + seconds
	while _sim_t() < end:
		await get_tree().physics_frame


func _wait_for(cond: Callable, timeout: float) -> bool:
	var end := _sim_t() + timeout
	while _sim_t() < end:
		if cond.call():
			return true
		await get_tree().physics_frame
	return bool(cond.call())


func _on_straight() -> bool:
	var d: Object = Pursuit.driver
	if d == null or d.get("route") == null:
		return false
	var route: RefCounted = d.get("route")
	var s_now: float = d.get("s_now")
	return float(route.call("remaining", s_now)) > 200.0 and float(route.call("curve_limit", s_now, 170.0, 7.5, 8.0)) > 24.0


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("[TEST] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])


func _radio_has(fragment: String) -> bool:
	for l in Dispatch.lines:
		if String(l).contains(fragment):
			return true
	return false


func _stage(stage_name: String) -> void:
	print("[STAGE] %s  t=%.1f  %s" % [stage_name, _sim_t(), str(Pursuit.snapshot())])
	if String(args.get("hold", "")) == stage_name:
		await get_tree().create_timer(100000.0).timeout


func _run_auto() -> void:
	await _wait(1.0)
	Adapters.lights_override = 1
	GameState.set_duty_status("Available")
	Pursuit.busy_on_start = false
	Pursuit.started.connect(func(_t: Node3D) -> void: GameState.set_duty_status("Busy"))   # what scripts/game/duty_flow.gd does
	Pursuit.alpr_hit(suspect_car, "TAY-6023", "registered owner has a warrant")
	_check("alpr toast", Pursuit.banner.call("toast_text") == "ALPR HIT   TAY-6023   REGISTERED OWNER HAS A WARRANT")
	var ok := await _wait_for(func() -> bool: return Pursuit.state == Pursuit.State.PURSUIT, 6.0)
	_check("auto start when lights go on", ok)
	if not ok:
		_finish()
		return
	var snap := Pursuit.snapshot()
	_check("fleeing toast", snap.toast == "The driver is fleeing!", str(snap.toast))
	_check("busy_on_start = false keeps Available", GameState.duty_status == "Available", GameState.duty_status)
	_check("pursuit line", String(snap.line).begins_with("PURSUIT   ") and String(snap.line).ends_with("   R request PIT"), String(snap.line))
	_check("radio 10-80", _radio_has("10-80, vehicle failing to yield"))
	await _stage("pursuit")
	Pursuit.driver.set("speed_override_mph", 28.0)
	await _wait(2.0)
	# scripted PIT refusal
	Pursuit.set_pit_decision(false, 1.0)
	_check("request pit", Pursuit.request_pit())
	await get_tree().physics_frame
	_check("pit requested", Pursuit.pit_state() == Pursuit.PitState.REQUESTED and String(Pursuit.snapshot().line).ends_with("PIT requested"))
	_check("radio request", _radio_has("Requesting permission to PIT"))
	await _wait_for(func() -> bool: return Pursuit.pit_state() == Pursuit.PitState.DENIED, 3.0)
	_check("pit denied", String(Pursuit.snapshot().line).ends_with("PIT denied: speeds are too high"), String(Pursuit.snapshot().line))
	_check("radio denied", _radio_has("speeds are too high"))
	_check("no request during cooldown", not Pursuit.request_pit())
	await _stage("denied")
	await _wait_for(func() -> bool: return Pursuit.pit_state() == Pursuit.PitState.IDLE, 22.0)
	_check("cooldown returns to R request PIT", String(Pursuit.snapshot().line).ends_with("R request PIT"), String(Pursuit.snapshot().line))
	_check("decision rule", Pit.decide(19.0) and Pit.decide(Pit.SPEED_LIMIT_MPH) and not Pit.decide(72.0) and not Pit.decide(87.0))
	# natural decision at about 28 mph
	_check("request pit again", Pursuit.request_pit())
	var auth := await _wait_for(func() -> bool: return Pursuit.pit_state() == Pursuit.PitState.AUTHORIZED, 9.0)
	_check("pit authorized at low speed", auth, "player mph=%.0f" % Adapters.speed_mph(player))
	_check("authorized line", String(Pursuit.snapshot().line).ends_with("PIT authorized"))
	await _stage("authorized")
	# PIT approach: wait for a long straight (the suspect escalates and heads for the fast roads)
	Pursuit.bail_delay = 10.75
	Pursuit.driver.set("speed_override_mph", 50.0)
	await _wait(6.0)
	var straight := await _wait_for(_on_straight, 90.0)
	_check("suspect reaches a long straight", straight)
	chaser.pit_side = 1.0
	chaser.mode = ChaseDriver.Mode.PIT
	var hint := await _wait_for(func() -> bool: return _hint_seen, 40.0)
	_check("PIT position hint shown when close", hint)
	await _stage("hint")
	var spun := await _wait_for(func() -> bool: return Pursuit.state == Pursuit.State.SUSPECT_DOWN, 45.0)
	_check("PIT spins the car out", spun, str(Pursuit.snapshot()))
	if not spun and String(args.get("force-pit", "0")) == "1":
		# real-physics runs: the bot may have fallen behind; put the player car behind the suspect and exercise the rest of the flow
		var back_xf := suspect_car.global_transform
		back_xf.origin = suspect_car.global_transform * Vector3(0.0, 0.1, 9.0)
		Adapters.teleport(player, back_xf)
		Adapters.set_velocity(player, Adapters.velocity(suspect_car))
		await _wait(0.2)
		Pursuit.force_pit_success(1.0)
		spun = Pursuit.state == Pursuit.State.SUSPECT_DOWN
	if not spun:
		_finish()
		return
	_check("spun-out toast", Pursuit.banner.call("toast_text") == "PIT: The car spun out.")
	await _stage("spun")
	var spun_at := _simt
	var score_before := GameState.score
	var bailed := await _wait_for(func() -> bool: return Pursuit.state == Pursuit.State.BAILED, 25.0)
	_check("suspect bails out", bailed)
	if not bailed:
		_finish()
		return
	await get_tree().physics_frame
	snap = Pursuit.snapshot()
	_check("bail toast", snap.toast == "They bailed out of the car! Catch them.")
	_check("bail_delay: bail 10.75 s after the spin-out", _simt - spun_at >= 10.7 and _simt - spun_at < 14.5, "%.2f s" % (_simt - spun_at))
	if suspect_car.get("scuffs") != null:
		_check("PIT contact used pit_scuff (no impulse)", int(suspect_car.get("scuffs")) > 0)
	_check("chase nearby line", String(snap.chase).begins_with("Chase nearby, ") and String(snap.chase).ends_with("   C join   Z call off"), String(snap.chase))
	_check("suspect_bailed signal", _bailed == 1)
	await _stage("bailed")
	await _wait(1.3)
	_check("score +20", GameState.score == score_before + 20, "%d -> %d" % [score_before, GameState.score])
	await _wait_for(func() -> bool: return Pursuit.foot != null and bool(Pursuit.foot.get("taser_out")), 5.0)
	_check("taser line", Pursuit.banner.call("taser_text").begins_with("Taser out   LMB use"), String(Pursuit.banner.call("taser_text")))
	Pursuit.join_chase()
	await get_tree().physics_frame
	_check("join -> FOOT CHASE gauge", Pursuit.state == Pursuit.State.FOOT_CHASE and String(Pursuit.banner.call("foot_text")).begins_with("FOOT CHASE   "), String(Pursuit.banner.call("foot_text")))
	var hit := false
	for _i in 12:
		await _wait(0.4)
		if Pursuit.taser_fire():
			hit = true
			break
		if String(args.get("debug", "0")) == "4":
			var pp: Vector3 = Pursuit.player_position()
			var cf := -cam.global_transform.basis.z
			print("[DBG4] taser miss: info=%s officer=%s suspect=%s cam=%s camfwd=%s phase=%s out=%s" % [str(Pursuit.foot.call("_target_info", pp)), str(pp), str(Pursuit.suspect.global_position), str(cam.global_position), str(cf), str(Pursuit.foot.get("phase")), str(Pursuit.foot.get("taser_out"))])
	_check("taser hits", hit)
	_check("covered toast", String(Pursuit.banner.call("toast_text")).contains("has them covered. E to deal with them yourself, or"), String(Pursuit.banner.call("toast_text")))
	_check("E Cuff prompt", Pursuit.banner.call("prompt_text") == "E  Cuff")
	_check("state subdued", Pursuit.state == Pursuit.State.SUBDUED)
	await _stage("tased")
	await _wait_for(func() -> bool: return officer.global_position.distance_to(Pursuit.suspect.global_position) < 3.0, 6.0)
	_check("interact starts cuffing", Pursuit.interact())
	_check("cuffing toast", Pursuit.banner.call("toast_text") == "Cuffing..." and Pursuit.state == Pursuit.State.CUFFING)
	await _stage("cuffing")
	await _wait_for(func() -> bool: return Pursuit.state == Pursuit.State.CUFFED, 6.0)
	_check("suspect cuffed", Pursuit.state == Pursuit.State.CUFFED and _cuffed == 1)
	_check("cuffed toast", Pursuit.banner.call("toast_text") == "Suspect cuffed. E to process them and book the charges.")
	_check("process prompt", Pursuit.banner.call("prompt_text") == "E  Process the suspect")
	await _stage("cuffed")
	_check("interact processes", Pursuit.interact())
	_check("process signal + end", _processed == 1 and Pursuit.state == Pursuit.State.IDLE and _ended.has(&"processed"), str(_ended))
	await _wait(2.0)
	for frag in ["Good PIT, vehicle spun out", "foot pursuit", "10-97", "Code four; suspect's down", "10-15"]:
		_check("radio: " + frag, _radio_has(frag))
	await _extra_checks()
	_finish()


## begin_foot_chase (no car, units == null), Traffic.clear / recycle_far_cars sparing held and pulled-over cars.
func _extra_checks() -> void:
	# --- begin_foot_chase -------------------------------------------------------------------------------------------------
	var runner := Adapters.spawn_npc(Transform3D(Basis.IDENTITY, player.global_position + Vector3(12, 0.1, 0)), "civilian")
	runner.call("flee_from", player.global_position, 60.0)
	_check("begin_foot_chase refused while idle=false", not Pursuit.begin_foot_chase(null))
	var began := Pursuit.begin_foot_chase(runner, {"plate": "XYZ-1234", "cover": "7-Sam-21", "evidence": ["Fleeing a police officer on foot"]})
	_check("begin_foot_chase starts the foot phase", began and Pursuit.state == Pursuit.State.BAILED and Pursuit.units == null)
	_check("begin_foot_chase refused while active", not Pursuit.begin_foot_chase(runner))
	var before := Dispatch.lines.size()
	await _wait(1.0)
	var declared := false
	for i in range(before, Dispatch.lines.size()):
		if String(Dispatch.lines[i]).contains("foot pursuit"):
			declared = true
	_check("foot pursuit declared without AI units (no crash)", declared)
	_check("evidence from options", Pursuit.evidence_charges.size() == 1)
	Pursuit.call_off()
	_check("call_off ends the started foot chase", Pursuit.state == Pursuit.State.IDLE and _ended.has(&"called_off"))
	# --- Traffic.clear / recycle_far_cars ----------------------------------------------------------------------------------
	# the traffic checks use a fixed probe on the start road as the focus (the player car may sit anywhere after the chase)
	var probe := Node3D.new()
	add_child(probe)
	probe.global_position = _start_origin
	Traffic.focus_node = probe
	Traffic.clear()
	var made := Traffic.spawn_ambient(8)
	_check("ambient cars spawned", made >= 4, "n=%d" % made)
	var owned: Array = []
	for c in Traffic.cars:
		if bool(c.owned):
			owned.append(c)
	if owned.size() >= 3:
		var held: Node3D = owned[0].vehicle
		var pulled: Node3D = owned[1].vehicle
		var plain: Node3D = owned[2].vehicle
		Traffic.hold_vehicle(held)
		Traffic.pull_over(pulled)
		_check("held and pulled-over cars are protected", Traffic.is_protected(held) and Traffic.is_protected(pulled) and not Traffic.is_protected(plain))
		var held_pos := held.global_position
		var pulled_pos := pulled.global_position
		Traffic.despawn_distance = 20.0   # nearly every car counts as far
		if String(args.get("debug", "0")) == "7":
			var spots := 0
			for _i in 40:
				if not Traffic._find_spot(player.global_position, true).is_empty():
					spots += 1
			print("[DBG7] player=%s spots=%d/40" % [str(player.global_position), spots])
			for c in Traffic.cars:
				var cv: Node3D = c.vehicle
				print("[DBG7] car owned=%s prot=%s d=%.0f inview=%s" % [str(c.owned), str(Traffic._is_protected(c)), cv.global_position.distance_to(player.global_position), str(Traffic._in_view(cv.global_position, cv.global_position.distance_to(player.global_position)))])
		var moved := Traffic.recycle_far_cars(20, 20.0)
		_check("recycle_far_cars moves cars instead of freeing them", moved >= 1 and Traffic.recycled >= 1 and is_instance_valid(plain), "moved=%d" % moved)
		_check("recycle spares held and pulled-over cars", held.global_position.is_equal_approx(held_pos) and pulled.global_position.distance_to(pulled_pos) < 30.0)
		Traffic.clear()
		_check("clear() keeps held, pulled-over and adopted cars", is_instance_valid(held) and is_instance_valid(pulled) and is_instance_valid(suspect_car) and Traffic.cars.size() >= 2, "left=%d" % Traffic.cars.size())
		Traffic.release_vehicle(held)
		_check("release_vehicle lifts the protection", not Traffic.is_protected(held))
		Traffic.despawn_distance = 340.0
	else:
		_check("enough ambient cars for the clear/recycle checks", false, "owned=%d" % owned.size())
	_check("traffic registry", Traffic.cars.size() >= 0)


## Long run without PIT: the suspect drives the roads for N seconds, the bot follows. Prints blocked-time statistics.
func _run_soak() -> void:
	await _wait(1.0)
	Adapters.lights_override = 1
	Pursuit.alpr_hit(suspect_car, "TAY-6023", "registered owner has a warrant")
	await _wait_for(func() -> bool: return Pursuit.state == Pursuit.State.PURSUIT, 6.0)
	var total := float(args.get("soak-seconds", "150"))
	var start_pos := suspect_car.global_position
	var travelled := 0.0
	var last := start_pos
	var top := 0.0
	var end_t := _sim_t() + total
	while _sim_t() < end_t and Pursuit.state == Pursuit.State.PURSUIT:
		await get_tree().physics_frame
		travelled += suspect_car.global_position.distance_to(last)
		last = suspect_car.global_position
		var spd := Adapters.speed_mph(suspect_car)
		if spd > 120.0 and top <= 120.0:
			print("[SOAK] overspeed %.0f mph at t=%.0f pos=%s" % [spd, _simt, str(suspect_car.global_position)])
		top = maxf(top, spd)
	var d: Object = Pursuit.driver
	print("[SOAK] sim=%.0fs state=%s suspect travelled=%.0fm top=%.0fmph recoveries=%d blocked=%.1fs | bot recoveries=%d blocked=%.1fs dist=%.0fft" % [
		total, Pursuit.State.keys()[Pursuit.state], travelled, top, int(d.get("recoveries")) if d != null else -1, float(d.get("stuck_time")) if d != null else -1.0,
		chaser.recoveries, chaser.stuck_time, Pursuit.distance_ft])
	if d != null:
		for r in d.get("recovery_log"):
			print("[SOAK] recovery at %s edge=%s s=%.0f left=%.0f nodes30=%d" % [str(r.pos), r.edge, r.s, r.left, r.nodes])
	get_tree().quit()


## Measures the real Vehicle's braking in a straight line (AI planning assumes a_brake of 4.5-5 m/s^2).
func _run_braketest() -> void:
	Traffic.release(suspect_car)
	await _wait(0.5)
	for car in [player, suspect_car]:
		for pedal in [1.0, 0.5]:
			Adapters.teleport(car, Transform3D(Basis.looking_at(Vector3(0, 0, -1)), Vector3(3.5, 0.4, -60.0)))
			Adapters.set_velocity(car, Vector3(0, 0, -17.0))
			await _wait(0.3)
			var mode := String(args.get("brakemode", "controls"))
			var v0 := Adapters.speed_ms(car)
			var line := "[BRAKE] %s pedal=%.1f v0=%.1f m/s:" % [car.name, pedal, v0]
			for i in 8:
				if mode == "steer":
					Adapters.drive(car, 0.0, pedal, 0.0, car.global_position + Vector3(0, 0, -30))
				else:
					Adapters.drive(car, 0.0, pedal, 0.0)
				await _wait(0.5)
				line += " %.1f" % Adapters.speed_ms(car)
			print(line)
	get_tree().quit()


func _finish() -> void:
	print("[RESULT] %s  %d/%d checks passed" % ["PASS" if _fails == 0 else "FAIL", _checks - _fails, _checks])
	if String(args.get("hold", "")) == "":
		get_tree().quit()


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
