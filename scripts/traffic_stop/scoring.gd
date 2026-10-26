extends RefCounted
## Stop evaluation after the decision. The three rows of the warning screen are exact (no visible reason -20, search without consent or probable cause -40, discretion for a family emergency +15).
## Every other row is an estimate: TODO(tahmin) see "Tasarım varsayımları" in docs/api/traffic_stop.md.

const Charges := preload("res://scripts/traffic_stop/charges.gd")

const NO_REASON := -20
const ILLEGAL_SEARCH := -40
const FAMILY_EMERGENCY := 15
const WRONG_CHARGE := -15
const RIGHT_CHARGE := 10
const LAWFUL_ARREST := 25
const UNLAWFUL_ARREST := -60
const FRISK_WITHOUT_GROUNDS := -10
const LET_IMPAIRED_GO := -50
const LET_WANTED_GO := -40
const MISSED_CHARGE := -5
const CLEAN_STOP := 5


## state: the dialog model's facts (see DialogModel.facts()).
## ruling: &"warning", &"citation" or &"arrest"; charge_ids: selected charges (citation/arrest).
static func evaluate(facts: Dictionary, ruling: StringName, charge_ids: Array) -> Dictionary:
	var items: Array[Dictionary] = []
	var truth: Dictionary = facts["truth"]
	if not facts["booking"] and String(facts["violation"]) == "":
		items.append({"text": "No visible reason for the stop", "points": NO_REASON})
	if facts["illegal_search"]:
		items.append({"text": "Search without consent or probable cause; what it found won't hold up", "points": ILLEGAL_SEARCH})
	if facts["illegal_frisk"]:
		items.append({"text": "Pat-down without grounds", "points": FRISK_WITHOUT_GROUNDS})
	match ruling:
		&"warning":
			if facts["impaired_known"]:
				items.append({"text": "Let an impaired driver go", "points": LET_IMPAIRED_GO})
			elif facts["wanted_known"]:
				items.append({"text": "Let a wanted person go", "points": LET_WANTED_GO})
			elif facts["emergency"] and not facts["found_legal"]:
				items.append({"text": "Good discretion for a family emergency", "points": FAMILY_EMERGENCY})
			elif facts["found_legal"]:
				items.append({"text": "Contraband found but no action taken", "points": -10})
			elif items.is_empty():
				items.append({"text": "Handled by the book", "points": CLEAN_STOP})
		&"citation", &"arrest":
			var supported_count := 0
			var arrestable_supported := false
			for id: StringName in charge_ids:
				var charge := Charges.get_charge(id)
				if supports(facts, id):
					supported_count += 1
					items.append({"text": "%s: supported" % charge["name"], "points": RIGHT_CHARGE})
					if Charges.is_arrestable(id):
						arrestable_supported = true
				else:
					items.append({"text": "%s: nothing supports it" % charge["name"], "points": WRONG_CHARGE})
			if ruling == &"arrest":
				if arrestable_supported:
					items.append({"text": "Lawful arrest", "points": LAWFUL_ARREST})
				else:
					items.append({"text": "Arrest without grounds", "points": UNLAWFUL_ARREST})
			else:
				for id in missed_charges(facts, charge_ids):
					items.append({"text": "Missed: %s" % String(Charges.get_charge(id)["name"]).to_lower(), "points": MISSED_CHARGE})
	var total := 0
	for item in items:
		total += int(item["points"])
	return {"items": items, "total": total}


## Whether the facts of this stop back a charge.
static func supports(facts: Dictionary, id: StringName) -> bool:
	if (facts["evidence_ids"] as Array).has(id):
		return true
	var truth: Dictionary = facts["truth"]
	match id:
		&"speeding", &"lane", &"seatbelt", &"equipment", &"phone", &"reckless":
			return StringName(facts["violation"]) == id
		&"expired_reg":
			return truth["registration"] == &"expired" and (facts["docs_checked"] or facts["plate_run"])
		&"no_insurance":
			return truth["insurance"] == &"none" and facts["docs_checked"]
		&"no_licence":
			return truth["licence"] == &"none" and facts["docs_checked"]
		&"suspended":
			return truth["licence"] == &"suspended" and facts["name_run"]
		&"dui":
			return float(truth["bac"]) >= 0.08 and (facts["breath_over"] or facts["fst_failed"])
		&"open_container":
			return truth["contraband"] == &"open_container" and (facts["found_legal"] or facts["plain_view"])
		&"marijuana":
			return truth["contraband"] == &"marijuana" and facts["found_legal"]
		&"firearm":
			return (truth["contraband"] == &"firearm" or truth["weapon"] == &"firearm") and facts["found_legal"]
		&"warrant":
			return bool(truth["warrant"]) and facts["name_run"]
		&"stolen_vehicle":
			return bool(truth["stolen_vehicle"]) and facts["plate_run"]
	return false


## Supported charges the officer knew about but did not write.
static func missed_charges(facts: Dictionary, chosen: Array) -> Array[StringName]:
	var missed: Array[StringName] = []
	for charge in Charges.citation_list():
		var id: StringName = charge["id"]
		if not chosen.has(id) and supports(facts, id) and not Charges.is_arrestable(id):
			missed.append(id)
	return missed
