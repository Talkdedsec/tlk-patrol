extends RefCounted
## Driver personalities for the traffic stop panel. A profile fixes the opening narrative, the driver's answers and the
## hidden truth (alcohol, contraband, documents) that the checks reveal. The showcase profile is the showcase stop
##; the other kinds are our own variations. Sentences below are our own wording.

const Charges := preload("res://scripts/traffic_stop/charges.gd")

# TODO(tahmin): every kind except the showcase, all answers to the other options, and the odds below.
const KINDS: Array[StringName] = [&"calm", &"nervous", &"hostile", &"drunk", &"rushed"]
# violation id -> [what the officer saw (sentence part), charge id]
const VIOLATIONS := {
	&"speeding": ["speeding", &"speeding"],
	&"lane": ["the car drift across the lane lines", &"lane"],
	&"seatbelt": ["the driver without a seatbelt", &"seatbelt"],
	&"equipment": ["a dead tail light", &"equipment"],
	&"phone": ["the driver holding a phone at the wheel", &"phone"],
	&"reckless": ["the car weaving through traffic", &"reckless"],
}
const CONTRABAND_TEXT := {
	&"marijuana": "a small bag of marijuana in the glovebox",
	&"open_container": "an open bottle in the back seat",
	&"firearm": "a loaded pistol under the driver's seat",
}
const WEAPON_TEXT := {
	&"firearm": "a loaded pistol in the waistband",
	&"knife": "a folding knife in the pocket",
}
const SOBER_FST := "steady walk-and-turn, clean one-leg stand."
const DRUNK_FST := "stumbles on the walk-and-turn, sways through the one-leg stand."


static func random_kind(rng: RandomNumberGenerator) -> StringName:
	var roll := rng.randf()
	if roll < 0.34:
		return &"calm"
	if roll < 0.52:
		return &"nervous"
	if roll < 0.68:
		return &"hostile"
	if roll < 0.78:
		return &"drunk"
	return &"rushed"


## The showcase stop: Darnell Foster, shaking, father in hospital.
static func showcase() -> Dictionary:
	return {
		"kind": &"rushed", "variant": &"showcase", "violation": &"", "name": "Darnell Foster", "emergency": true,
		"intro": [
			"You didn't see a violation before lighting this car up.",
			"The driver's knuckles are white on the wheel. They look close to tears.",
			"Engine off, window down, both hands on the wheel.",
			"They seem nervous: hands shaking, won't make eye contact.",
		],
		"greeting": "Please, officer, I have to get to the hospital.",
		"say": {
			"why": "My dad's had a heart attack. They called me from the hospital.",
			"headed": "Mercy General, on the east side. He's going into surgery.",
			"drink": "No, I don't drink and drive.",
			"whose": "It's mine. Please, can we do this quickly?",
			"illegal": "No. You can look if you want.",
			"weapons": "No weapons. I just need to get there.",
			"consent_yes": "Yes, anything. Just please hurry.",
			"consent_no": "Please, no. I don't have time for this.",
			"docs": "Here, it's all in my wallet.",
			"no_licence": "I left it in my other jacket.",
		},
		"truth": _truth({"consents": true}, _showcase_base()),
	}


static func _showcase_base() -> Dictionary:
	return {"licence": &"valid", "registration": &"valid", "insurance": &"valid", "warrant": false, "stolen_vehicle": false}


static func _truth(overrides: Dictionary, base: Dictionary) -> Dictionary:
	var truth := {
		"bac": 0.0, "fst_pass": true, "contraband": &"", "weapon": &"", "consents": true, "probable_cause": "",
		"licence": &"valid", "registration": &"valid", "insurance": &"valid", "warrant": false, "stolen_vehicle": false,
	}
	truth.merge(base, true)
	truth.merge(overrides, true)
	return truth


static func reason_line(violation: StringName) -> String:
	if violation == &"" or not VIOLATIONS.has(violation):
		return "You didn't see a violation before lighting this car up."
	return "You saw %s before lighting this car up." % VIOLATIONS[violation][0]


## Random (or fixed) profile for a record. violation: &"" for none, else a key of VIOLATIONS.
static func make(kind: StringName, record: Dictionary, rng: RandomNumberGenerator, violation: StringName = &"") -> Dictionary:
	var base := {"licence": record["licence"], "registration": record["registration"], "insurance": record["insurance"],
		"warrant": record["warrant"], "stolen_vehicle": record["stolen"]}
	var profile := {"kind": kind, "variant": &"", "violation": violation, "name": record["owner"], "emergency": false}
	var say := {}
	var truth_over := {}
	var intro: Array = [reason_line(violation)]
	match kind:
		&"calm":
			intro.append_array(["The driver looks tired but relaxed.", "Engine off, window down, both hands on the wheel.", "They meet your eyes and wait politely."])
			profile["greeting"] = "Evening, officer. Is something wrong?"
			say = {
				"why": "I think I was a bit careless back there. Sorry." if violation != &"" else "No, officer. Was I doing something wrong?",
				"headed": "Home. I just finished a late shift.",
				"drink": "No, I haven't had a drop.",
				"whose": "It's mine. I've had it about three years.",
				"illegal": "No, nothing like that.",
				"weapons": "No, officer. Nothing at all.",
				"consent_yes": "Sure, go ahead. I've got nothing to hide.",
				"consent_no": "I'd rather you didn't, if that's all right.",
				"docs": "Here you go.", "no_licence": "I must have left my wallet at home.",
			}
			truth_over = {"consents": rng.randf() < 0.7}
		&"nervous":
			intro.append_array(["The driver keeps glancing at the passenger seat.", "Engine running, window halfway down, grip tight on the wheel.", "They seem jumpy: knee bouncing, quick breaths."])
			profile["greeting"] = "Hi... officer. What's the problem?"
			say = {
				"why": "I don't know. I wasn't doing anything, I swear.",
				"headed": "Just to a friend's place. Not far.",
				"drink": "No. No, not tonight.",
				"whose": "It's mine. Well, my cousin's. He lets me use it.",
				"illegal": "No. Why would there be?",
				"weapons": "No weapons. Nothing.",
				"consent_yes": "I guess so. Make it quick, okay?",
				"consent_no": "No. I don't want anyone going through my things.",
				"docs": "Uh, yeah. One second.", "no_licence": "It's, uh, at home. I forgot it.",
			}
			var stash := rng.randf() < 0.6
			truth_over = {"consents": rng.randf() < 0.35}
			if stash:
				truth_over["contraband"] = &"marijuana"
				truth_over["probable_cause"] = "the smell of marijuana from the cabin"
				intro.append("You catch a faint smell of marijuana from the cabin.")
		&"hostile":
			intro.append_array(["The driver stares straight ahead, jaw clenched.", "Engine running, window barely open.", "They seem irritated: loud sighs, no eye contact."])
			profile["greeting"] = "What now? I didn't do anything."
			say = {
				"why": "No idea. Why don't you tell me?",
				"headed": "Home. Is that a crime now?",
				"drink": "I'm not drunk. Are we done here?",
				"whose": "It's my car. Check the registration.",
				"illegal": "No. You've got no reason to look.",
				"weapons": "No. And you can't just ask me that.",
				"consent_yes": "Fine. Look, then, and hurry up.",
				"consent_no": "No. Get a warrant.",
				"docs": "Here. Happy now?", "no_licence": "Don't have it on me.",
			}
			truth_over = {"consents": rng.randf() < 0.1}
			if rng.randf() < 0.18:
				truth_over["weapon"] = &"knife"
		&"drunk":
			intro.append_array(["The driver's eyes are glassy and the cabin smells of alcohol.", "Engine running, window all the way down.", "They seem unsteady: slow answers, slurred words."])
			profile["greeting"] = "Officer... hello. Nice night, huh?"
			say = {
				"why": "Was I swerving? Just a little, maybe.",
				"headed": "Home. It's not far, I promise.",
				"drink": "Two beers. Maybe three. With dinner.",
				"whose": "Mine. Obviously.",
				"illegal": "Nope. Well, maybe a bottle in the back. I forgot about it.",
				"weapons": "Weapons? No, no weapons.",
				"consent_yes": "Go ahead, go ahead.",
				"consent_no": "Nah, I'd rather you didn't.",
				"docs": "Hold on... it's in here somewhere.", "no_licence": "I think I lost it.",
			}
			truth_over = {"consents": rng.randf() < 0.5, "bac": snappedf(rng.randf_range(0.09, 0.17), 0.001), "fst_pass": false,
				"contraband": &"open_container", "probable_cause": "the smell of alcohol and an open bottle in plain view"}
		&"rushed":
			profile["emergency"] = true
			var variants: Array = [
				["The driver is pale and breathing hard.", "Engine off, window down, phone clutched in one hand.", "They seem frantic: sweating, glancing at the clock.",
					"Officer, please, my wife is in labour. We're almost at the hospital.", "She's in labour and the contractions are two minutes apart."],
				["The driver is flushed, eyes red from crying.", "Engine off, window down, both hands up where you can see them.", "They seem shaken: voice cracking, hands trembling.",
					"Sorry, officer, my daughter's school called. She fell and they're taking her to the ER.", "My daughter fell at school. They're taking her to the ER."],
			]
			var v: Array = variants[rng.randi() % variants.size()]
			intro.append_array([v[0], v[1], v[2]])
			profile["greeting"] = v[3]
			profile["variant"] = &"family_emergency"
			say = {
				"why": v[4],
				"headed": "The hospital on the east side. Please, I'm already late.",
				"drink": "No, I haven't been drinking. I swear.",
				"whose": "It's mine. Can we please do this quickly?",
				"illegal": "No, nothing. Look if you have to.",
				"weapons": "No. I don't own anything like that.",
				"consent_yes": "Yes, anything. Just hurry.",
				"consent_no": "Please, no. I have no time for this.",
				"docs": "Here. Everything is in the wallet.", "no_licence": "It's at home. I rushed out the door.",
			}
			truth_over = {"consents": true}
	profile["intro"] = intro
	profile["say"] = say
	profile["truth"] = _truth(truth_over, base)
	return profile


## Spoken line of a profile key ("why", "drink", ...); empty if missing.
static func line(profile: Dictionary, key: String) -> String:
	return String((profile["say"] as Dictionary).get(key, ""))


## Every driver sentence the profiles can say (for the radio clip generator).
static func all_lines() -> Array[String]:
	var lines: Array[String] = []
	var rng := RandomNumberGenerator.new()
	var record := {"licence": &"valid", "registration": &"valid", "insurance": &"valid", "warrant": false, "stolen": false, "owner": "X"}
	var profiles: Array[Dictionary] = [showcase()]
	for seed_value in 12:
		rng.seed = seed_value + 1
		for kind in KINDS:
			profiles.append(make(kind, record, rng, &"speeding"))
			profiles.append(make(kind, record, rng, &""))
	for p in profiles:
		var greeting := String(p["greeting"])
		if not greeting.is_empty() and not lines.has(greeting):
			lines.append(greeting)
		for key: String in p["say"]:
			var text: String = p["say"][key]
			if not lines.has(text):
				lines.append(text)
	return lines
