extends SceneTree
## Prints in-engine widths of overlay words and strings (font size calibration).
const Ui := preload("res://scripts/mdt/ui_kit.gd")


func _initialize() -> void:
	for weight in [400, 500]:
		for size in range(17, 24):
			print("OVL w%d size %d: Code %.1f Stolen %.1f respond %.1f pass %.1f space %.1f | code3 3sp %.0f code2 3sp %.0f" % [weight, size,
				Ui.text_width("Code", size, weight), Ui.text_width("Stolen", size, weight), Ui.text_width("respond", size, weight),
				Ui.text_width("pass", size, weight), Ui.text_width("a a", size, weight) - Ui.text_width("aa", size, weight),
				Ui.text_width("Code 3: Stolen vehicle.   Y respond   N pass   (24)", size, weight),
				Ui.text_width("Code 2: Trespassing.   Y respond   N pass   (24)", size, weight)])
	quit()
