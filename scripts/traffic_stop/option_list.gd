extends Control
## Scrollable option list of the traffic stop panel: section headers, 34 px rows with hover/pressed shades,
## checkbox rows for the charge forms and a thin scrollbar.

const Ui := preload("res://scripts/mdt/ui_kit.gd")

signal chosen(id: StringName)

const ROW_STEP := 34.0
const ROW_HEIGHT := 33.0
const HEADER_HEIGHT := 20.0
const TEXT_SIZE := 17
const HEADER_SIZE := 13
const THUMB_WIDTH := 8.0

var rows: Array[Dictionary] = []
var scroll: float = 0.0

var _hover := -1
var _pressed := -1


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


## Replaces the rows; the scroll offset is kept (clamped) unless reset is true.
func set_rows(new_rows: Array[Dictionary], reset: bool = false) -> void:
	rows = new_rows
	if reset:
		scroll = 0.0
	scroll = clampf(scroll, 0.0, max_scroll())
	_hover = _row_at(get_local_mouse_position()) if is_inside_tree() else -1
	queue_redraw()


func content_height() -> float:
	var total := 0.0
	for row in rows:
		total += HEADER_HEIGHT if row["kind"] == "header" else ROW_STEP
	return total


func max_scroll() -> float:
	return maxf(content_height() - size.y, 0.0)


func scroll_to_end() -> void:
	scroll = max_scroll()
	queue_redraw()


func _row_rect(index: int) -> Rect2:
	var y := -scroll
	for i in rows.size():
		var height := HEADER_HEIGHT if rows[i]["kind"] == "header" else ROW_STEP
		if i == index:
			return Rect2(0.0, y, size.x - 6.0, height if rows[i]["kind"] == "header" else ROW_HEIGHT)
		y += height
	return Rect2()


func _row_at(pos: Vector2) -> int:
	var y := -scroll
	for i in rows.size():
		var height := HEADER_HEIGHT if rows[i]["kind"] == "header" else ROW_STEP
		if pos.y >= y and pos.y < y + height:
			return i if rows[i]["kind"] != "header" and pos.x < size.x - 6.0 else -1
		y += height
	return -1


func _draw() -> void:
	var y := -scroll
	for i in rows.size():
		var row := rows[i]
		if row["kind"] == "header":
			if y + HEADER_HEIGHT > 0.0 and y < size.y:
				draw_string(Ui.font(600), Vector2(0.0, y + 14.5), String(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_SIZE, Ui.HEADER_TEXT)
			y += HEADER_HEIGHT
			continue
		if y + ROW_STEP > 0.0 and y < size.y:
			var rect := Rect2(0.0, y, size.x - 6.0, ROW_HEIGHT)
			var shade := Ui.ROW_BG
			if i == _pressed and i == _hover:
				shade = Ui.ROW_PRESSED
			elif i == _hover:
				shade = Ui.ROW_HOVER
			draw_rect(rect, shade)
			var text_x := 4.0
			if row["kind"] == "check":
				text_x = 24.0
				var box := Rect2(8.0, y + 10.0, 13.0, 13.0)
				draw_rect(box, Color("101114"))
				draw_rect(box, Color("25282D"), false, 1.0)
				if row.get("checked", false):
					draw_rect(box.grow(-2.0), Color("58BDFF"))
			draw_string(Ui.font(460), Vector2(text_x, y + 22.5), String(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, Ui.OPTION_TEXT)
			var tag := String(row.get("tag", ""))
			if not tag.is_empty():
				var tag_x := text_x + Ui.text_width(String(row["label"]), TEXT_SIZE, 460) + 6.0
				draw_string(Ui.font(600), Vector2(tag_x, y + 22.5), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Ui.ORANGE)
		y += ROW_STEP
	var total := content_height()
	if total > size.y + 0.5:
		var thumb_height := maxf(size.y * size.y / total, 24.0)
		var thumb_y := (size.y - thumb_height) * (scroll / max_scroll())
		draw_rect(Rect2(size.x - THUMB_WIDTH - 0.0, thumb_y, THUMB_WIDTH, thumb_height), Ui.SCROLL_THUMB)


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var hover := _row_at(motion.position)
		if hover != _hover:
			_hover = hover
			queue_redraw()
		return
	var button := event as InputEventMouseButton
	if button == null:
		return
	match button.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if button.pressed:
				_scroll_by(-ROW_STEP * 1.5)
		MOUSE_BUTTON_WHEEL_DOWN:
			if button.pressed:
				_scroll_by(ROW_STEP * 1.5)
		MOUSE_BUTTON_LEFT:
			var index := _row_at(button.position)
			if button.pressed:
				_pressed = index
				queue_redraw()
			else:
				var was := _pressed
				_pressed = -1
				queue_redraw()
				if was >= 0 and was == index and was < rows.size():
					chosen.emit(rows[was]["id"])


func _scroll_by(amount: float) -> void:
	scroll = clampf(scroll + amount, 0.0, max_scroll())
	_hover = _row_at(get_local_mouse_position())
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1
		_pressed = -1
		queue_redraw()
