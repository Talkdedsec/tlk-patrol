extends Node
## Scripted end-to-end check of Calls, Mdt and TrafficStop on the placeholder stage (run: scenes/traffic_stop/test_stage.tscn -- --auto).
## Replays the showcase stop: lights, pull-over, scene command, exit, talk, search, FST,
## breathalyzer, warning (-45), back in the car; then plate run, call offers, emergency band, chase notice and booking.

const Overlay := preload("res://scripts/traffic_stop/stop_overlay.gd")
const Adapters := preload("res://scripts/traffic_stop/adapters.gd")
const PullOver := preload("res://scripts/traffic_stop/pull_over.gd")
const FakeVehicle := preload("res://scripts/traffic_stop/dev/fake_vehicle.gd")
const FakeGraph := preload("res://scripts/traffic_stop/dev/fake_graph.gd")
const PlaceholderNpc := preload("res://scripts/traffic_stop/placeholder_npc.gd")

var stage: Node3D
var failures := 0
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL  ", message)
	else:
		print("ok    ", message)


func until(condition: Callable, timeout: float, message: String) -> bool:
	var waited := 0.0
	while not condition.call() and waited < timeout:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	check(condition.call(), message)
	return condition.call()


func _run() -> void:
	Engine.time_scale = 3.0
	Calls.voice.enabled = false
	TrafficStop.dialog_voice.enabled = false
	TrafficStop.auto_available = true
	GameState.set_score(15)
	await get_tree().create_timer(0.3).timeout
	var overlay := Overlay.of(get_tree())
	var target: Node3D = stage.target
	var patrol: Node3D = stage.patrol
	var player: Node3D = stage.player

	# --- the showcase stop ---------------------------------------------------------------------------
	target.plate = "KEA-9291"
	target.display_name = "Halvorsen Ranger SUV"
	Els.set_stage(2)
	Els.set_lights(true)
	await until(func() -> bool: return TrafficStop.state != TrafficStop.State.IDLE, 10.0, "lights on -> stop starts by itself")
	await until(func() -> bool: return TrafficStop.state == TrafficStop.State.STOPPED, 40.0, "car stops")
	check(target.speed_mph() < 0.5, "stopped car is at rest")
	check(target.global_position.x > 1.8, "car pulled to the right (x=%.1f)" % target.global_position.x)
	check(Dispatch.lines.size() >= 2 and Dispatch.lines[Dispatch.lines.size() - 2].contains("traffic stop, plate KEA-9291."), "radio: traffic stop, plate")
	check(Dispatch.lines[Dispatch.lines.size() - 1].contains("received, 1-Adam-12, traffic stop near the Southside."), "radio: dispatch received")
	patrol.speed = 0.0
	patrol.ai_enabled = false
	patrol.global_position = target.global_position + Vector3(0.0, 0.0, 9.0)
	TrafficStop.set_scene_commands(true)
	check(overlay.scene_commands_visible(), "scene commands box visible")
	var z_before := target.global_position.z
	TrafficStop.command(1)
	check(overlay.toast_text() == "PA: \"Driver, pull forward a little more and stop.\"", "PA toast for command 1")
	await get_tree().create_timer(6.0).timeout
	check(target.global_position.z < z_before - 3.0 and target.speed_mph() < 1.0, "car crept forward and stopped (%.1f m)" % (z_before - target.global_position.z))
	TrafficStop.command(4)
	patrol.global_position = target.global_position + Vector3(0.0, 0.0, 9.0)
	player.exit_vehicle()
	await until(func() -> bool: return TrafficStop.state == TrafficStop.State.ON_FOOT, 3.0, "officer on foot -> ON_FOOT")
	await get_tree().create_timer(0.5).timeout
	check(not TrafficStop.flashlight_on, "flashlight still off ~10 m from the driver (range %.1f m)" % TrafficStop.flashlight_range)
	check(Calls.status == &"busy" and GameState.duty_status == "Busy", "status Busy")
	check(overlay.toast_text() == "Status: Busy", "toast Status: Busy")
	check(Dispatch.lines.has("1-Adam-12: show me 10-6.") and Dispatch.lines.has("Dispatch: 10-4, 1-Adam-12."), "radio: show me 10-6 / 10-4")
	player.global_position = door_of(target) + Vector3(-0.8, 0.0, 0.0)
	await get_tree().create_timer(0.5).timeout
	print("DBG state=", TrafficStop.state_name(), " driver=", TrafficStop.driver, " vis=", TrafficStop.driver.visible if TrafficStop.driver else null, " dpos=", TrafficStop.driver.global_position if TrafficStop.driver else null,
		" player=", player.global_position, " in_car=", Adapters.player_in_vehicle(get_tree()), " prompt=", overlay.prompt_text(), " target=", TrafficStop._prompt_target)
	check(TrafficStop.flashlight_on and overlay._flash.visible, "flashlight and its line come on within the range")
	check(overlay.prompt_text() == "E  Talk to the driver", "prompt: E  Talk to the driver (got '%s')" % overlay.prompt_text())
	TrafficStop._interact()
	check(TrafficStop.dialog_open and TrafficStop.state == TrafficStop.State.DIALOG, "dialog opened")
	var panel: Control = TrafficStop._panel
	check(panel.narrative_text().contains("You didn't see a violation before lighting this car up."), "narrative: no violation line")
	check(panel.narrative_text().contains("Driver: \"Please, officer, I have to get to the hospital.\""), "narrative: greeting")
	var rows: Array[Dictionary] = TrafficStop.dialog.options()
	var buttons := rows.filter(func(r: Dictionary) -> bool: return r["kind"] == "button")
	var headers := rows.filter(func(r: Dictionary) -> bool: return r["kind"] == "header")
	check(buttons.size() == 21 and headers.size() == 5, "21 options in 5 sections (%d/%d)" % [buttons.size(), headers.size()])
	var d := TrafficStop.dialog
	d.choose(&"why")
	d.choose(&"drink")
	d.choose(&"illegal")
	check(panel.narrative_text().contains("My dad's had a heart attack. They called me from the hospital."), "answer: heart attack")
	d.choose(&"docs")
	check(panel.narrative_text().contains("Licence: Darnell Foster, born 06/10/1960, no. D7520883"), "licence line")
	check(panel.narrative_text().contains("Registration: Halvorsen Ranger SUV, plate KEA-9291, owner Darnell Foster"), "registration line")
	check(_has_option(d, &"name") and not _has_option(d, &"docs"), "Run their name replaces the document option")
	d.choose(&"search")
	check(panel.narrative_text().contains("You search the vehicle without consent or probable cause."), "illegal search line")
	check(panel.narrative_text().contains("Nothing illegal found."), "nothing found")
	check(not _has_option(d, &"pull_up") and not _has_option(d, &"step_out") and not _has_option(d, &"search") and not _has_option(d, &"patdown"), "directions and step-out options gone")
	check(_has_option(d, &"warn") and _has_option(d, &"consent"), "decide section and consent question remain")
	d.choose(&"fst")
	check(panel.narrative_text().contains("PASSED"), "FST passed")
	d.choose(&"breath")
	check(panel.narrative_text().contains("Breathalyzer: 0.000 BAC (legal limit 0.08)"), "breathalyzer line")
	d.choose(&"cite")
	check(d.view == d.View.CITATION and d.options().filter(func(r: Dictionary) -> bool: return r["kind"] == "check").size() == 13, "citation form: 13 charges")
	d.choose(&"back")
	d.choose(&"arrest")
	check(d.options().filter(func(r: Dictionary) -> bool: return r["kind"] == "check").size() == 27, "arrest form: 27 charges")
	d.choose(&"back")
	d.choose(&"warn")
	check(d.result.get("points", 0) == -45, "warning scores -45 (got %s)" % str(d.result.get("points", "none")))
	check(GameState.score == -30, "score 15 -> -30 (got %d)" % GameState.score)
	check(overlay.toast_text() == "Stop complete: -45 points", "toast Stop complete: -45 points")
	check(panel.narrative_text().contains("Good stop.  -45 points") and panel.narrative_text().contains("No visible reason for the stop (-20)")
		and panel.narrative_text().contains("(-40)") and panel.narrative_text().contains("Good discretion for a family emergency (+15)"), "summary rows")
	check(d.options().size() == 1 and d.options()[0]["label"] == "Done", "only Done left")
	d.choose(&"done")
	check(not TrafficStop.dialog_open and TrafficStop.state == TrafficStop.State.WRAP_UP, "dialog closed -> WRAP_UP")
	check(Calls.stats["warnings"] == 1, "warning counted")
	player.global_position = patrol.global_position + Vector3(-1.5, 0.0, 0.0)
	await get_tree().create_timer(0.4).timeout
	check(overlay.prompt_text() == "E  Get in", "prompt: E  Get in (got '%s')" % overlay.prompt_text())
	TrafficStop._interact()
	await until(func() -> bool: return TrafficStop.state == TrafficStop.State.IDLE, 25.0, "back in the car -> stop released")
	await until(func() -> bool: return Calls.status == &"available", 15.0, "10-8: status back to Available")

	# --- MDT -----------------------------------------------------------------------------------------------
	Mdt.open(&"plates")
	check(Mdt.is_open and Mdt.tab == &"plates", "MDT opens on PLATES")
	var plate_target := stage.target as Node3D
	plate_target.plate = "KEA-9291"
	if plate_target.has_meta("mdt_record"):
		plate_target.remove_meta("mdt_record")
	await Mdt.run_plate(plate_target)
	var plate_text := "\n".join(Mdt._plate_lines)
	check(plate_text.contains("Running plate KEA-9291...") and plate_text.contains("Owner: Darnell Foster") and plate_text.contains("No hits."), "PLATES result block")
	check(Dispatch.lines.has("1-Adam-12: run a 10-28 for me, KEA-9291."), "radio: run a 10-28")
	var found_reply := false
	for line in Dispatch.lines:
		if line.contains("that plate comes back to a Halvorsen Ranger SUV, registered to Darnell Foster. No wants or warrants."):
			found_reply = true
	check(found_reply, "dispatch plate reply")
	Mdt.show_tab(&"dispatch")
	check(Mdt.window().tab == &"dispatch", "DISPATCH tab")
	Mdt.show_tab(&"calls")
	Mdt.show_tab(&"unit")
	Mdt.close()
	check(not Mdt.is_open, "MDT closes")

	# --- calls ----------------------------------------------------------------------------------------------
	var call := Calls.offer(&"trespassing")
	check(overlay.offer_text() == "Code 2: Trespassing.   Y respond   N pass   (25)", "offer prompt (got '%s')" % overlay.offer_text())
	Calls.pass_offer()
	check(Dispatch.lines.has("1-Adam-12: unable, I'm tied up.") and Dispatch.lines.has("Dispatch: 10-22, another unit will handle the trespassing."), "N pass radio lines")
	check(overlay.offer_text() == "", "prompt cleared after pass")
	Calls.offer(&"stolen_vehicle")
	Calls.offer_left = 0.05
	await get_tree().create_timer(0.4).timeout
	check(Dispatch.lines[Dispatch.lines.size() - 2].contains("take the stolen vehicle. Code 3."), "expired offer goes to another unit")
	Calls.offer(&"noise_complaint")
	Calls.respond()
	check(Calls.status == &"busy" and not Calls.current.is_empty(), "Y respond -> assigned and Busy")
	Calls.complete()
	check(Calls.status == &"available" and Calls.current.is_empty(), "complete -> Available")
	Calls.emergency("Eastgate")
	await get_tree().create_timer(0.5).timeout
	var hud := Adapters.hud(get_tree())
	if hud != null:
		check(hud._emergency.visible, "emergency band on the HUD")
	else:
		check(overlay.toast_text() == "EMERGENCY: all units responding", "emergency band (no HUD fallback)")
	await get_tree().create_timer(1.2).timeout
	check(Calls.status == &"busy" and Calls.current.get("emergency", false), "emergency auto-assigned")
	Calls.complete()
	Calls.chase_nearby(0.2)
	check(overlay.chase_text() == "Chase nearby, 0.2 mi   C join   Z call off", "chase notice text")
	Calls.set_chase_distance(0.3)
	check(overlay.chase_text() == "Chase nearby, 0.3 mi   C join   Z call off", "chase distance update")
	Calls.call_off_chase()
	check(overlay.toast_text() == "Chase called off" and overlay.chase_text() == "", "Z call off")
	check(Dispatch.lines.has("Dispatch: 10-4, all units, pursuit terminated."), "pursuit terminated radio")

	# --- booking ----------------------------------------------------------------------------------------------
	var npc := PlaceholderNpc.new()
	stage.add_child(npc)
	TrafficStop.begin_booking(npc, ["Evading police in a vehicle", "Fleeing a police officer on foot", "Resisting arrest"], {"plate": "TAY-6023", "model": "Halvorsen Ranger SUV"})
	check(TrafficStop.dialog_open and TrafficStop.dialog.title == "Traffic stop: TAY-6023  (Halvorsen Ranger SUV)", "booking panel title")
	var b := TrafficStop.dialog
	check(not _has_option(b, &"why") and _has_option(b, &"book") and _has_option(b, &"docs"), "booking menu")
	b.choose(&"book")
	var checked := b.options().filter(func(r: Dictionary) -> bool: return r["kind"] == "check" and r["checked"])
	check(checked.size() == 3, "3 evidence charges pre-checked")
	b.choose(&"arrest_on")
	check(b.result.get("points", 0) > 0 and b.result.get("ruling") == &"arrest", "booking scored (+%s)" % str(b.result.get("points", 0)))
	b.choose(&"done")
	check(not TrafficStop.dialog_open and TrafficStop.state == TrafficStop.State.IDLE, "booking closed")

	# --- lane shift on a narrow road ---------------------------------------
	for case in [[false, 5.2, "no road known: full 3.2 m shift"], [true, 3.1, "8 m road, car in the lane centre (x=2): 1.1 m shift"]]:
		Adapters.graph_override = FakeGraph.new() if case[0] else null
		var car := FakeVehicle.new()
		car.position = Vector3(2.0, 0.0, -300.0)
		car.speed = 6.0
		stage.add_child(car)
		var mover := PullOver.new()
		stage.add_child(mover)
		mover.attach(car)
		mover.pull_over()
		await until(func() -> bool: return mover.mode == PullOver.Mode.HOLD, 25.0, "pull-over finishes (%s)" % case[2])
		check(absf(car.global_position.x - float(case[1])) < 0.35, "%s (x=%.2f)" % [case[2], car.global_position.x])
		check(not case[0] or car.global_position.x + 0.95 <= 4.1, "car body stays on the 8 m road")
		car.queue_free()
		mover.queue_free()
	Adapters.graph_override = null

	# --- voice ---------------------------------------------------------------------------------------------------
	print("VOICE clips=", Calls.voice.has_clips(), " tts=", Calls.voice.tts_available(),
		" sample method=", Calls.voice.method_for("10-4, 1-Adam-12."))
	print("E2E ", "OK" if failures == 0 else "FAIL", "  checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)


func _has_option(model, id: StringName) -> bool:
	for row: Dictionary in model.options():
		if row["id"] == id:
			return true
	return false


func door_of(vehicle: Node3D) -> Vector3:
	return (vehicle.call("enter_transform", &"driver") as Transform3D).origin
