extends RefCounted
## Starts Pursuit's foot phase on a suspect who is already on foot (armed-suspect calls). Pursuit only enters BAILED from
## a car pursuit (Pursuit._bail), so this sets up the same state from outside with the module's own FootChase.
## Module request (docs/api/game.md): Pursuit.begin_foot_chase(npc, options) would replace this adapter.

const FootChase := preload("res://scripts/pursuit/foot_chase.gd")
const AiUnits := preload("res://scripts/pursuit/ai_units.gd")
const PursuitAdapters := preload("res://scripts/pursuit/adapters.gd")

const EVIDENCE_FOOT := "Fleeing a police officer on foot"


## True when the foot chase is running. The suspect should already be running away (flee_from).
static func begin(npc: Node3D, plate := "", cover := "7-Sam-34", announce := true) -> bool:
	if Pursuit.state != Pursuit.State.IDLE or npc == null or not is_instance_valid(npc):
		return false
	Pursuit._ensure_banner()
	Pursuit.target = null
	Pursuit.suspect = npc
	Pursuit.suspect_plate = plate
	var units := AiUnits.new()      # silent (no radio chatter): Pursuit's foot callbacks expect a units object
	units.enabled = false
	units.start(Pursuit)
	Pursuit.units = units
	Pursuit.driver = null
	Pursuit.pit = null
	Pursuit.elapsed = 0.0
	Pursuit.evidence_charges.clear()
	Pursuit.evidence_charges.append(EVIDENCE_FOOT)
	var foot := FootChase.new()
	Pursuit.foot = foot
	foot.start(Pursuit, Pursuit.banner, npc, cover)
	Pursuit._set_state(Pursuit.State.BAILED)
	Pursuit.banner.call("clear_pursuit")
	if announce:
		Pursuit.banner.call("toast", "The suspect is running! Catch them.", 3.5)
	Pursuit._score_t = Pursuit.BAIL_SCORE_DELAY
	var officer := PursuitAdapters.officer()
	if officer != null and PursuitAdapters.in_vehicle(officer):
		PursuitAdapters.exit_vehicle(officer)   # same as Pursuit._bail: the car brakes, the officer gets out
	Pursuit.suspect_bailed.emit(npc)
	return true
