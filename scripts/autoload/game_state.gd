extends Node
## HUD-facing global state: clock, weather, score, duty status.
## Formats: "13:13  paused", "Cloudy", "Score -1820", "Busy".

signal changed

# Traffic stop and pursuit: 1 real second = 1 game minute. The clock can show "paused".
const GAME_MINUTES_PER_REAL_SECOND := 1.0

var minutes: float = 13.0 * 60.0 + 13.0
var clock_running: bool = false
var weather: String = "Cloudy"
var score: int = 0
var duty_status: String = "Available"


func _process(delta: float) -> void:
	if not clock_running:
		return
	var before := int(minutes)
	minutes += delta * GAME_MINUTES_PER_REAL_SECOND
	if int(minutes) != before:
		changed.emit()


func clock_text() -> String:
	var total := int(minutes) % 1440
	var text := "%02d:%02d" % [floori(total / 60.0), total % 60]
	return text if clock_running else text + "  paused"


func set_score(value: int) -> void:
	score = value
	changed.emit()


func set_weather(value: String) -> void:
	weather = value
	changed.emit()


func set_duty_status(value: String) -> void:
	duty_status = value
	changed.emit()
