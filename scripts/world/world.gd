extends Node
## World autoload: procedural city, road graph, street queries, lighting and traffic signals.
## Contract: docs/MIMARI.md; API: docs/api/world.md.
##
##   World.build(root)                  builds the city under `root` (creates a "CityWorld" child)
##   World.spawn_point(name)            Transform3D on the ground (forward = -Z of the transform)
##   World.street_at(pos)               {name, speed_limit_mph, kind, edge_id, distance}
##   World.road_graph                   RoadGraph (nodes / edges / shortest_path ...)
##   World.set_time(hours) / set_weather("Clear" | "Cloudy")
##   World.traffic_light_state(node_id, axis)  "green" / "yellow" / "red"
##   World.map_texture() / World.minimap_image(center, extent_m, px)

signal built
signal weather_changed(name: String)

const MINIMAP_BG := Color("#0B0E14")
const MINIMAP_ROAD := Color("#8E9298")
const MINIMAP_HIGHLIGHT := Color("#D8C070")
const MAP_PIXELS_PER_METER := 0.5

var road_graph: RoadGraph
var lighting: Lighting
var signals: TrafficSignals
var city_root: Node3D
var spawn_points: Dictionary = {}
var is_built := false
var build_time_ms := 0

var _map_texture: ImageTexture


func build(root: Node3D) -> void:
	var t0 := Time.get_ticks_msec()
	if city_root != null and is_instance_valid(city_root):
		city_root.queue_free()
	city_root = Node3D.new()
	city_root.name = "CityWorld"
	root.add_child(city_root)
	road_graph = CityLayout.build_graph()
	spawn_points = CityLayout.spawn_points(road_graph)
	lighting = Lighting.new()
	city_root.add_child(lighting)
	signals = TrafficSignals.new()
	city_root.add_child(signals)
	var builder := CityBuilder.new()
	builder.build(city_root, road_graph, lighting, signals)
	var lamps: Array[Dictionary] = builder.lamp_points
	lighting.set_lamps(lamps)
	_map_texture = null
	is_built = true
	build_time_ms = Time.get_ticks_msec() - t0
	built.emit()


func set_time(hours: float) -> void:
	if lighting != null:
		lighting.set_time(hours)
	else:
		GameState.minutes = fposmod(hours, 24.0) * 60.0


func set_weather(weather_name: String) -> void:
	if lighting != null:
		lighting.set_weather(weather_name)
	else:
		GameState.set_weather(weather_name)
	weather_changed.emit(GameState.weather)


## Ground transform for a named spawn (see docs/api/world.md for the list). Unknown names return the origin.
func spawn_point(spawn_name: StringName) -> Transform3D:
	var key := String(spawn_name)
	if not spawn_points.has(key):
		push_warning("World.spawn_point: unknown spawn '%s'" % key)
		return Transform3D(Basis(), Vector3(0, 0.05, 0))
	var sp: Dictionary = spawn_points[key]
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(sp.heading_deg)), sp.pos + Vector3(0, 0.05, 0))


func spawn_names() -> PackedStringArray:
	return PackedStringArray(spawn_points.keys())


## Street information at a world position. Off-road positions return an empty name and a 25 mph default.
func street_at(pos: Vector3) -> Dictionary:
	if road_graph == null:
		return {"name": "", "speed_limit_mph": 25, "kind": "none", "edge_id": -1, "distance": INF}
	if CityLayout.PLAZA.grow(4.0).has_point(Vector2(pos.x, pos.z)):
		return {"name": "Davidson Plaza", "speed_limit_mph": 10, "kind": "lot", "edge_id": -1, "distance": 0.0}
	var n := road_graph.nearest_edge(pos)
	if n.is_empty():
		return {"name": "", "speed_limit_mph": 25, "kind": "none", "edge_id": -1, "distance": INF}
	var e: Dictionary = n.edge
	var reach: float = e.width * 0.5 + 6.0
	if n.dist > reach:
		return {"name": "", "speed_limit_mph": 25, "kind": "none", "edge_id": -1, "distance": n.dist}
	return {"name": e.name, "speed_limit_mph": e.limit_mph, "kind": e.kind, "edge_id": e.id, "distance": n.dist}


## Signal state for an axis ("ns" = travelling along Z, "ew" = along X) at a signalised node.
func traffic_light_state(node_id: StringName, axis: String) -> String:
	return signals.state(node_id, axis) if signals != null and signals.has_node_signal(node_id) else "green"


func traffic_light_state_for_heading(node_id: StringName, heading: Vector3) -> String:
	return signals.state_for_heading(node_id, heading) if signals != null and signals.has_node_signal(node_id) else "green"


## Ground point and heading on a lane. lane 0 = right lane of travel from edge end `a` towards `b`, negative = other direction.
func lane_transform(edge_id: int, s: float, forward := true, lane := 0) -> Transform3D:
	var e: Dictionary = road_graph.edges[edge_id]
	var p := road_graph.point_on_edge(e, s)
	var dir: Vector3 = p.dir if forward else -p.dir
	var right := -Vector3.UP.cross(dir)
	var lane_w: float = (e.width - 1.0) / maxf(e.lanes * 2.0, 2.0)
	var pos: Vector3 = p.pos + right * (lane_w * (0.5 + lane)) + Vector3(0, 0.05, 0)
	var basis := Basis.looking_at(dir, Vector3.UP)
	return Transform3D(basis, pos)


# ---- scene presets ---------------------------------------------------------------------------------------

## Camera transform that applies a scene preset (see ScenePresets.names()).
func camera_preset(preset_name: String) -> Transform3D:
	return ScenePresets.camera_transform(preset_name)


## Applies the preset's time, weather and lamp style; returns its info dictionary (fov, car, els, ref).
func apply_scene_preset(preset_name: String) -> Dictionary:
	var p := ScenePresets.info(preset_name)
	if p.is_empty():
		push_warning("World.apply_scene_preset: unknown preset '%s'" % preset_name)
		return p
	set_weather(p.weather)
	set_time(p.hours)
	if lighting != null:
		lighting.lamp_style = p.lamp
		lighting.night_boost = p.get("night_boost", 1.0)
		lighting.window_energy = p.get("window_energy", 2.4)
	return p


func scene_preset_names() -> PackedStringArray:
	return ScenePresets.names()


# ---- minimap / overview ----------------------------------------------------------------------------------------

## Whole-map top-down overview (0.5 px per metre). Use map_uv() to place markers.
func map_texture() -> Texture2D:
	if _map_texture == null and road_graph != null:
		var b := CityLayout.MAP_BOUNDS
		var size := Vector2i(int(b.size.x * MAP_PIXELS_PER_METER), int(b.size.y * MAP_PIXELS_PER_METER))
		var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		_draw_roads(img, b.position, b.size, "")
		_map_texture = ImageTexture.create_from_image(img)
	return _map_texture


func map_uv(pos: Vector3) -> Vector2:
	var b := CityLayout.MAP_BOUNDS
	return Vector2((pos.x - b.position.x) / b.size.x, (pos.z - b.position.y) / b.size.y)


## North-up top-down crop around `center` covering `extent_m` metres square, as a `px` x `px` image.
## `highlight` = street name drawn in yellow (the active route in the minimap).
func minimap_image(center: Vector3, extent_m: float, px: int, highlight := "") -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var origin := Vector2(center.x - extent_m * 0.5, center.z - extent_m * 0.5)
	_draw_roads(img, origin, Vector2(extent_m, extent_m), highlight)
	return img


func _draw_roads(img: Image, origin: Vector2, extent: Vector2, highlight: String) -> void:
	img.fill(MINIMAP_BG)
	var scale := Vector2(img.get_width() / extent.x, img.get_height() / extent.y)
	# Davidson Plaza drive aisles and entrances (world-space rects).
	var lot_color := MINIMAP_HIGHLIGHT if highlight == "Davidson Plaza" else MINIMAP_ROAD
	var pl := CityLayout.PLAZA
	var lot_rects: Array[Rect2] = [Rect2(pl.position.x, pl.position.y, pl.size.x, 4.0), Rect2(pl.position.x, pl.end.y - 4.0, pl.size.x, 4.0),
		Rect2(pl.position.x, pl.position.y, 4.0, pl.size.y), Rect2(pl.end.x - 4.0, pl.position.y, 4.0, pl.size.y),
		Rect2(pl.position.x + 64.0, 262.0, 12.0, 30.0), Rect2(pl.position.x + 254.0, 262.0, 12.0, 30.0)]
	var az := pl.position.y + 14.5
	while az < pl.end.y - 10.0:
		lot_rects.append(Rect2(pl.position.x, az - 3.75, pl.size.x, 7.5))
		az += 24.0
	for r in lot_rects:
		var px := Rect2i(Vector2((r.position.x - origin.x) * scale.x, (r.position.y - origin.y) * scale.y).round(), Vector2(maxf(r.size.x * scale.x, 3.0), maxf(r.size.y * scale.y, 3.0)).round())
		img.fill_rect(px, lot_color)
	for pass_i in 2:
		for e in road_graph.edges:
			var is_hl: bool = highlight != "" and e.name == highlight
			if (pass_i == 0) == is_hl:
				continue
			var pts: PackedVector3Array = e.points
			for i in pts.size() - 1:
				var a := Vector2((pts[i].x - origin.x) * scale.x, (pts[i].z - origin.y) * scale.y)
				var c := Vector2((pts[i + 1].x - origin.x) * scale.x, (pts[i + 1].z - origin.y) * scale.y)
				var w := maxf(5.0, e.width * 0.6 * scale.x)
				var r := Rect2(minf(a.x, c.x) - w * 0.5, minf(a.y, c.y) - w * 0.5, absf(a.x - c.x) + w, absf(a.y - c.y) + w)
				img.fill_rect(Rect2i(r.position.round(), r.size.round()), MINIMAP_HIGHLIGHT if is_hl else MINIMAP_ROAD)
