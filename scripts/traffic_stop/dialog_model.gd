extends RefCounted
## Conversation state machine of the traffic stop panel.
## Pure data: the panel renders `entries` and `options()`, the TrafficStop autoload reacts to `action_requested`.
## Option structure, one-shot behaviour and the showcase texts are fixed; the answers of other drivers
## come from driver_profiles.gd.

const Charges := preload("res://scripts/traffic_stop/charges.gd")
const Profiles := preload("res://scripts/traffic_stop/driver_profiles.gd")
const Scoring := preload("res://scripts/traffic_stop/scoring.gd")
const Ui := preload("res://scripts/mdt/ui_kit.gd")

enum Mode { STOP, BOOKING }
enum View { MENU, CITATION, ARREST, SUMMARY }

## speaker: &"you", &"driver", &"narration" or &"result"; spoken: the sentence to voice ("" for none).
signal entry_added(bbcode: String, speaker: StringName, spoken: String)
signal view_changed
## Actions for the host: step_out, vehicle_command {index}, mdt_lines {lines}, step_away, arrest {charges}, citation {charges}, warning.
signal action_requested(action: StringName, args: Dictionary)
signal finished(result: Dictionary)

const GOOD_STOP := "Good stop."

var mode: int = Mode.STOP
var view: int = View.MENU
var title: String = ""
var record: Dictionary = {}
var profile: Dictionary = {}
var has_vehicle: bool = true
var entries: Array[String] = []
var checked: Dictionary = {}
var evidence_ids: Array = []
var result: Dictionary = {}

var _done: Dictionary = {}
var _f: Dictionary = {
	"out_of_car": false, "search_done": false, "consent": "", "illegal_search": false, "illegal_frisk": false, "frisked": false,
	"docs_checked": false, "plate_run": false, "name_run": false, "fst_failed": false, "breath_over": false,
	"found_legal": false, "plain_view": false, "admitted": false,
}


## opts: booking (bool), vehicle (bool, default true), evidence (Array of charge ids pre-checked and backed by the chase).
func setup(vehicle_record: Dictionary, driver_profile: Dictionary, opts: Dictionary = {}) -> void:
	record = vehicle_record
	profile = driver_profile
	mode = Mode.BOOKING if opts.get("booking", false) else Mode.STOP
	has_vehicle = opts.get("vehicle", true)
	evidence_ids = opts.get("evidence", [])
	for id in evidence_ids:
		checked[StringName(id)] = true
	title = "Traffic stop: %s  (%s)" % [record["plate"], record["model"]]
	entries.clear()
	if mode == Mode.BOOKING:
		_f["out_of_car"] = true
		entries.append("[i]You have the suspect. Identify them, search them, then book the charges.[/i]")
	else:
		for line: String in profile["intro"]:
			entries.append("[i]%s[/i]" % line)
		entries.append('Driver: "%s"' % profile["greeting"])


func greeting() -> String:
	return String(profile.get("greeting", ""))


# --- options ----------------------------------------------------------------------------------------

func options() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	match view:
		View.SUMMARY:
			rows.append(_button(&"done", "Done"))
		View.CITATION:
			rows.append(_header("CHARGES FOR THE CITATION"))
			for charge in Charges.citation_list():
				rows.append(_check(charge))
			rows.append(_button(&"issue", "Issue the citation"))
			rows.append(_button(&"back", "Back"))
		View.ARREST:
			rows.append(_header("CHARGES FOR THE ARREST"))
			for charge in Charges.arrest_list():
				rows.append(_check(charge))
			rows.append(_button(&"arrest_on", "Arrest on these charges"))
			rows.append(_button(&"back", "Back"))
		_:
			_menu_rows(rows)
	return rows


func _menu_rows(rows: Array[Dictionary]) -> void:
	if mode == Mode.STOP:
		_section(rows, "TALK", [
			[&"why", "Do you know why I stopped you?"], [&"headed", "Where are you headed?"],
			[&"drink", "Have you had anything to drink tonight?"], [&"whose", "Whose car is this?"],
			[&"illegal", "Is there anything illegal in the vehicle?"], [&"weapons", "Any weapons in the car or on you?"],
			[&"consent", "Mind if I search the vehicle?"]])
	var papers: Array = []
	if not _f["docs_checked"]:
		papers.append([&"docs", "Ask for licence and registration"])
	elif not _f["name_run"]:
		papers.append([&"name", "Run their name on the MDT"])
	if has_vehicle and not _f["plate_run"]:
		papers.append([&"plate", "Run the plate on the MDT"])
	_section(rows, "PAPERS AND MDT", papers, false)
	var investigate: Array = []
	if mode == Mode.STOP and not _f["out_of_car"]:
		investigate.append([&"step_out", "Ask them to step out of the car"])
	if mode == Mode.STOP:
		investigate.append([&"fst", "Field sobriety test"])
	investigate.append([&"breath", "Breathalyzer"])
	if not _f["frisked"] and not _f["search_done"]:
		investigate.append([&"patdown", "Pat them down for weapons"])
	if has_vehicle and not _f["search_done"]:
		investigate.append([&"search", "Search the vehicle"])
	_section(rows, "INVESTIGATE", investigate, false)
	if mode == Mode.STOP and not _f["out_of_car"]:
		_section(rows, "DIRECTIONS", [
			[&"pull_up", "Have them pull up further"], [&"next_street", "Have them pull into the next street on the right"],
			[&"follow", "Have them follow you"]])
	if mode == Mode.STOP:
		rows.append(_header("DECIDE"))
		rows.append(_button(&"warn", "Let them go with a warning"))
		rows.append(_button(&"cite", "Write a citation..."))
		rows.append(_button(&"arrest", "Arrest..."))
		rows.append(_button(&"away", "Step away (Esc)"))
	else:
		rows.append(_header("DECIDE"))
		rows.append(_button(&"book", "Book the charges"))
		rows.append(_button(&"away", "Step away (Esc)"))


func _section(rows: Array[Dictionary], name: String, items: Array, _unused: bool = true) -> void:
	var visible_items: Array = []
	for item: Array in items:
		if not _done.has(item[0]):
			visible_items.append(item)
	if visible_items.is_empty():
		return
	rows.append(_header(name))
	for item: Array in visible_items:
		rows.append(_button(item[0], item[1]))


func _header(text: String) -> Dictionary:
	return {"kind": "header", "id": &"", "label": text}


func _button(id: StringName, label: String) -> Dictionary:
	return {"kind": "button", "id": id, "label": label}


func _check(charge: Dictionary) -> Dictionary:
	var id: StringName = charge["id"]
	return {"kind": "check", "id": id, "label": Charges.label(charge), "checked": checked.get(id, false),
		"tag": "[evidence]" if evidence_ids.has(id) else ""}


# --- choosing ---------------------------------------------------------------------------------------

func choose(id: StringName) -> void:
	if view == View.CITATION or view == View.ARREST:
		if _choose_form(id):
			return
	match id:
		&"why":
			_ask(id, "Do you know why I stopped you?")
		&"headed":
			_ask(id, "Where are you headed?")
		&"drink":
			_ask(id, "Have you had anything to drink tonight?")
		&"whose":
			_ask(id, "Whose car is this?")
		&"illegal":
			_ask(id, "Is there anything illegal in the vehicle?")
			if String(profile["truth"]["contraband"]) == "open_container":
				_f["admitted"] = true
				_f["plain_view"] = true
		&"weapons":
			_ask(id, "Any weapons in the car or on you?")
		&"consent":
			_done[id] = true
			_you("Mind if I search the vehicle?")
			if profile["truth"]["consents"]:
				_f["consent"] = "yes"
				_driver(Profiles.line(profile, "consent_yes"))
			else:
				_f["consent"] = "no"
				_driver(Profiles.line(profile, "consent_no"))
		&"docs":
			_check_documents()
		&"name":
			_run_name()
		&"plate":
			_run_plate()
		&"step_out":
			_done[id] = true
			_step_out()
		&"fst":
			_field_sobriety()
		&"breath":
			_breathalyzer()
		&"patdown":
			_pat_down()
		&"search":
			_search_vehicle()
		&"pull_up":
			_direct(id, 1, "You signal the driver to pull up further.")
		&"next_street":
			_direct(id, 2, "You signal the driver to turn into the next street on the right.")
		&"follow":
			_direct(id, 3, "You signal the driver to follow you.")
		&"warn":
			_rule(&"warning", [])
		&"cite":
			view = View.CITATION
			view_changed.emit()
		&"arrest", &"book":
			view = View.ARREST
			view_changed.emit()
		&"away":
			action_requested.emit(&"step_away", {})
		&"done":
			finished.emit(result)
	if view == View.MENU:
		view_changed.emit()


func _choose_form(id: StringName) -> bool:
	match id:
		&"back":
			view = View.MENU
			view_changed.emit()
			return true
		&"issue":
			var ids := selected_charges()
			if ids.is_empty():
				_narration("Pick at least one charge first.")
			else:
				_rule(&"citation", ids)
			return true
		&"arrest_on":
			var ids2 := selected_charges()
			if ids2.is_empty():
				_narration("Pick at least one charge first.")
			else:
				_rule(&"arrest", ids2)
			return true
	if Charges.get_charge(id).size() > 0:
		checked[id] = not checked.get(id, false)
		view_changed.emit()
		return true
	return false


func selected_charges() -> Array:
	var ids: Array = []
	var source: Array[Dictionary] = Charges.citation_list() if view == View.CITATION else Charges.arrest_list()
	for charge in source:
		if checked.get(charge["id"], false):
			ids.append(charge["id"])
	return ids


## Esc: leaves a charge form, or steps away from the driver.
func back_or_away() -> void:
	if view == View.CITATION or view == View.ARREST:
		view = View.MENU
		view_changed.emit()
	elif view == View.SUMMARY:
		finished.emit(result)
	else:
		action_requested.emit(&"step_away", {})


# --- results -----------------------------------------------------------------------------------------

func _ask(id: StringName, question: String) -> void:
	_done[id] = true
	_you(question)
	_driver(Profiles.line(profile, String(id)))


func _check_documents() -> void:
	_f["docs_checked"] = true
	_done[&"docs"] = true
	_you("Licence, registration and insurance, please.")
	var truth: Dictionary = profile["truth"]
	if truth["licence"] == &"none":
		_driver(Profiles.line(profile, "no_licence"))
		_result("Licence: none produced")
	else:
		_result("Licence: %s, born %s, no. %s" % [record["owner"], record["dob"], record["licence_no"]])
	var registration := "Registration: %s, plate %s, owner %s" % [record["model"], record["plate"], record["owner"]]
	if truth["registration"] == &"expired":
		registration += ", tags expired"
	_result(registration)
	if truth["insurance"] == &"none":
		_result("Insurance: no proof produced")


func _run_name() -> void:
	_f["name_run"] = true
	_done[&"name"] = true
	var truth: Dictionary = profile["truth"]
	var lines: Array[String] = []
	var who := "%s, born %s" % [record["owner"], record["dob"]]
	match truth["licence"]:
		&"valid":
			lines.append("%s: licence valid." % who)
		&"suspended":
			lines.append("%s: [b][color=%s]licence SUSPENDED[/color][/b]." % [who, Ui.hex(Ui.FAIL_RED)])
		_:
			lines.append("%s: no licence on file." % record["owner"])
	if truth["warrant"]:
		lines.append("[b][color=%s]Outstanding warrant on file.[/color][/b] Use caution." % Ui.hex(Ui.FAIL_RED))
	elif truth["licence"] != &"suspended":
		lines.append("No wants or warrants.")
	_result("You run their name on the MDT.")
	for line in lines:
		_result(line)
	action_requested.emit(&"mdt_lines", {"lines": ["Name check: %s" % record["owner"]] + lines})


func _run_plate() -> void:
	_f["plate_run"] = true
	_done[&"plate"] = true
	_result("You run the plate on the MDT.")
	var block := Array(_plate_block())
	for line in block:
		_result(String(line))
	action_requested.emit(&"mdt_lines", {"lines": block})


func _plate_block() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("[b]%s[/b], %s" % [record["plate"], record["model"]])
	lines.append("Owner: %s" % record["owner"])
	var hits: Array = record.get("hits", [])
	if hits.is_empty():
		lines.append("No hits.")
	for hit in hits:
		lines.append("[color=%s][b]HIT[/b]  %s[/color]" % [Ui.hex(Ui.FAIL_RED), hit])
	return lines


func _step_out() -> void:
	_f["out_of_car"] = true
	_you("Step out of the vehicle for me, please.")
	_narration("The driver steps out and stands by the car.")
	action_requested.emit(&"step_out", {})


func _auto_step_out() -> void:
	if not _f["out_of_car"]:
		_done[&"step_out"] = true
		_step_out()


func _field_sobriety() -> void:
	_done[&"fst"] = true
	_auto_step_out()
	_you("I'm going to have you do a few tests for me.")
	var truth: Dictionary = profile["truth"]
	if truth["fst_pass"]:
		_result("Field sobriety test: %s" % Profiles.SOBER_FST)
		_result("[b][color=%s]PASSED[/color][/b]" % Ui.hex(Ui.PASS_GREEN))
	else:
		_f["fst_failed"] = true
		_result("Field sobriety test: %s" % Profiles.DRUNK_FST)
		_result("[b][color=%s]FAILED[/color][/b]" % Ui.hex(Ui.FAIL_RED))


func _breathalyzer() -> void:
	_done[&"breath"] = true
	var bac: float = profile["truth"]["bac"]
	_result("Breathalyzer: %.3f BAC (legal limit 0.08)" % bac)
	if bac >= 0.08:
		_f["breath_over"] = true
		_result("[b][color=%s]OVER THE LIMIT[/color][/b]" % Ui.hex(Ui.FAIL_RED))


func _pat_down() -> void:
	_f["frisked"] = true
	_done[&"patdown"] = true
	_auto_step_out()
	var truth: Dictionary = profile["truth"]
	var grounds: bool = _f["consent"] == "yes" or truth["weapon"] != &"" or truth["contraband"] == &"firearm"
	_result("You pat them down for weapons.")
	if truth["weapon"] != &"":
		_result("You find [b]%s[/b]." % Profiles.WEAPON_TEXT[truth["weapon"]])
	else:
		_result("Nothing on them.")
	if not grounds:
		_f["illegal_frisk"] = true


## TODO(tahmin): the consent/probable-cause variants of the search line, the contraband results and the pat-down text.
func _search_vehicle() -> void:
	_f["search_done"] = true
	_done[&"search"] = true
	_auto_step_out()
	var truth: Dictionary = profile["truth"]
	var basis := ""
	var detail := ""
	if _f["consent"] == "yes":
		basis = "consent"
	elif String(truth["probable_cause"]) != "" or _f["admitted"]:
		basis = "cause"
		detail = String(truth["probable_cause"])
		if detail.is_empty():
			detail = "the driver's own admission"
	elif _f["fst_failed"] or _f["breath_over"]:
		basis = "cause"
		detail = "the failed sobriety test"
	else:
		basis = "none"
	match basis:
		"consent":
			_plain_result("You search the vehicle with their consent.")
		"cause":
			_plain_result("You search the vehicle on probable cause: %s." % detail)
		_:
			_f["illegal_search"] = true
			_plain_result("You search the vehicle [color=%s]without consent or probable cause[/color]." % Ui.hex(Ui.ORANGE))
	var found: Array[String] = []
	if truth["contraband"] != &"":
		found.append(Profiles.CONTRABAND_TEXT[truth["contraband"]])
	if truth["weapon"] != &"" and not _f["frisked"]:
		found.append(Profiles.WEAPON_TEXT[truth["weapon"]])
		_f["frisked"] = true
	if found.is_empty():
		_result("Nothing illegal found.")
	else:
		_f["found_legal"] = basis != "none"
		_result("You find [b]%s[/b]." % " and ".join(found))


func _direct(id: StringName, index: int, text: String) -> void:
	_done[id] = true
	_narration(text)
	action_requested.emit(&"vehicle_command", {"index": index})


## TODO(tahmin): the citation and arrest summaries (only the warning screen is fixed).
func _rule(ruling: StringName, ids: Array) -> void:
	var evaluation := Scoring.evaluate(facts(), ruling, ids)
	var total: int = evaluation["total"]
	var items: Array = evaluation["items"]
	match ruling:
		&"warning":
			_result("You let them go with a verbal warning.")
		&"citation":
			var names := PackedStringArray()
			for id in ids:
				names.append(Charges.label(Charges.get_charge(id)))
			_result("You issue a citation: %s." % "; ".join(names))
			_result("Total fines: $%d" % Charges.total_fines(ids))
		&"arrest":
			var names2 := PackedStringArray()
			for id in ids:
				names2.append(String(Charges.get_charge(id)["name"]))
			_result("You handcuff the driver and read them their rights." if mode == Mode.STOP else "You book the suspect.")
			_result("Charges: %s." % "; ".join(names2))
	_result("[b]%s  %+d points[/b]" % [GOOD_STOP, total])
	for item: Dictionary in items:
		_result("  - %s (%+d)" % [item["text"], int(item["points"])])
	result = {"ruling": ruling, "points": total, "items": items, "charges": ids.duplicate(), "fines": Charges.total_fines(ids),
		"arrested": ruling == &"arrest", "plate": record["plate"], "name": record["owner"], "booking": mode == Mode.BOOKING}
	view = View.SUMMARY
	view_changed.emit()
	action_requested.emit(StringName(ruling), {"charges": ids, "points": total, "result": result})


## Facts for Scoring (and for TrafficStop's stop summary).
func facts() -> Dictionary:
	var truth: Dictionary = profile["truth"]
	return {
		"booking": mode == Mode.BOOKING, "violation": String(profile.get("violation", &"")), "truth": truth,
		"emergency": bool(profile.get("emergency", false)), "illegal_search": _f["illegal_search"],
		"illegal_frisk": _f["illegal_frisk"], "docs_checked": _f["docs_checked"], "plate_run": _f["plate_run"],
		"name_run": _f["name_run"], "fst_failed": _f["fst_failed"], "breath_over": _f["breath_over"],
		"found_legal": _f["found_legal"], "plain_view": _f["plain_view"], "evidence_ids": evidence_ids,
		"impaired_known": _f["fst_failed"] or _f["breath_over"],
		"wanted_known": (_f["name_run"] and bool(truth["warrant"])) or (_f["plate_run"] and bool(truth["stolen_vehicle"])),
	}


func driver_is_out() -> bool:
	return _f["out_of_car"]


# --- entries -------------------------------------------------------------------------------------------

func _add(bbcode: String, speaker: StringName, spoken: String = "") -> void:
	entries.append(bbcode)
	entry_added.emit(bbcode, speaker, spoken)


func _you(text: String) -> void:
	_add('You: "%s"' % text, &"you", text)


func _driver(text: String) -> void:
	if text.is_empty():
		return
	_add('Driver: "%s"' % text, &"driver", text)


func _narration(text: String) -> void:
	_add("[i]%s[/i]" % text, &"narration")


func _result(text: String) -> void:
	_add(text, &"result")


func _plain_result(text: String) -> void:
	_add(text, &"result")
