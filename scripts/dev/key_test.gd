extends SceneTree
## Dev check for the weapon slot keys 1/2/3 in the real game scene.
## Headless cannot capture the mouse (Weapons ignores keys then), so this checks the key->action mapping and the slot handler.

func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(2.5).timeout
	var weapons: Node = root.get_node("Weapons")
	for pair in [[KEY_1, "weapon_1"], [KEY_2, "weapon_2"], [KEY_3, "weapon_3"], [KEY_5, "draw_weapon"]]:
		var ev := InputEventKey.new()
		ev.physical_keycode = pair[0]
		ev.pressed = true
		print("MAP ", OS.get_keycode_string(pair[0]), " -> ", pair[1], " = ", InputMap.has_action(pair[1]) and InputMap.event_is_action(ev, pair[1]))
	for id in [&"pistol", &"rifle", &"shotgun", &"shotgun", &"pistol"]:
		weapons.call("_slot_key", id)
		await create_timer(1.3).timeout
		print("SLOT ", id, " -> equipped=", weapons.get("equipped"), " state=", weapons.get("state"))
	quit()
