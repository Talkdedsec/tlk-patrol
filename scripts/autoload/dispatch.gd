extends Node
## Radio / dispatch log bus. The HUD listens to line_added.

signal line_added(text: String)

const MAX_LINES := 40

var lines: PackedStringArray = []


func say(text: String) -> void:
	lines.append(text)
	if lines.size() > MAX_LINES:
		lines.remove_at(0)
	line_added.emit(text)
