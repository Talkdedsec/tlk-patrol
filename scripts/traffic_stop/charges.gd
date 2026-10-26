extends RefCounted
## Charge lists of the citation and arrest forms.
## Fines are $ amounts; felonies and some misdemeanors carry none.

const ALL: Array[Dictionary] = [
	{"id": &"speeding", "name": "Speeding", "level": "infraction", "fine": 150},
	{"id": &"lane", "name": "Failure to maintain lane", "level": "infraction", "fine": 120},
	{"id": &"expired_reg", "name": "Expired registration", "level": "infraction", "fine": 90},
	{"id": &"no_insurance", "name": "No proof of insurance", "level": "infraction", "fine": 250},
	{"id": &"open_container", "name": "Open container in a vehicle", "level": "infraction", "fine": 100},
	{"id": &"no_licence", "name": "Driving without a licence", "level": "misdemeanor", "fine": 300},
	{"id": &"suspended", "name": "Driving with a suspended licence", "level": "misdemeanor", "fine": 500},
	{"id": &"dui", "name": "Driving under the influence", "level": "misdemeanor", "fine": 0},
	{"id": &"marijuana", "name": "Possession of marijuana", "level": "misdemeanor", "fine": 300},
	{"id": &"pwid", "name": "Possession with intent to distribute", "level": "felony", "fine": 0},
	{"id": &"firearm", "name": "Unlawful carrying of a firearm", "level": "felony", "fine": 0},
	{"id": &"stolen_property", "name": "Possession of stolen property", "level": "misdemeanor", "fine": 0},
	{"id": &"stolen_vehicle", "name": "Possession of a stolen vehicle", "level": "felony", "fine": 0},
	{"id": &"false_id", "name": "Giving false identification", "level": "misdemeanor", "fine": 0},
	{"id": &"warrant", "name": "Outstanding warrant", "level": "felony", "fine": 0},
	{"id": &"evading", "name": "Evading police in a vehicle", "level": "felony", "fine": 0, "evidence": true},
	{"id": &"fleeing_foot", "name": "Fleeing a police officer on foot", "level": "misdemeanor", "fine": 0, "evidence": true},
	{"id": &"resisting", "name": "Resisting arrest", "level": "misdemeanor", "fine": 0, "evidence": true},
	{"id": &"unsafe_collision", "name": "Unsafe driving causing a collision", "level": "infraction", "fine": 200},
	{"id": &"leaving_scene", "name": "Leaving the scene of a collision", "level": "misdemeanor", "fine": 0},
	{"id": &"reckless", "name": "Reckless driving", "level": "misdemeanor", "fine": 500},
	{"id": &"brandishing", "name": "Brandishing a firearm", "level": "misdemeanor", "fine": 0},
	{"id": &"carjacking", "name": "Carjacking", "level": "felony", "fine": 0},
	{"id": &"child_endangerment", "name": "Child endangerment", "level": "misdemeanor", "fine": 0},
	{"id": &"seatbelt", "name": "No seatbelt", "level": "infraction", "fine": 75},
	{"id": &"equipment", "name": "Equipment violation (fix-it ticket)", "level": "infraction", "fine": 25},
	{"id": &"phone", "name": "Handheld phone while driving", "level": "infraction", "fine": 160},
]

## The 13 charges of the citation form, in form order.
const CITATION_IDS: Array[StringName] = [&"speeding", &"lane", &"expired_reg", &"no_insurance", &"open_container", &"no_licence",
	&"suspended", &"marijuana", &"unsafe_collision", &"reckless", &"seatbelt", &"equipment", &"phone"]


static func get_charge(id: StringName) -> Dictionary:
	for charge in ALL:
		if charge["id"] == id:
			return charge
	return {}


## Charge id from an id or from its display name (pursuit passes either).
static func resolve(value: Variant) -> StringName:
	var text := String(value)
	for charge in ALL:
		if String(charge["id"]) == text or String(charge["name"]).to_lower() == text.to_lower():
			return charge["id"]
	return &""


static func label(charge: Dictionary) -> String:
	var detail: String = charge["level"]
	if int(charge["fine"]) > 0:
		detail += ", $%d" % int(charge["fine"])
	return "%s (%s)" % [charge["name"], detail]


static func arrest_list() -> Array[Dictionary]:
	return ALL


static func citation_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for id in CITATION_IDS:
		list.append(get_charge(id))
	return list


static func total_fines(ids: Array) -> int:
	var total := 0
	for id in ids:
		total += int(get_charge(id).get("fine", 0))
	return total


static func is_arrestable(id: StringName) -> bool:
	var level: String = get_charge(id).get("level", "infraction")
	return level != "infraction"
