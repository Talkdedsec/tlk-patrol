extends "res://scripts/game/scenes/call_scene.gd"
## Quiet calls (traffic collision, trespassing, disturbance, suspicious person, noise, welfare): the people involved stand at
## the place and the officer walks up and talks to each of them (E). The statements are our own wording; when everyone has
## been heard the call is cleared. A collision also leaves two crashed cars at the kerb.

const OUTFITS: Array[StringName] = [&"green_hoodie", &"grey_tee_cap", &"yellow_top", &"teal_jacket", &"denim_plaid", &"white_shirt"]
const TALK_RANGE := 2.6
const PROMPT := "E  Talk"

## Statements per call type: the first person's and the second person's.
const STATEMENTS := {
	&"traffic_collision": [
		"I had the green light. They came out of nowhere and hit my door.",
		"I looked down for one second. I'll give you my insurance card."],
	&"trespassing": [
		"I only sat down for a minute, I did not know the lot was closed.",
		"I asked them twice to leave. Please make sure they go."],
	&"suspicious_person": [
		"I'm waiting for a friend. I wasn't touching any cars.",
		"They kept looking into the windows. It made me nervous."],
	&"noise_complaint": [
		"We'll turn it down, officer. It's my brother's birthday.",
		"It has been going since noon. Some of us have to work."],
	&"disturbance": [
		"He started it. I just want him off my property.",
		"That's not what happened. We were only talking."],
	&"welfare_check": [
		"Thanks for coming. I haven't heard from her since Tuesday.",
		"She's fine, I was at the hospital. My phone died."],
	&"shoplifting": [
		"I forgot to pay, I swear. Let me pay for it now.",
		"I saw them put it in the bag and walk past the register."],
}

var talked: Array[bool] = []
var people: Array[Node3D] = []
var _wrapped := false
var _prompt_shown := false


func _init() -> void:
	kind = &"talk"


func spawn() -> void:
	var yaw := atan2(-edge_dir().x, -edge_dir().z)
	var type_id := StringName(call.get("type", &"trespassing"))
	var base := roadside(6.0 if director.rng.randf() < 0.5 else -6.0)
	var count := 2
	for i in count:
		var pos := base + edge_dir() * (float(i) * 2.2 - 1.1)
		var npc := spawn_npc(pos, OUTFITS[director.rng.randi() % OUTFITS.size()], yaw + PI * 0.5 * (1.0 if i == 0 else -1.0))
		people.append(npc)
		talked.append(false)
	if type_id == &"traffic_collision":
		_crash_cars()
	for npc in people:
		npc.call_deferred("talk", &"talk_a")


func _crash_cars() -> void:
	var dir := edge_dir()
	var right := -Vector3.UP.cross(dir)
	for i in 2:
		var type_id := Vehicles.random_traffic_type()
		var pos := origin + right * (2.2 if i == 0 else 1.2) + dir * (0.0 if i == 0 else 5.5) + Vector3(0.0, 0.5, 0.0)
		var yaw := atan2(-dir.x, -dir.z) + (0.0 if i == 0 else 0.5)
		var car := Vehicles.spawn(type_id, Transform3D(Basis(Vector3.UP, yaw), pos), director.world_parent())
		car.set_handbrake(true)
		car.set_meta("stop_hold", true)
		track(car)


func update(_dt: float) -> void:
	if _wrapped:
		return
	var prompt := ""
	var near := _nearest_person()
	if near >= 0 and not director.player_driving():
		prompt = PROMPT
	director.set_scene_prompt(prompt)
	_prompt_shown = not prompt.is_empty()


func _nearest_person() -> int:
	var best := -1
	var best_d := TALK_RANGE
	for i in people.size():
		if not is_instance_valid(people[i]):
			continue
		var d: float = director.player_distance(people[i].global_position)
		if d < best_d:
			best = i
			best_d = d
	return best


func on_interact() -> bool:
	if _wrapped or director.player_driving():
		return false
	var i := _nearest_person()
	if i < 0:
		return false
	var lines: Array = STATEMENTS.get(StringName(call.get("type", &"")), STATEMENTS[&"trespassing"])
	var who := "Driver" if call.get("type", &"") == &"traffic_collision" else "Witness"
	director.hint("%s: \"%s\"" % [who, lines[i % lines.size()]], 4.5)
	talked[i] = true
	people[i].call("talk", &"talk_b")
	director.speak_line(lines[i % lines.size()])
	if not talked.has(false):
		_wrap_up()
	return true


func _wrap_up() -> void:
	_wrapped = true
	director.set_scene_prompt("")
	await director.get_tree().create_timer(4.8).timeout
	if done:
		return
	director.hint("Everyone is heard. Call cleared.", 2.5)
	finish(&"cleared")


func cleanup() -> void:
	director.set_scene_prompt("")
	super()
