extends "res://scripts/hud/hud.gd"
## The game's HUD: the drawing is scripts/hud/hud.gd, but the lines that several modules write to go through one
## arbiter so they never overdraw each other:
##   - bottom prompt: Pursuit ("E  Cuff", "E  Process the suspect") > call scenes ("E  Talk") > TrafficStop > the seat ("E  Get in")
##   - weapon slot (top right): Taser lines > "Flashlight on   4 off" > the weapon line
##   - amber call offer and the gold mission line share one place: the offer hides the mission while it is up
## TrafficStop draws its prompt / offer / flashlight line on its own overlay (stop_overlay.gd); they are read from there
## each frame, the overlay's own labels are made transparent and the HUD draws them.

const Overlay := preload("res://scripts/traffic_stop/stop_overlay.gd")

## Source priorities of the bottom prompt (higher wins). `pursuit` is whoever calls set_prompt() directly (the Pursuit banner).
const PROMPT_PRIORITY := {&"pursuit": 40, &"scene": 30, &"stop": 20, &"seat": 10}
const SLOT_PRIORITY := {&"taser": 3, &"flash": 2, &"weapon": 1}
const FLASH_TEXT := "Flashlight on   4 off"

var _prompts: Dictionary = {}
var _shown_prompt := ""
var _slot: Dictionary = {}
var _slot_key := "-"
var _stop_overlay: CanvasLayer
var _overlay_hidden := false


func _process(_delta: float) -> void:
	if _stop_overlay == null or not is_instance_valid(_stop_overlay):
		if get_tree().root.get_node_or_null("TrafficStop") == null:
			return
		_stop_overlay = Overlay.of(get_tree())
		_overlay_hidden = false
	if not _overlay_hidden:
		_hide_overlay_labels()
	set_prompt_from(&"stop", String(_stop_overlay.call("prompt_text")))
	var offer := String(_stop_overlay.call("offer_text"))
	if offer != _offer.text:
		set_offer(offer)
	var flash: Variant = _stop_overlay.get("_flash")
	_set_slot(&"flash", {"lines": [FLASH_TEXT]} if flash is Label and (flash as Label).visible else {})


## The overlay keeps its state in its labels (visible flag), so they are hidden by transparency, not by `visible`.
func _hide_overlay_labels() -> void:
	var ready_count := 0
	for label_name in ["_prompt", "_offer", "_flash"]:
		var label: Variant = _stop_overlay.get(label_name)
		if label is Label:
			(label as Label).modulate.a = 0.0
			ready_count += 1
	_overlay_hidden = ready_count == 3


# --- prompt -------------------------------------------------------------------------------------------------------

## Direct callers (the Pursuit banner) are the `pursuit` source.
func set_prompt(text: String) -> void:
	set_prompt_from(&"pursuit", text)


func set_prompt_from(source: StringName, text: String) -> void:
	if text.is_empty():
		if not _prompts.has(source):
			return
		_prompts.erase(source)
	else:
		_prompts[source] = text
	var best := ""
	var best_priority := -1
	for key: StringName in _prompts:
		var priority: int = PROMPT_PRIORITY.get(key, 5)
		if priority > best_priority:
			best_priority = priority
			best = _prompts[key]
	if best != _shown_prompt:
		_shown_prompt = best
		_prompt.text = best
		_prompt.visible = not best.is_empty()


## The prompt that is on screen right now.
func prompt_text() -> String:
	return _shown_prompt


# --- offer / mission ----------------------------------------------------------------------------------------------

func set_offer(text: String) -> void:
	_offer.text = text
	_offer.visible = not text.is_empty()
	_mission.visible = not _mission.text.is_empty() and text.is_empty()


func set_mission(text: String) -> void:
	_mission.text = text
	_mission.visible = not text.is_empty() and not _offer.visible


func mission_text() -> String:
	return _mission.text


# --- weapon slot ----------------------------------------------------------------------------------------------------

func set_weapon_line(weapon_name: String, magazine: int, reserve: int) -> void:
	_set_slot(&"weapon", {"name": weapon_name, "mag": magazine, "reserve": reserve})


func clear_weapon_line() -> void:
	_set_slot(&"weapon", {})


## Taser lines (Pursuit) and the HUD state player; an empty array frees the slot.
func set_equipment_lines(lines: Array) -> void:
	_set_slot(&"taser", {} if lines.is_empty() else {"lines": lines})


func _set_slot(source: StringName, value: Dictionary) -> void:
	if value.is_empty():
		if not _slot.has(source):
			return
		_slot.erase(source)
	else:
		_slot[source] = value
	var best: StringName = &""
	var best_priority := 0
	for key: StringName in _slot:
		var priority: int = SLOT_PRIORITY.get(key, 1)
		if priority > best_priority:
			best_priority = priority
			best = key
	var key_text := "" if best == &"" else "%s|%s" % [best, str(_slot[best])]
	if key_text == _slot_key:
		return
	_slot_key = key_text
	if best == &"":
		_weapon.visible = false
	elif best == &"weapon":
		var w: Dictionary = _slot[best]
		_style_weapon(T_WEAPON)
		_weapon.text = "%s  %d / %d   LMB fire   RMB aim   hold R reload" % [w["name"], w["mag"], w["reserve"]]
		_weapon.visible = true
	else:
		_style_weapon(T_EQUIP)
		_weapon.text = "\n".join(PackedStringArray(_slot[best]["lines"]))
		_weapon.visible = true


## Text of the weapon slot as drawn ("" when hidden). For tests.
func weapon_slot_text() -> String:
	return _weapon.text if _weapon.visible else ""


func offer_text() -> String:
	return _offer.text if _offer.visible else ""


func reset() -> void:
	_prompts.clear()
	_shown_prompt = ""
	_slot.clear()
	_slot_key = "-"
	super.reset()
