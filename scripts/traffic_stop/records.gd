extends RefCounted
## Vehicle and driver records for plate runs and traffic stops. A plate always maps to the same record
## (seeded from the plate), unless a scenario stores its own in the vehicle's "mdt_record" meta.

const FIRST_NAMES: Array[String] = ["Darnell", "Marcus", "Elena", "Priya", "Tomas", "Hannah", "Wesley", "Imani", "Lucas", "Greta",
	"Raymond", "Sofia", "Andre", "Maya", "Curtis", "Nadia", "Victor", "Lena", "Owen", "Rosa", "Dwayne", "Claire", "Felix", "Joan"]
const LAST_NAMES: Array[String] = ["Foster", "Whitaker", "Alvarez", "Nakamura", "Brennan", "Okafor", "Lindgren", "Delgado", "Hartley",
	"Mbeki", "Castillo", "Sorensen", "Pruitt", "Navarro", "Kowalski", "Ellison", "Tran", "Abbott", "Ferreira", "Quinn", "Hollis",
	"Park", "Bianchi", "Mercer"]
const MODELS: Array[String] = ["Halvorsen Ranger SUV", "Arden Compact", "Calloway Sedan", "Brightwater Pickup", "Kestrel Hatchback",
	"Tolland Coupe", "Marlow Van", "Redfield Wagon"]
const COLORS: Array[String] = ["black", "white", "silver", "red", "blue", "green", "tan", "gray"]

## Hit texts shown by plate runs and name runs.
const HIT_TEXT := {
	&"warrant": "registered owner has a warrant",
	&"suspended": "owner's licence suspended",
	&"stolen": "vehicle reported stolen",
	&"expired": "registration expired",
	&"evading": "owner has prior arrests for evading",
}


static func random_plate(rng: RandomNumberGenerator) -> String:
	var letters := ""
	for i in 3:
		letters += char(65 + rng.randi() % 26)
	return "%s-%04d" % [letters, rng.randi() % 10000]


## Record for a plate. Flags are rolled from the plate so the same car always has the same history.
static func for_plate(plate: String, model_hint: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(plate)
	var first := FIRST_NAMES[rng.randi() % FIRST_NAMES.size()]
	var last := LAST_NAMES[rng.randi() % LAST_NAMES.size()]
	var roll := rng.randf()
	var record := {
		"plate": plate,
		"model": model_hint if not model_hint.is_empty() else MODELS[rng.randi() % MODELS.size()],
		"color": COLORS[rng.randi() % COLORS.size()],
		"first": first, "last": last, "owner": "%s %s" % [first, last],
		"dob": "%02d/%02d/%d" % [rng.randi_range(1, 28), rng.randi_range(1, 12), rng.randi_range(1951, 2004)],
		"licence_no": "D%07d" % rng.randi_range(1000000, 9999999),
		"licence": &"valid", "registration": &"valid", "insurance": &"valid",
		"warrant": false, "stolen": false, "evading": false,
	}
	# TODO(tahmin): hit frequencies; only "No hits" and the ALPR warrant/suspended examples.
	if roll < 0.06:
		record["warrant"] = true
	elif roll < 0.12:
		record["licence"] = &"suspended"
	elif roll < 0.15:
		record["stolen"] = true
	elif roll < 0.20:
		record["registration"] = &"expired"
	elif roll < 0.23:
		record["evading"] = true
	elif roll < 0.27:
		record["licence"] = &"none"
	if rng.randf() < 0.05:
		record["insurance"] = &"none"
	return finish(record)


## The showcase stop: Halvorsen Ranger SUV KEA-9291, Darnell Foster.
static func showcase() -> Dictionary:
	return finish({
		"plate": "KEA-9291", "model": "Halvorsen Ranger SUV", "color": "green", "first": "Darnell", "last": "Foster",
		"owner": "Darnell Foster", "dob": "06/10/1960", "licence_no": "D7520883",
		"licence": &"valid", "registration": &"valid", "insurance": &"valid",
		"warrant": false, "stolen": false, "evading": false,
	})


## Fills the derived "hits" list.
static func finish(record: Dictionary) -> Dictionary:
	var hits: Array[String] = []
	if record.get("warrant", false):
		hits.append(HIT_TEXT[&"warrant"])
	if record.get("licence", &"valid") == &"suspended":
		hits.append(HIT_TEXT[&"suspended"])
	if record.get("stolen", false):
		hits.append(HIT_TEXT[&"stolen"])
	if record.get("registration", &"valid") == &"expired":
		hits.append(HIT_TEXT[&"expired"])
	if record.get("evading", false):
		hits.append(HIT_TEXT[&"evading"])
	record["hits"] = hits
	return record


## Dispatch's answer to a 10-28 (log text without the speaker prefix).
static func reply_text(unit: String, record: Dictionary) -> String:
	var text := "%s, that plate comes back to a %s, registered to %s. " % [unit, record["model"], record["owner"]]
	var hits: Array = record["hits"]
	if hits.is_empty():
		return text + "No wants or warrants."
	return text + "Be advised, %s." % hits[0]


## MDT PLATES result block (BBCode): bold plate, owner, "No hits."
static func result_lines(record: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("[b]%s[/b], %s" % [record["plate"], record["model"]])
	lines.append("Owner: %s" % record["owner"])
	var hits: Array = record["hits"]
	if hits.is_empty():
		lines.append("No hits.")
	for hit in hits:
		lines.append("[color=#ff6a60][b]HIT[/b]  %s[/color]" % hit)
	return lines


## All names and model words (the radio clip generator voices these as a word bank).
static func all_words() -> Array[String]:
	var words: Array[String] = []
	words.append_array(FIRST_NAMES)
	words.append_array(LAST_NAMES)
	words.append_array(MODELS)
	words.append_array(COLORS)
	return words
