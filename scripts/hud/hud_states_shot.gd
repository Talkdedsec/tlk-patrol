extends SceneTree
## Dev tool: renders every HUD state of scenarios/data/hud_states.json on a black 1920x1080 canvas, one PNG per state.
## Needs a GPU window (no --headless).
##
## araclar/godot.sh --script res://scripts/hud/hud_states_shot.gd -- --out C:/tmp/hud_states [--only id1,id2]

const DEFAULT_OUT := "user://hud_states"


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void:  # never leave a stuck process behind
		push_error("hud_states_shot watchdog: aborted")
		quit(2))
	var args := _parse(OS.get_cmdline_user_args())
	var out: String = args.get("out", DEFAULT_OUT)
	var only: PackedStringArray = String(args.get("only", "")).split(",", false)
	DirAccess.make_dir_recursive_absolute(out)
	AudioServer.set_bus_mute(0, true)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.size = Vector2(1920, 1080)
	viewport.add_child(bg)
	var hud: Node = load("res://scripts/hud/hud.gd").new()
	viewport.add_child(hud)
	await process_frame
	await process_frame
	hud.call("set_map_texture", MinimapPanel.make_test_map())

	var states := HudStatePlayer.load_states()
	var done := 0
	for s in states:
		if not only.is_empty() and not only.has(s["id"]):
			continue
		HudStatePlayer.apply(hud, s)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("%s/%s.png" % [out, s["id"]])
		done += 1
	print("STATES ", done, " -> ", out)
	quit()


func _parse(argv: PackedStringArray) -> Dictionary:
	var result := {}
	var i := 0
	while i < argv.size():
		if argv[i].begins_with("--") and i + 1 < argv.size():
			result[argv[i].substr(2)] = argv[i + 1]
			i += 2
		else:
			i += 1
	return result
