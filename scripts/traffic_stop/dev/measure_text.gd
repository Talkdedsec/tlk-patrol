extends SceneTree
## Prints in-engine text widths for the calibration of font sizes.
const Ui := preload("res://scripts/mdt/ui_kit.gd")


func _initialize() -> void:
	var tests := [
		["title", "MOBILE DATA TERMINAL  ·  COMPUTER AIDED DISPATCH", 600, false, 412, [14, 15, 16]],
		["tab", "DISPATCH", 600, false, 72, [14, 15, 16]],
		["nocall", "NO CALL ASSIGNED", 700, false, 154, [15, 16, 17]],
		["body", "Patrol your area. New calls show here and come in over the", 400, false, 458, [15, 16, 17]],
		["radio", "Dispatch: 10-4, 6-Adam-15.", 400, false, 178, [13, 14, 15]],
		["footer", "Tab or Esc to close  ·  the car can still be driven", 400, false, 274, [12, 13, 14]],
		["status", "1-ADAM-12   AVAILABLE", 600, false, 169, [14, 15, 16]],
		["runbtn", "RUN THE PLATE OF THE VEHICLE AHEAD", 700, false, 286, [14, 15, 16]],
		["dlg title", "Traffic stop: KEA-9291  (Halvorsen Ranger SUV)", 600, false, 447, [19, 20, 21]],
		["dlg narr", "Engine off, window down, both hands on the wheel.", 400, true, 400, [17, 18, 19]],
		["dlg opt", "Do you know why I stopped you?", 400, false, 253, [16, 17, 18]],
		["dlg hdr", "PAPERS AND MDT", 600, false, 111, [12, 13, 14]],
	]
	for t in tests:
		var out := "%s target %d:" % [t[0], t[4]]
		for size: int in t[5]:
			out += "  %d->%.0f" % [size, Ui.text_width(t[1], size, t[2], t[3])]
		print(out)
	var extra := [["body", "Patrol your area. New calls show here and come in over the", 458, 16], ["dlg opt", "Do you know why I stopped you?", 253, 17],
		["footer", "Tab or Esc to close  ·  the car can still be driven", 274, 13], ["running", "Running plate KEA-9291...", 195, 17],
		["owner", "Owner: Darnell Foster", 169, 17], ["radio", "Dispatch: 10-4, 6-Adam-15.", 178, 14]]
	for t in extra:
		var out := "%s target %d size %d:" % [t[0], t[2], t[3]]
		for weight in [300, 350, 400, 450, 500, 600]:
			out += "  w%d->%.0f" % [weight, Ui.text_width(t[1], t[3], weight, false)]
		print(out)
	quit()
