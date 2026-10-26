class_name CityLayout
extends RefCounted
## Original layout of Davidson City (street names and speed limits are fixed in the layout,
## the placement is our own design). X = east, Z = south, units metres.

const PLAZA := Rect2(50.0, 290.0, 330.0, 230.0)   # Davidson Plaza parking lot (x, z, w, d)
const MAP_BOUNDS := Rect2(-2300.0, -760.0, 4600.0, 1520.0)
const GROUND_BOUNDS := Rect2(-2300.0, -1300.0, 4600.0, 2600.0)

const MAPLE_X := -120.0
const HOOVER_X := 0.0
const ELM_X := 120.0
const CEDAR_X := -240.0
const OAK_X := 240.0
const ROW_8TH := -350.0
const ROW_BIRCH := -250.0
const ROW_ASH := -50.0
const ROW_9TH := -150.0
const ROW_WESTERN := 50.0
const ROW_DAVIDSON := 250.0
const HIGHWAY_Z := -690.0
const KILN_X := 600.0
const ROUTE7_X := -1100.0
const LAKEVIEW_X := 1000.0
const COUNTY18_Z := 700.0


static func build_graph() -> RoadGraph:
	var g := RoadGraph.new()
	# Residential grid: 5 north-south streets x 5 east-west streets (+ Davidson Blvd), blocks ~120 x 100 m.
	var cols := {"c": CEDAR_X, "m": MAPLE_X, "h": HOOVER_X, "e": ELM_X, "o": OAK_X}
	var rows := {"8": ROW_8TH, "b": ROW_BIRCH, "9": ROW_9TH, "k": ROW_ASH, "w": ROW_WESTERN, "d": ROW_DAVIDSON}
	for c in cols:
		for r in rows:
			var control := "all_way"
			if r == "d":
				control = "signal" if c == "h" else "minor_stop"
			g.add_node(StringName(c + r), Vector3(cols[c], 0, rows[r]), control)
	# Hoover St northern end meets I-40; Busco Rd is the rural stretch in between.
	g.add_node(&"hi", Vector3(HOOVER_X, 0, HIGHWAY_Z))
	g.add_node(&"hs", Vector3(HOOVER_X, 0, COUNTY18_Z))
	g.add_node(&"wl", Vector3(-400, 0, ROW_WESTERN))
	g.add_node(&"we", Vector3(400, 0, ROW_WESTERN))
	g.add_node(&"dwl", Vector3(-500, 0, ROW_DAVIDSON))
	g.add_node(&"kd", Vector3(KILN_X, 0, ROW_DAVIDSON), "signal")
	g.add_node(&"de1", Vector3(800, 0, ROW_DAVIDSON))
	g.add_node(&"lvd", Vector3(LAKEVIEW_X, 0, ROW_DAVIDSON), "minor_stop")
	g.add_node(&"de2", Vector3(2200, 0, ROW_DAVIDSON))
	g.add_node(&"dwf", Vector3(-2200, 0, ROW_DAVIDSON))
	g.add_node(&"r7d", Vector3(ROUTE7_X, 0, ROW_DAVIDSON), "minor_stop")
	g.add_node(&"kn", Vector3(KILN_X, 0, -100))
	g.add_node(&"ik", Vector3(KILN_X, 0, HIGHWAY_Z))
	g.add_node(&"kf", Vector3(KILN_X, 0, 450), "minor_stop")
	g.add_node(&"ks", Vector3(KILN_X, 0, COUNTY18_Z))
	g.add_node(&"fe", Vector3(900, 0, 450))
	g.add_node(&"r7n", Vector3(ROUTE7_X, 0, HIGHWAY_Z))
	g.add_node(&"r7s", Vector3(ROUTE7_X, 0, COUNTY18_Z))
	g.add_node(&"lvn", Vector3(LAKEVIEW_X, 0, HIGHWAY_Z))
	g.add_node(&"lvs", Vector3(LAKEVIEW_X, 0, COUNTY18_Z))
	g.add_node(&"c18e", Vector3(1500, 0, COUNTY18_Z))
	g.add_node(&"iw", Vector3(-1500, 0, HIGHWAY_Z))
	g.add_node(&"ie", Vector3(1500, 0, HIGHWAY_Z))

	# Residential grid edges. lanes = lanes per direction, width in metres.
	g.add_edge("Busco Rd", &"hi", &"h8", 1, 45, 9.0, "rural")
	var col_names := {"c": "Cedar St", "m": "Maple St", "h": "Hoover St", "e": "Elm St", "o": "Oak St"}
	var row_names := {"8": "8th St", "b": "Birch St", "9": "9th St", "k": "Ash St", "w": "Western Ave"}
	var row_order := ["8", "b", "9", "k", "w", "d"]
	var col_order := ["c", "m", "h", "e", "o"]
	for c in col_order:
		for i in row_order.size() - 1:
			var limit := 25
			g.add_edge(col_names[c], StringName(c + row_order[i]), StringName(c + row_order[i + 1]), 1, limit, 9.0, "residential")
	for r in ["8", "b", "9", "k", "w"]:
		var width := 10.0 if r == "w" else 9.0
		var limit := 30 if r == "w" else 25
		for i in col_order.size() - 1:
			g.add_edge(row_names[r], StringName(col_order[i] + r), StringName(col_order[i + 1] + r), 1, limit, width, "residential")
	g.add_edge("Western Ave", &"wl", &"cw", 1, 30, 10.0, "residential")
	g.add_edge("Western Ave", &"ow", &"we", 1, 30, 10.0, "residential")
	g.add_edge("Hoover St", &"hd", &"hs", 1, 30, 9.0, "residential")
	# Davidson Blvd: wide commercial boulevard (2 lanes each way) and the 65 mph Beltway at both ends.
	g.add_edge("Davidson Beltway", &"dwf", &"r7d", 2, 65, 15.0, "highway")
	g.add_edge("Davidson Beltway", &"r7d", &"dwl", 2, 65, 15.0, "highway")
	g.add_edge("Davidson Blvd", &"dwl", &"cd", 1, 45, 13.0, "arterial")
	g.add_edge("Davidson Blvd", &"cd", &"md", 1, 45, 13.0, "arterial")
	g.add_edge("Davidson Blvd", &"md", &"hd", 1, 45, 13.0, "arterial")
	g.add_edge("Davidson Blvd", &"hd", &"ed", 1, 45, 13.0, "arterial")
	g.add_edge("Davidson Blvd", &"ed", &"od", 1, 45, 13.0, "arterial")
	g.add_edge("Davidson Blvd", &"od", &"kd", 1, 45, 13.0, "arterial")
	g.add_edge("Davidson Blvd", &"kd", &"de1", 1, 45, 13.0, "arterial")
	g.add_edge("Davidson Beltway", &"de1", &"lvd", 2, 65, 15.0, "highway")
	g.add_edge("Davidson Beltway", &"lvd", &"de2", 2, 65, 15.0, "highway")
	# Kiln Rd industrial strip.
	g.add_edge("Kiln Rd", &"ik", &"kn", 1, 45, 9.0, "rural")
	g.add_edge("Kiln Rd", &"kn", &"kd", 1, 25, 10.0, "industrial")
	g.add_edge("Kiln Rd", &"kd", &"kf", 1, 25, 10.0, "industrial")
	g.add_edge("Kiln Rd", &"kf", &"ks", 1, 25, 10.0, "industrial")
	g.add_edge("Foundry Rd", &"kf", &"fe", 1, 30, 9.0, "industrial")
	# Rural network and the interstate.
	g.add_edge("I-40", &"iw", &"r7n", 2, 65, 15.0, "highway")
	g.add_edge("I-40", &"r7n", &"hi", 2, 65, 15.0, "highway")
	g.add_edge("I-40", &"hi", &"ik", 2, 65, 15.0, "highway")
	g.add_edge("I-40", &"ik", &"lvn", 2, 65, 15.0, "highway")
	g.add_edge("I-40", &"lvn", &"ie", 2, 65, 15.0, "highway")
	g.add_edge("Route 7", &"r7n", &"r7d", 2, 65, 14.0, "highway")
	g.add_edge("Route 7", &"r7d", &"r7s", 2, 65, 14.0, "highway")
	g.add_edge("Lakeview Rd", &"lvn", &"lvd", 1, 45, 9.0, "rural")
	g.add_edge("Lakeview Rd", &"lvd", &"lvs", 1, 45, 9.0, "rural")
	g.add_edge("County Rd 18", &"r7s", &"hs", 1, 45, 8.5, "rural")
	g.add_edge("County Rd 18", &"hs", &"ks", 1, 45, 8.5, "rural")
	g.add_edge("County Rd 18", &"ks", &"lvs", 1, 45, 8.5, "rural")
	g.add_edge("County Rd 18", &"lvs", &"c18e", 1, 45, 8.5, "rural")
	return g


## Named spawn points: {pos: Vector3 (ground), heading_deg: float} where heading 0 = facing -Z (north), 90 = east.
static func spawn_points(g: RoadGraph) -> Dictionary:
	var lot_center := PLAZA.get_center()
	return {
		"hoover_st": {"pos": Vector3(3.5, 0.0, -60.0), "heading_deg": 0.0},
		"hoover_9th": {"pos": Vector3(3.5, 0.0, -110.0), "heading_deg": 0.0},
		"western_ave": {"pos": Vector3(-60.0, 0.0, ROW_WESTERN + 3.0), "heading_deg": 90.0},
		"ninth_st": {"pos": Vector3(-60.0, 0.0, ROW_9TH + 3.0), "heading_deg": 90.0},
		"davidson_blvd": {"pos": Vector3(-300.0, 0.0, ROW_DAVIDSON + 4.0), "heading_deg": 90.0},
		"davidson_plaza": {"pos": Vector3(lot_center.x - 60.0, 0.0, lot_center.y), "heading_deg": 270.0},
		"parking_lot": {"pos": Vector3(lot_center.x, 0.0, lot_center.y), "heading_deg": 270.0},
		"kiln_rd": {"pos": Vector3(KILN_X - 3.5, 0.0, 330.0), "heading_deg": 180.0},
		"foundry_rd": {"pos": Vector3(700.0, 0.0, 450.0 + 3.0), "heading_deg": 90.0},
		"highway": {"pos": Vector3(-600.0, 0.0, HIGHWAY_Z + 3.7), "heading_deg": 90.0},
		"beltway": {"pos": Vector3(-1900.0, 0.0, ROW_DAVIDSON + 3.7), "heading_deg": 90.0},
		"route_7": {"pos": Vector3(ROUTE_7_LANE, 0.0, 100.0), "heading_deg": 180.0},
		"pursuit_start": {"pos": Vector3(-2000.0, 0.0, ROW_DAVIDSON + 3.7), "heading_deg": 90.0},
	}


const ROUTE_7_LANE := ROUTE7_X - 3.7
