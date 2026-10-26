extends RefCounted
## Radio phrasing helpers: compass words, speed words and the AI-unit position report.
## Short call codes and callsigns stay fixed; the longer sentences are our own wording.

const UNIT_POOL: Array[String] = ["7-Sam-21", "1-Adam-22", "5-Adam-11", "7-Sam-34"]
const BACKUP_UNIT := "1-Lincoln-30"
const COVER_UNIT := "7-Sam-34"


## World heading to a compass word (north = -Z, east = +X).
static func cardinal(dir: Vector3) -> String:
	var deg := fposmod(rad_to_deg(atan2(dir.x, -dir.z)), 360.0)
	if deg < 45.0 or deg >= 315.0:
		return "northbound"
	if deg < 135.0:
		return "eastbound"
	if deg < 225.0:
		return "southbound"
	return "westbound"


## TODO(tahmin): thresholds. Words: at twenty / at thirty / slow / moderate / very fast / speeds over a hundred.
static func speed_words(mph: float, limit_mph: int) -> String:
	if mph >= 100.0:
		return "speeds over a hundred"
	if mph <= 24.0:
		return "at twenty"
	if mph <= 34.0:
		return "at thirty"
	var r := mph / maxf(float(limit_mph), 1.0)
	if r < 0.95:
		return "slow speeds"
	if r < 1.35:
		return "moderate speeds"
	return "very fast speeds"


static func region(kind: String) -> String:
	if kind == "highway" or kind == "rural" or kind == "ramp":
		return " through Busco County"
	return " in downtown Davidson City"


## One position report line (without the unit prefix).
static func position_report(dir_word: String, changed: bool, kind: String, mph: float, limit_mph: int, rng: RandomNumberGenerator) -> String:
	var spd := speed_words(mph, limit_mph)
	var reg := region(kind)
	var cap := dir_word.capitalize()
	if changed:
		match rng.randi() % 3:
			0:
				return "Turning %s, %s." % [dir_word, spd]
			1:
				return "Now %s%s." % [dir_word, reg]
			_:
				return "%s%s, %s." % [cap, reg, spd]
	match rng.randi() % 3:
		0:
			return "Still %s, %s." % [dir_word, spd]
		1:
			return "Heading %s%s, %s." % [dir_word, reg, spd]
		_:
			return "%s%s, %s." % [cap, reg, spd]
