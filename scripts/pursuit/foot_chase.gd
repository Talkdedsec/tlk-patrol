extends RefCounted
## Foot phase of a pursuit: the suspect runs, the player chases ("Chase nearby" / FOOT CHASE), tases (LMB), the
## covering unit arrives, the suspect is cuffed (E) and ready to be processed.

const Adapters := preload("res://scripts/pursuit/adapters.gd")

enum Phase { RUN, DOWN, CUFFING, CUFFED }

const FT := 0.3048
## TODO(tahmin): Taser range and aim cone (only "on target, 14 ft" is shown); the real device reaches 15-35 ft.
const TASER_RANGE_M := 35.0 * FT
const TASER_CONE_COS := 0.9925    # cos(7 degrees)
const TASER_DELAY := 2.0          # Taser line 2 s after the bail (6:01.5 -> 6:03.5); TODO(tahmin): what triggers it
const MISS_COOLDOWN := 1.5
const RADIO_DELAY := 0.5          # "suspect bailed, I'm in foot pursuit" 0.5 s after the banner
const CUFF_TIME := 3.0            # "Cuffing..." about 3 s
## TODO(tahmin): the covering unit cuffs on its own after this many seconds if the player does nothing.
const AI_CUFF_DELAY := 10.0
const CUFF_RANGE_M := 6.0
const LOST_FT := 800.0
const LOST_SECONDS := 12.0
const COVERED_CENTER_X := 1051.0  # the long "has them covered" line is centred at x~1050, not at the screen centre

var p: Node
var banner: Node
var npc: Node3D
var phase: int = Phase.RUN
var joined := false              # TODO(tahmin): the trigger key is our choice; "Chase nearby" stays until C, then FOOT CHASE
var taser_out := false
var distance_ft := 0.0
var cop_name := "7-Sam-34"
var cop_npc: Node3D = null

var _t := 0.0
var announced := false            # true: the "foot pursuit" radio lines were (or must not be) sent
var _flee_t := 0.0
var _cuff_t := 0.0
var _cover_t := 0.0
var _by_ai := false
var _cooldown := 0.0
var _lost_t := 0.0


func start(pursuit: Node, ui: Node, suspect: Node3D, cover_name: String) -> void:
	p = pursuit
	banner = ui
	npc = suspect
	cop_name = cover_name
	phase = Phase.RUN
	_t = 0.0
	joined = false
	taser_out = false


func tick(dt: float) -> void:
	if npc == null or not is_instance_valid(npc):
		return
	_t += dt
	_cooldown = maxf(_cooldown - dt, 0.0)
	var pp: Vector3 = p.call("player_position")
	var d := npc.global_position - pp
	d.y = 0.0
	distance_ft = d.length() / FT
	match phase:
		Phase.RUN:
			_tick_run(dt, pp, d)
		Phase.DOWN:
			_cover_t += dt
			if _cover_t >= AI_CUFF_DELAY:
				_start_cuff(true)
		Phase.CUFFING:
			_cuff_t += dt
			if not _by_ai and distance_ft * FT > CUFF_RANGE_M + 1.0:
				phase = Phase.DOWN
				_cover_t = 0.0
				_show_covered()
				p.call("on_cuff_interrupted")
			elif _cuff_t >= CUFF_TIME:
				_finish_cuff()


func _tick_run(dt: float, pp: Vector3, d: Vector3) -> void:
	if not announced and _t >= RADIO_DELAY:
		announced = true
		p.call("on_foot_pursuit_declared")
	_flee_t -= dt
	if _flee_t <= 0.0:
		_flee_t = 0.45
		var side := Vector3(-d.z, 0.0, d.x).normalized()
		npc.call("flee_from", pp + side * sin(_t * 1.7) * 6.0, 70.0)
	if joined:
		banner.call("set_foot_chase", distance_ft)
	else:
		banner.call("set_chase_nearby", distance_ft)
	if not taser_out and _t >= TASER_DELAY:
		taser_out = true
		p.call("on_taser_out")
	if taser_out:
		var tgt := _target_info(pp)
		banner.call("set_taser", "Taser out   LMB use", "on target, %d ft" % roundi(tgt.ft) if tgt.ok else "")
	if distance_ft > LOST_FT:
		_lost_t += dt
		if _lost_t > LOST_SECONDS:
			p.call("end", &"lost")
	else:
		_lost_t = 0.0


## {ok, ft}: the suspect is inside the Taser range and the aim ray passes within the cone.
func _target_info(pp: Vector3) -> Dictionary:
	var chest := npc.global_position + Vector3(0.0, 1.1, 0.0)
	var flat := npc.global_position - pp
	flat.y = 0.0
	var ft := flat.length() / FT
	if flat.length() > TASER_RANGE_M:
		return {"ok": false, "ft": ft}
	var origin := pp + Vector3(0.0, 1.6, 0.0)
	var aim := (chest - origin).normalized()
	var officer := Adapters.officer()
	if officer != null and officer.has_method("get_aim_ray"):
		var ray: Dictionary = officer.call("get_aim_ray")
		origin = ray.origin
		aim = ray.direction
	else:
		var cam := Adapters.camera()
		if cam != null:
			origin = cam.global_position
			aim = -cam.global_transform.basis.z
	var cosang := aim.dot((chest - origin).normalized())
	return {"ok": cosang >= TASER_CONE_COS, "ft": ft}


func join() -> void:
	if phase == Phase.RUN:
		joined = true
		banner.call("clear_chase_nearby")


## LMB: true when the Taser hit.
func taser_fire() -> bool:
	if phase != Phase.RUN or not taser_out or _cooldown > 0.0:
		return false
	var pp: Vector3 = p.call("player_position")
	if not bool(_target_info(pp).ok):
		_cooldown = MISS_COOLDOWN
		return false
	_down()
	return true


## The suspect went down by other means (Weapons.target_downed, not lethal): same follow-up as the Taser.
func downed_externally() -> void:
	if phase == Phase.RUN:
		_down(false)


func _down(animate := true) -> void:
	phase = Phase.DOWN
	_cover_t = 0.0
	if animate:
		npc.call("go_down", &"taser")
	banner.call("clear_chase_nearby")
	banner.call("clear_foot_chase")
	banner.call("set_taser", "", "")
	_show_covered()
	_spawn_cop()
	p.call("on_suspect_downed")


func _show_covered() -> void:
	banner.call("toast", "%s has them covered. E to deal with them yourself, or %s will cuff them." % [cop_name, cop_name], 0.0, &"cuff_offer", COVERED_CENTER_X)
	banner.call("set_prompt", "E  Cuff")


func _spawn_cop() -> void:
	var pp: Vector3 = p.call("player_position")
	var back := pp - npc.global_position
	back.y = 0.0
	if back.length() < 0.1:
		back = Vector3.BACK
	back = back.normalized()
	var side := Vector3(-back.z, 0.0, back.x)
	var from := npc.global_position + back * 14.0 + side * 3.0
	cop_npc = Adapters.spawn_npc(Transform3D(Basis.looking_at(-back, Vector3.UP), from), "sheriff")
	cop_npc.call("walk_to", npc.global_position + side * 1.0 + back * 0.9, 4.2)


func interact() -> bool:
	if phase == Phase.DOWN:
		var pp: Vector3 = p.call("player_position")
		var d := npc.global_position - pp
		d.y = 0.0
		if d.length() <= CUFF_RANGE_M:
			_start_cuff(false)
			return true
	elif phase == Phase.CUFFED:
		p.call("process_suspect")
		return true
	return false


func _start_cuff(by_ai: bool) -> void:
	phase = Phase.CUFFING
	_by_ai = by_ai
	_cuff_t = 0.0
	banner.call("toast", "Cuffing...", 0.0)
	banner.call("set_prompt", "")
	p.call("on_cuff_started")


func _finish_cuff() -> void:
	phase = Phase.CUFFED
	npc.call("cuff")
	banner.call("toast", "Suspect cuffed. E to process them and book the charges.", 0.0)
	banner.call("set_prompt", "E  Process the suspect")
	p.call("on_suspect_cuffed")


func cleanup() -> void:
	if cop_npc != null and is_instance_valid(cop_npc):
		cop_npc.queue_free()
	cop_npc = null
