extends SceneTree
## Headless self-test of the World API:  araclar/godot.sh --headless --script res://scripts/world/selftest.gd
## Prints PASS/FAIL lines; exit code is not used by the engine wrapper, so grep for FAIL.

var fails := 0


func check(label: String, ok: bool, extra := "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("  " + extra if extra != "" else ""))
	if not ok:
		fails += 1


func _initialize() -> void:
	var holder := Node3D.new()
	get_root().add_child(holder)
	await process_frame
	var w = get_root().get_node("World")
	w.build(holder)
	check("built", w.is_built, "%d ms" % w.build_time_ms)
	check("graph nodes/edges", w.road_graph.nodes.size() > 25 and w.road_graph.edges.size() > 40, "%d/%d" % [w.road_graph.nodes.size(), w.road_graph.edges.size()])
	var s: Dictionary = w.street_at(Vector3(2.0, 0, -60.0))
	check("street_at Hoover St", s.name == "Hoover St" and s.speed_limit_mph == 25, str(s))
	s = w.street_at(Vector3(-300.0, 0, 255.0))
	check("street_at Davidson Blvd", s.name == "Davidson Blvd" and s.speed_limit_mph == 45, str(s))
	s = w.street_at(Vector3(603.0, 0, 330.0))
	check("street_at Kiln Rd", s.name == "Kiln Rd" and s.speed_limit_mph == 25, str(s))
	s = w.street_at(Vector3(-600.0, 0, -690.0))
	check("street_at I-40", s.name == "I-40" and s.speed_limit_mph == 65, str(s))
	s = w.street_at(Vector3(200.0, 0, 400.0))
	check("street_at plaza", s.name == "Davidson Plaza", str(s))
	s = w.street_at(Vector3(300.0, 0, -500.0))
	check("street_at off-road", s.name == "", str(s))
	for n in w.spawn_names():
		var t: Transform3D = w.spawn_point(n)
		var st: Dictionary = w.street_at(t.origin)
		check("spawn %s" % n, st.name != "", "%s at %s" % [st.name, t.origin])
	var path: Array = w.road_graph.shortest_path(&"hi", &"ks")
	check("shortest_path hi->ks", path.size() > 3, str(path))
	var img: Image = w.minimap_image(Vector3(0, 0, 0), 200.0, 128, "Hoover St")
	check("minimap_image", img.get_width() == 128)
	check("map_texture", w.map_texture() != null and w.map_texture().get_width() > 1000)
	var st1: String = w.traffic_light_state(&"hd", "ns")
	check("signal state", st1 in ["green", "yellow", "red"], st1)
	w.set_time(6.75)
	w.set_weather("Cloudy")
	check("set_time/weather", is_equal_approx(w.lighting.hours, 6.75) and get_root().get_node("GameState").weather == "Cloudy")
	print("SELFTEST fails=", fails)
	quit()
