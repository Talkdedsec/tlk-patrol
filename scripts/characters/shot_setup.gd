extends RefCounted
## shot.gd --setup helper: puts the test-bench officer into a weapon state before the screenshot.
## Use: --setup res://scripts/characters/shot_setup.gd --stage unarmed|ready|aim|fire --weapon pistol|rifle|shotgun


static func run(scene: Node) -> void:
	var args := OS.get_cmdline_user_args()
	var stage := "unarmed"
	var weapon := &"pistol"
	for i in args.size() - 1:
		if args[i] == "--stage":
			stage = args[i + 1]
		elif args[i] == "--weapon":
			weapon = StringName(args[i + 1])
	var officer: Officer
	for child in scene.get_children():
		if child is Officer:
			officer = child
	if officer == null:
		return
	officer.mouse_sensitivity = 0.0
	officer.pitch = -0.08
	if stage == "run":
		Input.action_press("move_forward")
		return
	if stage == "unarmed":
		return
	officer.set_loadout([weapon])
	officer.draw_weapon(weapon)
	if stage == "aim" or stage == "fire" or stage == "aimwalk":
		Input.action_press("aim")
	if stage == "aimwalk":
		Input.action_press("move_right")
	if stage == "fire":
		await scene.get_tree().create_timer(1.3).timeout
		officer.notify_shot()
