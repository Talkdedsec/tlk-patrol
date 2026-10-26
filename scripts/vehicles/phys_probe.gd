extends SceneTree
## Dev probe: measures how VehicleBody3D engine_force / brake map to acceleration (headless ok).

func _initialize() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 2, 4000)
	fs.shape = box
	fs.position.y = -1.0
	floor_body.add_child(fs)
	world.add_child(floor_body)
	var car := VehicleBody3D.new()
	car.mass = 1800.0
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.9, 0.9, 4.8)
	cs.shape = b
	cs.position.y = 0.75
	car.add_child(cs)
	for p in [Vector3(-0.85, 0.37, -1.5), Vector3(0.85, 0.37, -1.5), Vector3(-0.85, 0.37, 1.5), Vector3(0.85, 0.37, 1.5)]:
		var w := VehicleWheel3D.new()
		w.position = p + Vector3(0, 0.12, 0)
		w.wheel_radius = 0.37
		w.wheel_rest_length = 0.12
		w.suspension_travel = 0.2
		w.suspension_stiffness = 80.0
		w.suspension_max_force = 40000.0
		w.damping_compression = 1.0
		w.damping_relaxation = 1.3
		w.wheel_friction_slip = 1.5
		w.use_as_traction = p.z > 0
		w.use_as_steering = p.z < 0
		car.add_child(w)
	car.position.y = 0.3
	world.add_child(car)
	for i in 120:
		await physics_frame
	print("REST y=", car.position.y)
	var args := OS.get_cmdline_user_args()
	var mode := String(args[0]) if args.size() > 0 else "engine"
	var val := float(args[1]) if args.size() > 1 else 1000.0
	if mode == "engine":
		car.engine_force = val
		var t := 0.0
		for i in 240:
			await physics_frame
			t += 1.0 / 60.0
			if i % 60 == 59:
				print("t=%.1f v=%.2f m/s" % [t, -car.linear_velocity.dot(car.global_transform.basis.z)])
	else:
		car.linear_velocity = -car.global_transform.basis.z * 30.0
		car.brake = val
		var t := 0.0
		for i in 120:
			await physics_frame
			t += 1.0 / 60.0
			if i % 20 == 19:
				print("t=%.2f v=%.2f m/s" % [t, -car.linear_velocity.dot(car.global_transform.basis.z)])
	quit()
