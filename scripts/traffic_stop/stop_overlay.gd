extends CanvasLayer
## Overlay extras the HUD does not draw: the top-centre toast slot, the call offer
## and chase prompts, the bottom interaction prompt, the flashlight line and the SCENE COMMANDS box.
## One shared instance: Overlay.of(tree). Set Overlay.parent_override before first use to host it inside a SubViewport.

const Ui := preload("res://scripts/mdt/ui_kit.gd")
const Adapters := preload("res://scripts/traffic_stop/adapters.gd")

const CENTER_X := 960.0
const TOAST_Y := 75.0
const CHASE_Y := 125.0
const OFFER_Y := 175.0
const PROMPT_Y := 978.0
const FLASH_Y := 151.0
const RIGHT_EDGE := 1902.0
const SCENE_BOX := Rect2(30, 415, 300, 325)
const SCENE_COMMANDS: Array[String] = [
	"Pull up further", "Pull into the next street on the right", "Follow me", "Stop right there",
	"Flares: slow passing traffic", "Flares: close the lane", "Close the road (traffic detours)", "Pick the flares up",
]

static var parent_override: Node = null
static var _instance: CanvasLayer = null

var _toast: Label
var _offer: Label
var _chase: Label
var _prompt: Label
var _flash: Label
var _scene_box: Panel
var _scene_title: Label
var _scene_sub: Label
var _scene_lines: Array[Label] = []
var _toast_token := 0
var _last_toast := ""
var _offer_text := ""
var _chase_text := ""
var _prompt_text := ""
var _chase_on_hud := false
var _last_toast_until := 0


## The shared overlay (created on first use, added under parent_override or the tree root).
static func of(tree: SceneTree) -> CanvasLayer:
	if _instance != null and is_instance_valid(_instance):
		return _instance
	_instance = (load("res://scenes/traffic_stop/stop_overlay.tscn") as PackedScene).instantiate() as CanvasLayer
	var host: Node = parent_override if parent_override != null and is_instance_valid(parent_override) else tree.root
	host.add_child.call_deferred(_instance)
	return _instance


## Moves the shared overlay under another node (screenshot tool, scenarios that render in a SubViewport).
static func reparent_to(node: Node) -> void:
	parent_override = node
	if _instance != null and is_instance_valid(_instance) and _instance.get_parent() != node:
		_instance.get_parent().remove_child(_instance)
		node.add_child(_instance)


func _init() -> void:
	layer = 12
	# Sizes: in-engine widths tuned (offer 455 px, chase 475, prompt 209, flashlight 151).
	_toast = _center_label(24, Ui.WHITE, TOAST_Y, 500)
	_offer = _center_label(20, Ui.AMBER, OFFER_Y, 500)
	_chase = _center_label(26, Ui.CHASE_RED, CHASE_Y, 500)
	_prompt = _center_label(23, Ui.WHITE, PROMPT_Y, 450)
	_flash = Ui.label("Flashlight on   4 off", 17, Ui.PROMPT_GREEN, 450, false, true)
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_flash.position = Vector2(RIGHT_EDGE - 400.0, FLASH_Y - 12.0)
	_flash.size = Vector2(400.0, 24.0)
	_flash.visible = false
	add_child(_flash)
	_build_scene_box()


func _center_label(size: int, color: Color, y_center: float, weight: int = 400) -> Label:
	var node := Ui.label("", size, color, weight, false, true)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	node.position = Vector2(CENTER_X - 600.0, y_center - 16.0)
	node.size = Vector2(1200.0, 32.0)
	node.visible = false
	add_child(node)
	return node


# --- toast slot (single slot: a new toast replaces the old one) ----------------------------------

## Shows a toast in the top-centre slot: through the HUD's single slot when a HUD exists, else on this overlay.
func toast(text: String, seconds: float = 2.5, color: Color = Ui.WHITE) -> void:
	_last_toast = text
	_last_toast_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	if is_inside_tree() and Adapters.hud_toast(get_tree(), text, seconds):
		return
	toast_local(text, seconds, color)


## Toast drawn by the overlay itself (no HUD in the scene).
func toast_local(text: String, seconds: float = 2.5, color: Color = Ui.WHITE) -> void:
	_last_toast = text
	_last_toast_until = Time.get_ticks_msec() + int(seconds * 1000.0)
	if not is_inside_tree():
		await ready
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.visible = true
	_toast_token += 1
	var token := _toast_token
	await get_tree().create_timer(seconds).timeout
	if token == _toast_token:
		_toast.visible = false


func clear_toast() -> void:
	_toast_token += 1
	_toast.visible = false
	_last_toast_until = 0


## The toast text currently on screen ("" when none). Used by tests and scenarios.
func toast_text() -> String:
	return _last_toast if Time.get_ticks_msec() < _last_toast_until else ""


# --- amber call offer / red chase notice / bottom prompt / flashlight line --------------------------
# The chase notice goes through the HUD's set_chase_nearby when a HUD exists (473 px vs 475 px target); the other
# lines are drawn by the overlay, sized from in-engine widths against target widths. The *_text() getters
# return what was last set.

func _hud() -> Node:
	return Adapters.hud(get_tree()) if is_inside_tree() else null


## Amber offer line. Drawn by the overlay: HUD.set_offer measured 507 px wide against a 455 px target.
func set_offer(text: String) -> void:
	_offer_text = text
	_offer.text = text
	_offer.visible = not text.is_empty()


## Red "Chase nearby, 0.2 mi   C join   Z call off" (miles); clear_chase() hides it.
func set_chase_miles(miles: float) -> void:
	_chase_text = "Chase nearby, %.1f mi   C join   Z call off" % miles
	var hud := _hud()
	if hud != null and hud.has_method("set_chase_nearby"):
		hud.call("set_chase_nearby", miles * 5280.0)
		_chase_on_hud = true
		_chase.visible = false
		return
	_chase.text = _chase_text
	_chase.visible = true


func clear_chase() -> void:
	_chase_text = ""
	_chase.visible = false
	if _chase_on_hud:
		_chase_on_hud = false
		var hud := _hud()
		if hud != null and hud.has_method("clear_pursuit"):
			hud.call("clear_pursuit")


func offer_text() -> String:
	return _offer_text


func chase_text() -> String:
	return _chase_text


# --- bottom prompt: "E  Get in" ------------------------------------------------------------------

## Drawn by the overlay (HUD.set_prompt is ~5 % larger than needed); the game's own "E  Get in" hides while this is set.
func set_prompt(text: String) -> void:
	_prompt_text = text
	_prompt.text = text
	_prompt.visible = not text.is_empty()


func prompt_text() -> String:
	return _prompt_text


func set_flashlight_line(on: bool) -> void:
	_flash.visible = on


# --- SCENE COMMANDS box --------------------------------------------------------------------------

func _build_scene_box() -> void:
	_scene_box = Panel.new()
	_scene_box.position = SCENE_BOX.position
	_scene_box.size = SCENE_BOX.size
	_scene_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_box.add_theme_stylebox_override("panel", Ui.box(Color(0.04, 0.06, 0.09, 0.9), 10))
	_scene_box.visible = false
	add_child(_scene_box)
	_scene_title = Ui.label("SCENE COMMANDS  (M to close)", 15, Ui.WHITE)
	_scene_title.position = Vector2(14, 12)
	_scene_box.add_child(_scene_title)
	_scene_sub = Ui.label("Stopped car: ", 15, Ui.WHITE)
	_scene_sub.position = Vector2(14, 37)
	_scene_box.add_child(_scene_sub)
	for i in SCENE_COMMANDS.size():
		var line := Ui.label("%d  %s" % [i + 1, SCENE_COMMANDS[i]], 15, Ui.WHITE)
		line.position = Vector2(14, 87 + i * 25)
		_scene_box.add_child(line)
		_scene_lines.append(line)


func show_scene_commands(plate: String) -> void:
	_scene_sub.text = "Stopped car: " + plate
	_scene_box.visible = true


func hide_scene_commands() -> void:
	_scene_box.visible = false


func scene_commands_visible() -> bool:
	return _scene_box.visible
