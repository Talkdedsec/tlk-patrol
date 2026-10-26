extends RefCounted
## --setup for scripts/dev/shot.gd on scenes/main.tscn. Environment variables:
##   GS_STAGE   foot (default) | drive (seated instantly) | exit (seated, then gets out)
##   GS_HOURS   time of day, e.g. 21.5 for the night shot
##   GS_SIREN   siren tone for the ELS shot (yelp, wail ...), switches lights on
##   GS_CRUISE  mph: drives straight at this speed (use with --frames 240 or more)
##   GS_TRAFFIC 0 removes the ambient cars
##   GS_CAM     seat: side camera on the driver seat (GS_DOOR=1 opens the door, GS_HIDE=Body,Door_FL hides model nodes)
## Run:  GS_STAGE=drive araclar/godot.sh --script res://scripts/dev/shot.gd -- --scene res://scenes/main.tscn \
##        --setup res://scripts/game/shot_setup.gd --out C:/tmp/g.png --frames 60 --no-capture


static func run(scene: Node) -> void:
	var stage := OS.get_environment("GS_STAGE")
	var hours := OS.get_environment("GS_HOURS")
	var siren := OS.get_environment("GS_SIREN")
	var cruise := OS.get_environment("GS_CRUISE")
	if OS.get_environment("GS_TRAFFIC") == "0":
		scene.hooks.clear_traffic()
	if not hours.is_empty():
		World.set_time(float(hours))
	if stage == "drive" or stage == "exit" or not cruise.is_empty():
		scene.seat.enter(scene.patrol_vehicle, true)
	if not siren.is_empty():
		Els.set_siren(StringName(siren))
	if not cruise.is_empty():
		scene.seat.scripted_drive = true
		var driver := (load("res://scripts/game/auto_drive.gd") as GDScript).new() as Node
		scene.add_child(driver)
		driver.call("follow_straight", scene.patrol_vehicle, 600.0, float(cruise))
	if stage == "exit":
		scene.seat.exit()
	var cam_mode := OS.get_environment("GS_CAM")
	if cam_mode == "seat":
		# side view into the driver window, door shut or open (GS_DOOR=1)
		if OS.get_environment("GS_DOOR") == "1":
			scene.patrol_vehicle.open_driver_door()
		var car: Vehicle = scene.patrol_vehicle
		for node_name in OS.get_environment("GS_HIDE").split(",", false):   # e.g. Body,Door_FL to look at the seat
			var node := car.get_node_or_null("Model/" + node_name) as Node3D
			if node != null:
				node.visible = false
		var cam := Camera3D.new()
		scene.add_child(cam)
		var seat_pos := car.seat_transform(&"driver").origin
		cam.global_position = seat_pos + car.global_transform.basis * Vector3(-2.4, 0.9, 0.6)
		cam.look_at(seat_pos + Vector3(0.0, 0.5, 0.0), Vector3.UP)
		cam.fov = 55.0
		cam.make_current()
