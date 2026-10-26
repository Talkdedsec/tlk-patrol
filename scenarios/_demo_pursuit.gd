extends "res://scripts/dev/scenario_base.gd"
## ALPR hit -> flight -> PIT -> bail -> foot chase -> Taser -> cuffs -> booking, played through the game's own loop: a stolen vehicle
## call is accepted, the plate reader finds the parked car, the lights come on and it drives off, PIT is requested (R), authorised
## and used, the driver bails, the officer gets out and chases on foot, tases him (LMB), cuffs (E), processes (E) and books.
## The bot only replaces the hands (ChaseDriver follows the car; the runner is slowed a little so the foot chase can close).
## Record: araclar/kayit.sh _demo_pursuit   (about 100 s; shots go to the runner's --out folder)

const DemoTools := preload("res://scripts/game/demo_tools.gd")
const PerfProbe := preload("res://scripts/game/perf_probe.gd")
const ChaseDriver := preload("res://scripts/pursuit/chase_driver.gd")
const AutoDrive := preload("res://scripts/game/auto_drive.gd")

var t: Node


func _init() -> void:
	duration = 300.0     # safety: the script ends the run itself


func setup(main_scene: Node) -> void:
	super(main_scene)
	main.add_child(PerfProbe.new())
	t = DemoTools.new()
	t.main = main
	t.scenario_name = "_demo_pursuit"
	main.add_child(t)
	main.hooks.set_calls_enabled(false)
	main.hooks.alpr_enabled = true
	Calls.ambient_enabled = false
	Calls.auto_offers = false
	TrafficStop.auto_detect = false
	Pursuit.lost_enabled = false
	at(0.3, func() -> void: _run())


func _run() -> void:
	var seat: Node = main.seat
	var car: Vehicle = main.patrol_vehicle
	var director: Node = main.hooks.director
	seat.scripted_drive = true
	await t.wait(1.0)

	# --- call and approach ------------------------------------------------------------------------------------------------
	director.offer(&"stolen_vehicle", {"position": Vector3(0.0, 0.0, -300.0)})
	await t.wait(5.0)
	await t.snap("01_offer")
	Calls.respond()                                          # Y
	seat.enter(car)                                          # E: the officer walks to the door and gets in
	await t.until(func() -> bool: return seat.is_driving(), 8.0, "officer in the car")
	await t.wait(0.8)
	var road := AutoDrive.new()                              # straight up Hoover St until the BOLO car is placed (230 m)
	main.add_child(road)
	road.follow_straight(car, 500.0, 34.0)
	await t.until(func() -> bool: return director.scene != null and director.scene.spawned, 40.0, "BOLO car placed")
	road.stop(0.0)
	var bolo: Vehicle = director.scene.car
	t.follow_car(bolo, 12.0, 40.0)                           # no lights, no siren while approaching (04 report)
	await t.until(func() -> bool: return Pursuit.snapshot()["toast"].begins_with("ALPR HIT"), 40.0, "ALPR hit")
	await t.wait(0.6)
	await t.snap("02_alpr_hit")

	# --- lights on close behind it: the car runs ---------------------------------------------------------------------------
	await t.until(func() -> bool: return t.distance_to_car(bolo) < 24.0, 20.0, "close behind the car")
	Els.set_stage(3)
	Els.set_siren(&"yelp")
	await t.until(func() -> bool: return Pursuit.state == Pursuit.State.PURSUIT, 8.0, "pursuit start")
	t.stop_follow(0.0)
	t.chase_car(16.0)
	Pursuit.suspect_bailed.connect(func(_npc: Node3D) -> void: t.stop_chase_car(), CONNECT_ONE_SHOT)
	await t.wait(2.0)
	await t.snap("03_fleeing")

	# --- the chase, PIT --------------------------------------------------------------------------------------------------------
	await t.wait(9.0)
	Pursuit.set_pit_decision(true, 5.0)
	Pursuit.request_pit()                                    # R
	await t.wait(1.0)
	await t.snap("04_pit_requested")
	await t.until(func() -> bool: return Pursuit.pit_state() == Pursuit.PitState.AUTHORIZED, 10.0, "PIT authorised")
	t.chaser.mode = ChaseDriver.Mode.PIT
	await t.wait(1.0)
	await t.snap("05_pit_authorized")
	var spun: bool = await t.until(func() -> bool: return Pursuit.state == Pursuit.State.SUSPECT_DOWN, 20.0, "natural PIT contact")
	if not spun:
		t.note("no natural contact: the PIT is applied directly")
		Pursuit.force_pit_success(1.0)
	t.chaser.gap = 9.0
	t.chaser.mode = ChaseDriver.Mode.FOLLOW
	await t.wait(1.5)
	await t.snap("06_spun_out")

	# --- bail, foot chase ------------------------------------------------------------------------------------------------------
	await t.until(func() -> bool: return Pursuit.state == Pursuit.State.BAILED, 25.0, "driver bails")
	await t.snap("07_bailed")
	await t.until(func() -> bool: return seat.is_on_foot(), 12.0, "officer out of the car")
	var suspect: Node3D = Pursuit.suspect
	t.tired = suspect                                        # the runner is slower than the officer after a while
	t.run_to = suspect
	t.aim_target = suspect
	await t.wait(1.5)
	Pursuit.join_chase()                                     # C
	await t.snap("08_foot_chase")
	var tased := false
	var left := 45.0
	var log_at := 0.0
	while not tased and left > 0.0 and Pursuit.state != Pursuit.State.IDLE:
		await t.wait(0.4)
		left -= 0.4
		log_at -= 0.4
		if log_at <= 0.0:
			log_at = 3.0
			t.note("foot chase: %.1f m behind, suspect %s (%s), officer %s" % [t.distance_to(suspect), str(suspect.global_position.snapped(Vector3.ONE * 0.1)), suspect.get("state"), str(main.player.global_position.snapped(Vector3.ONE * 0.1))])
		if Pursuit.state == Pursuit.State.FOOT_CHASE and t.distance_to(suspect) < 10.0:
			tased = Pursuit.taser_fire()                     # LMB
	if not tased:
		t.note("the Taser never found him: the suspect is taken down directly")
		Pursuit.foot.downed_externally()
	await t.wait(0.8)
	await t.snap("09_tased")

	# --- cuffs, process, booking -----------------------------------------------------------------------------------------------
	t.aim_target = null
	t.tired = null
	t.run_to = null
	main.player.walk_to(suspect.global_position, true)           # he is lying a few metres away: straight to him
	var reached: bool = await t.until(func() -> bool: return t.distance_to(suspect) < 2.0, 8.0, "at the suspect")
	if not reached:
		t.note("the officer is stuck: he is put next to the suspect")
		main.player.global_position = suspect.global_position + Vector3(1.6, 0.05, 1.6)
	main.player.stop_scripted()
	await t.wait(0.8)
	for attempt in 3:                                        # E: cuffs (a cuff that was interrupted is started again)
		if Pursuit.state == Pursuit.State.CUFFED:
			break
		if t.distance_to(suspect) > 4.0:
			main.player.global_position = suspect.global_position + Vector3(1.6, 0.05, 1.6)
		Pursuit.interact()
		await t.wait(1.5)
		if attempt == 0:
			await t.snap("10_cuffing")
		await t.until(func() -> bool: return Pursuit.state == Pursuit.State.CUFFED, 5.0, "cuffed")
	await t.wait(1.2)
	await t.snap("11_cuffed")
	Pursuit.interact()                                       # E: process the suspect
	var booked: bool = await t.until(func() -> bool: return TrafficStop.dialog_open, 4.0, "booking menu")
	if not booked:
		t.note("E did not open the booking: it is requested directly")
		Pursuit.process_suspect()
		await t.until(func() -> bool: return TrafficStop.dialog_open, 4.0, "booking menu (direct)")
	await t.wait(2.0)
	await t.snap("12_booking")
	var booking: Object = TrafficStop.dialog
	booking.choose(&"book")
	await t.wait(2.0)
	await t.snap("13_charges")
	booking.choose(&"arrest_on")
	await t.wait(2.0)
	await t.snap("14_result")
	booking.choose(&"done")
	await t.wait(4.0)
	await t.snap("15_done")
	t.note("score %d, calls cleared %d, status %s, chain %s" % [GameState.score, director.completed, GameState.duty_status, str(main.hooks.duty.events)])
	main.get_tree().quit()
