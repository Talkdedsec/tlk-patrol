extends SceneTree
## Dev tool: renders a scene for N frames in an exact-size SubViewport and saves a PNG.
## Needs a GPU window (do not pass --headless).
##
## godot --path . --script res://scripts/dev/shot.gd -- --scene res://scenes/main.tscn --out C:/tmp/a.png \
##       [--frames 10] [--size 1920x1080] [--setup res://scripts/dev/some_setup.gd]
##
## --setup: a script with `static func run(scene: Node) -> void`, called once the scene is ready (use it to fake state).


func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var scene_path: String = args.get("scene", "res://scenes/main.tscn")
	var out: String = args.get("out", "user://shot.png")
	var frames := int(args.get("frames", "10"))
	var size_parts := String(args.get("size", "1920x1080")).split("x")
	var size := Vector2i(int(size_parts[0]), int(size_parts[1]))

	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	viewport.add_child(scene)
	await process_frame
	await process_frame
	if args.has("setup"):
		var setup: GDScript = load(args["setup"])
		setup.call("run", scene)
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(out)
	print("SHOT ", image.get_size(), " -> ", out)
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
