extends RefCounted
## Call types, locations and unit call signs. Heads ("Code 2, Trespassing.") follow the standard format; the detail
## sentences are our own wording.

const UNITS: Array[String] = ["1-Adam-14", "1-Adam-22", "5-Adam-23", "5-Lincoln-18", "7-Sam-34", "7-Sam-21", "1-Lincoln-30",
	"5-Adam-11", "2-Adam-17", "3-Mary-41", "6-Adam-15", "9-Henry-27"]
const LOCATIONS: Array[String] = ["the Southside", "Oak Hills", "Eastgate", "Davidson Blvd"]

# Offerable call types (Y respond / N pass). Takeover calls ("all units ... respond Code 3") are Calls.emergency().
const TYPES := {
	&"trespassing": {"title": "Trespassing", "noun": "trespassing", "code": 2, "texts": [
		"A caller says a person is on private property near {loc} and will not leave.",
		"The owner of a lot near {loc} wants someone removed from the yard."]},
	&"suspicious_person": {"title": "Suspicious person", "noun": "suspicious person", "code": 2, "texts": [
		"A caller saw someone trying car doors near {loc}.",
		"A resident near {loc} reports a stranger looking into parked cars."]},
	&"noise_complaint": {"title": "Noise complaint", "noun": "noise complaint", "code": 2, "texts": [
		"Neighbours near {loc} report loud music and shouting.",
		"A caller near {loc} says a party is keeping the whole street awake."]},
	&"shoplifting": {"title": "Shoplifting", "noun": "shoplifting", "code": 2, "texts": [
		"Store staff near {loc} are holding a suspected shoplifter.",
		"A clerk near {loc} says a customer left without paying."]},
	&"traffic_collision": {"title": "Traffic collision", "noun": "traffic collision", "code": 2, "texts": [
		"Two cars collided near {loc}, no injuries reported.",
		"A caller reports a fender bender blocking a lane near {loc}."]},
	&"disturbance": {"title": "Disturbance", "noun": "disturbance", "code": 2, "texts": [
		"A caller near {loc} reports an argument getting loud between two neighbours.",
		"Bar staff near {loc} ask for help with a rowdy customer."]},
	&"welfare_check": {"title": "Welfare check", "noun": "welfare check", "code": 2, "texts": [
		"Family asks for someone to check on an elderly relative near {loc}.",
		"A caller near {loc} has not seen a neighbour for days."]},
	&"stolen_vehicle": {"title": "Stolen vehicle", "noun": "stolen vehicle", "code": 3, "texts": [
		"BOLO, {color} {model}, plate {plate}, last seen near {loc}. Occupant may flee."]},
	&"armed_robbery": {"title": "Armed robbery", "noun": "armed robbery", "code": 3, "texts": [
		"A store clerk near {loc} says the suspect showed a weapon and is leaving on foot.",
		"A cashier near {loc} reports a robbery just now, suspect heading away."]},
	&"burglary": {"title": "Burglary in progress", "noun": "burglary", "code": 3, "texts": [
		"A caller hears someone breaking in next door near {loc}.",
		"An alarm and a broken window near {loc}, someone is still inside."]},
	&"foot_pursuit": {"title": "Foot pursuit", "noun": "foot pursuit", "code": 3, "texts": [
		"Units are chasing a suspect on foot near {loc}. Assist if you can."]},
	&"shots_fired": {"title": "Shots fired", "noun": "shots fired", "code": 3, "texts": [
		"Several callers near {loc} report gunshots."]},
	&"traffic_stop": {"title": "Traffic stop", "noun": "traffic stop", "code": 2, "texts": [
		"Dispatch asks you to check a vehicle near {loc} that was reported driving erratically."]},
}

const COLORS: Array[String] = ["black", "white", "silver", "red", "blue", "green", "tan", "gray"]
const MODELS: Array[String] = ["Arden Compact", "Calloway Sedan", "Brightwater Pickup", "Kestrel Hatchback", "Tolland Coupe"]

static var _next_id: int = 1


## Builds a call dictionary. opts may override: location, text, plate, code.
static func make(type_id: StringName, rng: RandomNumberGenerator, opts: Dictionary = {}) -> Dictionary:
	var def: Dictionary = TYPES.get(type_id, TYPES[&"trespassing"])
	var loc: String = opts.get("location", LOCATIONS[rng.randi() % LOCATIONS.size()])
	var texts: Array = def["texts"]
	var text: String = opts.get("text", texts[rng.randi() % texts.size()])
	var plate: String = opts.get("plate", random_plate(rng))
	text = text.replace("{loc}", loc).replace("{plate}", plate)
	text = text.replace("{color}", COLORS[rng.randi() % COLORS.size()]).replace("{model}", MODELS[rng.randi() % MODELS.size()])
	var code: int = opts.get("code", def["code"])
	var title: String = def["title"]
	var head := ("Code %d: %s." % [code, title]) if code >= 3 else ("Code %d, %s." % [code, title])
	var call := {
		"id": _next_id, "type": type_id, "code": code, "title": title, "noun": def["noun"], "location": loc,
		"text": text, "head": head, "line": head + " " + text, "emergency": false, "status": &"new", "plate": plate,
	}
	_next_id += 1
	return call


static func random_plate(rng: RandomNumberGenerator) -> String:
	var letters := ""
	for i in 3:
		letters += char(65 + rng.randi() % 26)
	return "%s-%04d" % [letters, rng.randi() % 10000]


static func random_unit(rng: RandomNumberGenerator, exclude: Array = []) -> String:
	var pool: Array[String] = []
	for u in UNITS:
		if not exclude.has(u):
			pool.append(u)
	return pool[rng.randi() % pool.size()]


## Every static dispatch line the catalog can say (used by the clip generator, scripts/traffic_stop/dev/dump_lines.gd).
static func all_lines() -> Array[String]:
	var lines: Array[String] = []
	for type_id: StringName in TYPES:
		var def: Dictionary = TYPES[type_id]
		var head := ("Code %d: %s." % [def["code"], def["title"]]) if int(def["code"]) >= 3 else ("Code %d, %s." % [def["code"], def["title"]])
		for text: String in def["texts"]:
			if text.contains("{plate}"):
				continue  # dynamic: composed from the word bank
			for loc in LOCATIONS:
				lines.append(head + " " + text.replace("{loc}", loc))
		lines.append("10-22, another unit will handle the %s." % def["noun"])
	return lines
