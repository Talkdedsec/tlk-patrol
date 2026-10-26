extends RefCounted
## Dev stand-in for World.road_graph: one straight road along Z, centred on center_x (see Adapters.graph_override).

var edge := {"id": 1, "name": "Test St", "width": 8.0}
var center_x := 0.0


func nearest_edge(pos: Vector3) -> Dictionary:
	return {"edge": edge, "dist": absf(pos.x - center_x), "point": Vector3(center_x, 0.0, pos.z), "t": 0.5}
