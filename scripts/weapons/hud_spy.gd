extends Node
## Test double for the HUD weapon-line API (set_weapon_line / clear_weapon_line). Records what Weapons pushed.

var line := ""                        ## "Pistol 17 / 34" or "" when cleared
var set_count := 0
var clear_count := 0
var history: Array[String] = []


func set_weapon_line(weapon_name: String, magazine: int, reserve: int) -> void:
	line = "%s %d / %d" % [weapon_name, magazine, reserve]
	set_count += 1
	history.append(line)


func clear_weapon_line() -> void:
	line = ""
	clear_count += 1
	history.append("")
