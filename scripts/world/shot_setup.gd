extends RefCounted
## Setup hook for scripts/dev/shot.gd. Reads env vars:
##   WS_SPOT   spawn name for the camera anchor (default hoover_st)
##   WS_CAM    "x,y,z,yaw_deg,pitch_deg" explicit camera (overrides the spawn)
##   WS_HOURS  game hour (float), WS_WEATHER Clear|Cloudy, WS_ELS=1 turns test-car ELS lights on
##   WS_DIST   camera distance from the spawn (default 9), WS_HEIGHT camera height (default 2.2), WS_AZIM orbit angle in degrees


static func run(scene: Node) -> void:
	var preset := OS.get_environment("WS_PRESET")
	if preset != "":
		scene.show_preset(preset)   # WS_PRESET applies a ScenePresets entry and ignores the other variables
		return
	var hours := OS.get_environment("WS_HOURS")
	if hours != "":
		World.set_time(float(hours))
	var weather := OS.get_environment("WS_WEATHER")
	if weather != "":
		World.set_weather(weather)
	var cam: Camera3D = scene.camera
	var spot := OS.get_environment("WS_SPOT")
	if spot == "":
		spot = "hoover_st"
	scene._teleport(spot)
	var dist := float(OS.get_environment("WS_DIST")) if OS.get_environment("WS_DIST") != "" else 9.0
	var height := float(OS.get_environment("WS_HEIGHT")) if OS.get_environment("WS_HEIGHT") != "" else 2.2
	var t: Transform3D = World.spawn_point(spot)
	var azim := OS.get_environment("WS_AZIM")
	scene.yaw = t.basis.get_euler().y + (deg_to_rad(float(azim)) if azim != "" else 0.0)
	cam.global_position = t.origin + Vector3(0, height, 0) + Basis(Vector3.UP, scene.yaw) * Vector3(0, 0, dist)
	var pitch := OS.get_environment("WS_PITCH")
	scene.pitch = deg_to_rad(float(pitch)) if pitch != "" else -0.12
	var explicit := OS.get_environment("WS_CAM")
	if explicit != "":
		var p := explicit.split(",")
		cam.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		scene.yaw = deg_to_rad(float(p[3]))
		scene.pitch = deg_to_rad(float(p[4]))
	scene._apply_camera()
	if OS.get_environment("WS_ELS") == "1":
		scene.set_els(true)
