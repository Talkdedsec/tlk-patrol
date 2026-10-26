extends SceneTree
## Dev tool: finds the Open Sans width-axis value (75..100) that makes a string hit a target advance.
## godot --headless --path . --script res://scripts/hud/font_fit.gd
## Each row: [name, text, new_size, weight, italic, current_size, current_wdth, ref_ink, shot_ink]
## target advance = advance(current) * ref_ink / shot_ink, solved for wdth at new_size.

const ROWS := [
	["clock", "18:56  paused", 25, 400, false, 26, 100, 153, 163],
	["clock_digits", "17:22", 25, 400, false, 26, 100, 57, 61],
	["weather", "Cloudy", 26, 400, false, 26, 100, 77, 80],
	["score", "Score -2370", 18, 400, false, 18, 100, 98, 96],
	["duty", "Busy", 18, 400, false, 18, 100, 39, 38],
	["weapon", "Shotgun  4 / 18   LMB fire   RMB aim   hold R reload", 17, 400, false, 17, 100, 409, 399],
	["mission", "Talk to the people there and find out what happened.", 21, 400, false, 19, 100, 513, 471],
	["log", "Dispatch: 1-Adam-14, take the hit and run. Code 3.", 17, 400, false, 18, 100, 383, 418],
	["street", "Davidson Beltway  65 mph", 16, 400, false, 15, 100, 191, 181],
	["maphint", "Map  [,]", 13, 400, false, 12, 100, 40, 38],
	["els_title", "ELS SYSTEM", 17, 700, true, 18, 100, 91, 96],
	["els_status", "STAGE 3  Auto: Triple alternate", 13, 400, false, 13, 100, 175, 183],
	["radar_title", "RADAR", 16, 700, false, 17, 100, 50, 56],
]


func _adv(text: String, size: int, weight: int, wdth: int, italic: bool) -> float:
	return HudStyle.text_width(text, size, weight, wdth, italic)


func _initialize() -> void:
	for r in ROWS:
		var now := _adv(r[1], r[5], r[3], r[6], r[4])
		var target: float = now * float(r[7]) / float(r[8])
		var best := 100
		var best_err := 1e9
		for wdth in range(75, 101):
			var err := absf(_adv(r[1], r[2], r[3], wdth, r[4]) - target)
			if err < best_err:
				best_err = err
				best = wdth
		print("%-13s size %d wdth %d  (adv %.1f -> target %.1f, err %.1f, wdth100 adv %.1f)" % [
			r[0], r[2], best, now, target, best_err, _adv(r[1], r[2], r[3], 100, r[4])])
	quit()
