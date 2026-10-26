extends Control
## Traffic stop dialog panel: right-side overlay, title, scrolling narrative (RichTextLabel,
## italics for scene text), option list below. Rect 1360..1896 x 64..1055 of the 1920x1080 canvas.
## The panel only renders a DialogModel; clicking calls model.choose(id), Esc calls model.back_or_away().

const Ui := preload("res://scripts/mdt/ui_kit.gd")
const OptionList := preload("res://scripts/traffic_stop/option_list.gd")

const RECT := Rect2(1360.0, 64.0, 536.0, 991.0)
const NARRATIVE_RECT := Rect2(1374.0, 111.0, 516.0, 489.0)
const LIST_RECT := Rect2(1374.0, 603.0, 507.0, 442.0)

signal closed

var model
var _title: Label
var _narrative: RichTextLabel
var _list: Control
var _has_text := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Panel.new()
	bg.position = RECT.position
	bg.size = RECT.size
	bg.add_theme_stylebox_override("panel", Ui.box(Ui.PANEL_BG, 12, Ui.PANEL_EDGE, 1))
	add_child(bg)
	_title = Ui.label("", 20, Ui.WHITE, 600)
	_title.position = Vector2(1374.0, 78.0)
	add_child(_title)
	_narrative = Ui.rich(17, Ui.WHITE, -1, 430)
	_narrative.position = NARRATIVE_RECT.position
	_narrative.size = NARRATIVE_RECT.size
	_narrative.scroll_following = true
	Ui.style_scrollbar(_narrative.get_v_scroll_bar(), Ui.SCROLL_THUMB, 8.0)
	add_child(_narrative)
	_list = OptionList.new()
	_list.position = LIST_RECT.position
	_list.size = LIST_RECT.size
	_list.chosen.connect(_on_chosen)
	add_child(_list)


## Binds a DialogModel and renders its current state.
func open(dialog_model) -> void:
	if model != null:
		_unbind()
	model = dialog_model
	model.entry_added.connect(_on_entry)
	model.view_changed.connect(_refresh_options)
	_title.text = model.title
	_narrative.clear()
	_has_text = false
	for line: String in model.entries:
		_append(line)
	_refresh_options(true)
	visible = true


func close() -> void:
	if model != null:
		_unbind()
	model = null
	visible = false


func _unbind() -> void:
	if model.entry_added.is_connected(_on_entry):
		model.entry_added.disconnect(_on_entry)
	if model.view_changed.is_connected(_refresh_options):
		model.view_changed.disconnect(_refresh_options)


func _append(bbcode: String) -> void:
	if _has_text:
		_narrative.newline()
	_narrative.append_text(bbcode)
	_has_text = true


func _on_entry(bbcode: String, _speaker: StringName, _spoken: String) -> void:
	_append(bbcode)


var _last_view := -1


func _refresh_options(reset: bool = false) -> void:
	if model == null:
		return
	# Opening a charge form (or leaving it) starts at the top of the list.
	var changed_view: bool = model.view != _last_view
	_last_view = model.view
	_list.set_rows(model.options(), reset or changed_view)
	if changed_view and model.view == model.View.SUMMARY:
		_narrative.scroll_to_line(maxi(_narrative.get_line_count() - 1, 0))


func _on_chosen(id: StringName) -> void:
	if model != null:
		model.choose(id)


func _input(event: InputEvent) -> void:
	if visible and model != null and event is InputEventKey and event.pressed and not event.echo and event.is_action("close_menu"):
		get_viewport().set_input_as_handled()
		model.back_or_away()


## Narrative text without markup (tests).
func narrative_text() -> String:
	return _narrative.get_parsed_text()


func list() -> Control:
	return _list
