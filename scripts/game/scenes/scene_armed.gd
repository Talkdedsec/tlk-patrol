extends "res://scripts/game/scenes/call_scene.gd"
## "Armed robbery" call (Code 3): the suspect stands near the road with a pistol. Within sight the hint
## "They're holding a gun. R to order them to drop it; 5 to draw." appears. R (tap) orders the drop (surrender or run);
## coming close or shooting makes the suspect run: Pursuit's foot chase (Chase nearby / FOOT CHASE, Taser or Weapons,
## cover unit, cuffs, booking) takes over.

const FootAdapter := preload("res://scripts/game/foot_chase_adapter.gd")
const Records := preload("res://scripts/traffic_stop/records.gd")

const SEE_RANGE := 75.0           # m: the hint appears
const NOTICE_RANGE := 17.0        # m: the suspect runs when the player is this close
const ORDER_RANGE := 45.0
const HESITATE := 9.0             # s: the suspect runs after this long in sight if nothing happens
const SURRENDER_CHANCE := 0.55    # TODO(tahmin): share of drop-the-weapon orders that work
const OUTFITS: Array[StringName] = [&"purple_sweater", &"red_shirt_blue_shorts", &"maroon_runner", &"orange_driver"]
const HINT := "They're holding a gun. R to order them to drop it; 5 to draw."

var suspect: Node3D
var plate := ""
var phase := 0                    # 0 waiting, 1 in sight, 2 chase / surrendered
var _seen_for := 0.0
var _hurt := false


func _init() -> void:
	kind = &"armed_robbery"


func spawn() -> void:
	var away: bool = director.away_along_edge(edge, edge_s)
	var yaw_to_road := atan2(-edge_dir().x, -edge_dir().z)
	var pos := roadside(6.2 if director.rng.randf() < 0.5 else -6.2)
	suspect = spawn_npc(pos, OUTFITS[director.rng.randi() % OUTFITS.size()], yaw_to_road + (0.0 if away else PI))
	suspect.call("equip", &"pistol", true)
	plate = String(call.get("plate", ""))
	var rec := Records.for_plate(plate, "Calloway Sedan")
	rec["warrant"] = true
	suspect.set_meta("mdt_record", Records.finish(rec))
	link(Pursuit.ended, _on_pursuit_ended)
	link(TrafficStop.booking_finished, _on_booking_finished)
	link(Weapons.target_hit, _on_target_hit)
	link(Weapons.shot_fired, _on_shot_fired)
	link(Weapons.target_downed, _on_target_downed)


func update(dt: float) -> void:
	if suspect == null or not is_instance_valid(suspect):
		finish(&"cancelled")
		return
	if phase == 2:
		return
	var distance: float = director.player_distance(suspect.global_position)
	if phase == 0:
		if distance < SEE_RANGE:
			phase = 1
			director.hint(HINT, 4.0)
		return
	_seen_for += dt
	if suspect != null:
		_face_player()
	# a driver is only noticed up close; on foot the suspect loses his nerve after a while
	var nervous: bool = not director.player_driving() and _seen_for > HESITATE + distance * 0.05
	if distance < NOTICE_RANGE or nervous or _hurt:
		run_away()


func _face_player() -> void:
	var to: Vector3 = director.player_pos() - suspect.global_position
	to.y = 0.0
	if to.length() > 1.0:
		suspect.rotation.y = lerp_angle(suspect.rotation.y, atan2(-to.x, -to.z), 0.15)


func on_order() -> bool:
	if phase != 1 or director.player_driving() or director.player_distance(suspect.global_position) > ORDER_RANGE:
		return false
	if director.rng.randf() < float(call.get("surrender_chance", SURRENDER_CHANCE)):
		phase = 2
		director.hint("Drop it and get on your knees!", 2.0)
		suspect.call("surrender")
		_surrender_later()
	else:
		director.hint("They are running!", 1.5)
		run_away()
	return true


func _surrender_later() -> void:
	await director.get_tree().create_timer(1.6).timeout
	if done or suspect == null or not is_instance_valid(suspect):
		return
	suspect.call("kneel")
	if FootAdapter.begin(suspect, plate):
		Pursuit.foot.call("downed_externally")      # on the knees: "has them covered", E cuffs


func run_away() -> void:
	if phase == 2:
		return
	phase = 2
	var from: Vector3 = director.player_pos()
	suspect.call("flee_from", from, 160.0)
	FootAdapter.begin(suspect, plate)


func _on_target_hit(npc: Node, _damage, _part) -> void:
	if npc == suspect and phase != 2:
		_hurt = true


func _on_shot_fired(_origin, _dir, _weapon) -> void:
	if phase == 1:
		_hurt = true


## Shot before the chase started: the foot phase is set up first so Pursuit handles the fall (FOOT CHASE off, deceased line).
func _on_target_downed(npc: Node, weapon, lethal: bool) -> void:
	if npc != suspect:
		return
	if phase != 2:
		phase = 2
		if FootAdapter.begin(suspect, plate, "7-Sam-34", false):
			Pursuit.call("_on_target_downed", npc, weapon, lethal)
	if lethal:
		Calls.radio_dispatch("10-4, officer needs assistance, subject deceased. Clear the scene when able.")


func _on_pursuit_ended(reason: StringName) -> void:
	if phase != 2 or done:
		return
	if reason == &"processed":
		return
	finish(&"cleared" if reason == &"suspect_down" else &"cancelled")


func _on_booking_finished(_result: Dictionary) -> void:
	if phase == 2 and not done:
		finish(&"cleared")
