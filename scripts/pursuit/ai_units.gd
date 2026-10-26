extends RefCounted
## Radio-only AI police units of a pursuit: join (`I'm 10-80`), periodic position reports, drop out
## (`my unit's disabled...`), occasional roadblock announcement, backup unit. Units are not simulated as vehicles
## (they are seldom visible).

const Radio := preload("res://scripts/pursuit/radio.gd")

## TODO(tahmin): all timings below (2-4 units active, 7-12 s between reports; lifetimes are guessed).
const MIN_UNITS := 2
const MAX_UNITS := 4
const REPORT_MIN := 7.0
const REPORT_MAX := 12.0
const LIFETIME_MIN := 35.0
const LIFETIME_MAX := 110.0
const ROADBLOCK_MIN_T := 45.0
const ROADBLOCK_MAX_T := 90.0
const BACKUP_ETA := 28.0

var p: Node
var enabled := true
var units: Array = []          # [{callsign: String, leave_at: float}]
var rng := RandomNumberGenerator.new()
var t := 0.0
var backup_pending := false
var backup_eta := -1.0
var roadblock_enabled := true

var _queue: Array = []         # [{t: float, callsign: String}]
var _next_report := 8.0
var _report_i := 0
var _last_dir := ""
var _roadblock_at := -1.0
var _roadblock_done := false


func start(pursuit: Node) -> void:
	p = pursuit
	rng.randomize()
	t = 0.0
	units.clear()
	_queue.clear()
	backup_pending = false
	backup_eta = -1.0
	_next_report = 9.0
	_roadblock_done = false
	_roadblock_at = rng.randf_range(ROADBLOCK_MIN_T, ROADBLOCK_MAX_T)
	if not enabled:
		return
	_schedule_join(2.0)
	_schedule_join(5.0)


func active_callsigns() -> Array[String]:
	var out: Array[String] = []
	for u: Dictionary in units:
		out.append(String(u.callsign))
	return out


## Unit that talks the player through the end of the pursuit (cover / cuff): 7-Sam-34.
func cover_unit() -> String:
	var names := active_callsigns()
	if names.has(Radio.COVER_UNIT) or names.is_empty():
		return Radio.COVER_UNIT
	return names[0]


## Name of any active unit (for "Good PIT" style lines); empty when none.
func any_unit() -> String:
	var names := active_callsigns()
	return names[rng.randi() % names.size()] if not names.is_empty() else ""


func _free_callsign() -> String:
	var taken := active_callsigns()
	for q: Dictionary in _queue:
		taken.append(String(q.callsign))
	var free: Array[String] = []
	for c in Radio.UNIT_POOL:
		if not taken.has(c):
			free.append(c)
	return free[rng.randi() % free.size()] if not free.is_empty() else ""


func _schedule_join(delay: float) -> void:
	var c := _free_callsign()
	if c != "":
		_queue.append({"t": t + delay, "callsign": c})


func _join(callsign: String) -> void:
	units.append({"callsign": callsign, "leave_at": t + rng.randf_range(LIFETIME_MIN, LIFETIME_MAX)})
	p.call("say", "%s: I'm 10-80." % callsign, 0.1)


func _leave(u: Dictionary) -> void:
	units.erase(u)
	p.call("say", "%s: my unit's disabled, I'm out of the pursuit." % u.callsign, 0.0)
	if rng.randf() < 0.4:
		p.call("say", "Dispatch: 10-22, another unit will handle the traffic collision.", 0.9)
	_schedule_join(rng.randf_range(8.0, 25.0))


## ctx: {dir: Vector3 (suspect heading), mph: float, limit: int, kind: String}
func tick(dt: float, ctx: Dictionary) -> void:
	t += dt
	for q: Dictionary in _queue.duplicate():
		if t >= float(q.t):
			_queue.erase(q)
			if enabled and units.size() < MAX_UNITS:
				_join(String(q.callsign))
	if enabled:
		for u: Dictionary in units.duplicate():
			if t >= float(u.leave_at):
				_leave(u)
		if units.size() + _queue.size() < MIN_UNITS:
			_schedule_join(rng.randf_range(3.0, 10.0))
	if backup_eta > 0.0:
		backup_eta -= dt
		if backup_eta <= 0.0 and backup_pending:
			backup_eta = -1.0
			units.append({"callsign": Radio.BACKUP_UNIT, "leave_at": t + rng.randf_range(40.0, 120.0)})
			p.call("say", "%s: I'm 10-80." % Radio.BACKUP_UNIT, 0.1)
	if enabled and t >= _next_report and not units.is_empty():
		var u: Dictionary = units[_report_i % units.size()]
		_report_i += 1
		var dir: Vector3 = ctx.dir
		var word := Radio.cardinal(dir)
		var line := Radio.position_report(word, word != _last_dir and _last_dir != "", String(ctx.kind),
			float(ctx.mph), int(ctx.limit), rng)
		_last_dir = word
		p.call("say", "%s: %s" % [u.callsign, line], 0.0)
		_next_report = t + rng.randf_range(REPORT_MIN, REPORT_MAX)
	if enabled and roadblock_enabled and not _roadblock_done and t >= _roadblock_at and not units.is_empty():
		_roadblock_done = true
		var rb: Dictionary = units[rng.randi() % units.size()]
		p.call("say", "%s: I'll set up a roadblock ahead of them." % rb.callsign, 0.0)
		p.call("roadblock", String(rb.callsign))


## B key: request backup (true) or clear it (false).
func toggle_backup() -> bool:
	if not backup_pending:
		backup_pending = true
		backup_eta = BACKUP_ETA
		return true
	backup_pending = false
	backup_eta = -1.0
	for u: Dictionary in units.duplicate():
		if u.callsign == Radio.BACKUP_UNIT:
			units.erase(u)
	return false
