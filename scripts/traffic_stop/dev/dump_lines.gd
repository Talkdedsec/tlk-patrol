extends SceneTree
## Dev tool: lists every line the radio voice may need and writes araclar/ses/telsiz_satirlar.json for araclar/ses/telsiz_uret.py.
## Run: araclar/godot.sh --headless --script res://scripts/traffic_stop/dev/dump_lines.gd
## "lines" are rendered as full clips; "words" are the bank used to compose any other line word by word.

const SpeechText := preload("res://scripts/calls/speech_text.gd")
const Catalog := preload("res://scripts/calls/call_catalog.gd")
const Profiles := preload("res://scripts/traffic_stop/driver_profiles.gd")
const Records := preload("res://scripts/traffic_stop/records.gd")

const FIXED: Array[String] = [
	"show me 10-6.", "show me 10-8.", "show me 10-76.", "10-4, 1-Adam-12.", "10-4, 1-Adam-12 responding Code 3.",
	"unable, I'm tied up.", "10-4, responding.", "10-4, 10-76.", "10-97.", "clearing.", "10-15.", "en route.",
	"terminate the pursuit.", "10-4, all units, pursuit terminated.", "Joining in.", "I've got the lead.",
	"Requesting permission to PIT.", "my prisoner's booked, show me 10-8.", "one in custody, transporting to booking.",
	"received, 1-Adam-12, traffic stop near the Southside.", "traffic stop, plate KEA-9291.", "run a 10-28 for me, KEA-9291.",
	"1-Adam-12, that plate comes back to a Halvorsen Ranger SUV, registered to Darnell Foster. No wants or warrants.",
	"10-80, vehicle failing to yield.", "Understood, 1-Adam-12 10-80. All units, be advised.", "Thank you, officer.",
	"Driver, pull forward a little more and stop.", "Driver, pull into the next street on your right and stop.",
	"Driver, follow me.", "Driver, stop right there.",
	"Do you know why I stopped you?", "Where are you headed?", "Have you had anything to drink tonight?", "Whose car is this?",
	"Is there anything illegal in the vehicle?", "Any weapons in the car or on you?", "Mind if I search the vehicle?",
	"Licence, registration and insurance, please.", "Step out of the vehicle for me, please.",
	"I'm going to have you do a few tests for me.",
	"Still northbound, at thirty.", "Heading eastbound, moderate speeds.", "Now westbound, very fast speeds.",
	"Turning southbound, slow speeds.", "Still northbound, speeds over a hundred.", "Still northbound, at twenty.",
]
const PURSUIT_LINES: Array[String] = [
	"Copy, 1-Adam-12 is 10-80. All units, be advised.", "Be advised, the registered owner has prior evading arrests. Use caution.",
	"I need a 10-78.", "10-4. 1-Lincoln-30, respond Code 3 to assist 1-Adam-12.", "10-4, 1-Lincoln-30, disregard.",
	"Calling off the foot pursuit.", "10-4, foot pursuit terminated.", "1-Adam-12, stand by.",
	"1-Adam-12, we have lost the suspect. All units, terminate the pursuit.", "1-Adam-12, supervisor clears the PIT.",
	"1-Adam-12, supervisor says negative on the PIT, speeds are too high. Keep following.", "Good PIT, vehicle spun out.",
	"Suspect bailed, I'm in foot pursuit.", "10-4, foot pursuit. All units, be advised.", "Thanks for the assist, 1-Adam-12.",
	"Code four; suspect's down.", "my unit's disabled, I'm out of the pursuit.", "I'm 10-80.", "10-97.", "10-15.",
	"I'll set up a roadblock ahead of them.", "He's turning right, now northbound.", "Continuing northbound, moderate speeds.",
]
const EXTRA_WORDS: Array[String] = ["police", "unit", "units", "plate", "traffic", "stop", "near", "southside", "responding", "assist",
	"warrant", "wants", "registered", "advised", "caution", "evading", "arrests", "prior", "hundred", "point", "dollars"]


## Dynamic sentences: only their words are needed (they are composed word by word at run time).
func _word_only_texts() -> Array[String]:
	var texts: Array[String] = []
	for unit in Catalog.UNITS:
		for type_id: StringName in Catalog.TYPES:
			var def: Dictionary = Catalog.TYPES[type_id]
			texts.append("%s, take the %s. Code %d." % [unit, def["noun"], def["code"]])
		texts.append("%s, that plate comes back to a registered to. No wants or warrants. Be advised." % unit)
	for hit: String in Records.HIT_TEXT.values():
		texts.append("Be advised, %s." % hit)
	for prefix in ["Still", "Now", "Heading", "Turning"]:
		for direction in ["northbound", "eastbound", "southbound", "westbound"]:
			for region in ["", " through Busco County", " in downtown Davidson City"]:
				for speed in ["at twenty", "at thirty", "slow speeds", "moderate speeds", "very fast speeds", "speeds over a hundred"]:
					texts.append("%s %s%s, %s." % [prefix, direction, region, speed])
	texts.append("Name check licence valid suspended outstanding warrant found one in custody transporting to booking")
	return texts


func _harvest(dir: String, out: Array[String]) -> void:
	var re := RegEx.create_from_string("(?:\\bsay|Dispatch\\.say)\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".gd"):
			continue
		var source := FileAccess.get_file_as_string(dir + "/" + file)
		for m in re.search_all(source):
			var line := m.get_string(1).replace("\\\"", "\"")
			var split := line.find(": ")
			if split > 0 and split < 48:
				line = line.substr(split + 2)
			line = line.replace("%s", "1-Adam-12").replace("%d", "3")
			if not line.contains("%") and line.length() > 2 and not out.has(line):
				out.append(line)
	for sub in DirAccess.get_directories_at(dir):
		_harvest(dir + "/" + sub, out)


func _initialize() -> void:
	var lines: Dictionary = {}  # key -> {text, spoken}
	var texts: Array[String] = []
	texts.append_array(FIXED)
	texts.append_array(Catalog.all_lines())
	texts.append_array(Profiles.all_lines())
	texts.append_array(PURSUIT_LINES)
	var harvested: Array[String] = []
	_harvest("res://scripts", harvested)
	texts.append_array(harvested)
	for loc in Catalog.LOCATIONS:
		texts.append("all units, shots fired, officer needs assistance. 1-Adam-12, %s. Respond Code 3." % loc)
	for unit in Catalog.UNITS:
		texts.append("%s, stand by." % unit)
		texts.append("10-4, %s." % unit)
	for text in texts:
		var key := SpeechText.key(text)
		if key.is_empty() or lines.has(key):
			continue
		lines[key] = {"text": text, "spoken": SpeechText.spoken_form(text), "key": key}
	# Word bank: every token of every line, plus names, models, phonetic alphabet and numbers.
	var words: Dictionary = {}
	for key: String in lines:
		for token in key.split(" ", false):
			words[token] = true
	for text in _word_only_texts():
		for token in SpeechText.key(text).split(" ", false):
			words[token] = true
	for letter: String in SpeechText.PHONETIC:
		words[String(SpeechText.PHONETIC[letter]).to_lower()] = true
	for n in 100:
		for token in SpeechText.number_words(n).split(" ", false):
			words[token] = true
	for entry in Records.all_words():
		for token in SpeechText.key(entry).split(" ", false):
			words[token] = true
	for unit in Catalog.UNITS:
		for token in SpeechText.key(unit).split(" ", false):
			words[token] = true
	for entry in EXTRA_WORDS:
		words[entry] = true
	for digit in 10:
		words[SpeechText.ONES[digit]] = true
	var word_list: Array = words.keys()
	word_list.sort()
	var out := {"lines": lines.values(), "words": word_list}
	var file := FileAccess.open("res://araclar/ses/telsiz_satirlar.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	print("DUMP lines=%d words=%d" % [lines.size(), word_list.size()])
	quit()
