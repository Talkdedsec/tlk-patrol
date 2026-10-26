class_name TrafficSignals
extends Node3D
## Signalised intersections: a fixed-time cycle per node, lens meshes switched between lit/dark materials.
## Cycle (seconds): NS green 22, yellow 3, all-red 1.5, EW green 18, yellow 3, all-red 1.5 = 49 s.
## TODO(tahmin): signal durations are our estimate.

signal state_changed(node_id: StringName, ns: String, ew: String)

const GREEN_NS := 22.0
const GREEN_EW := 18.0
const YELLOW := 3.0
const ALL_RED := 1.5
const CYCLE := GREEN_NS + GREEN_EW + 2.0 * YELLOW + 2.0 * ALL_RED

var _nodes: Dictionary = {}   # id -> {offset: float, lenses: {ns: Array[MeshInstance3D x3 per head], ew: ...}, last: String}
var _mats: Dictionary = {}


func _init() -> void:
	name = "TrafficSignals"
	for c in ["red", "yellow", "green"]:
		var col: Color = {"red": Color("#FF2A1E"), "yellow": Color("#FFC21A"), "green": Color("#2CFF7A")}[c]
		var on := StandardMaterial3D.new()
		on.albedo_color = col
		on.emission_enabled = true
		on.emission = col
		on.emission_energy_multiplier = 3.0
		var off := StandardMaterial3D.new()
		off.albedo_color = col.darkened(0.82)
		_mats[c] = {"on": on, "off": off}


## Registers a signal head mesh instance triple: lenses = [red, yellow, green] for the given axis ("ns" / "ew").
func add_head(node_id: StringName, axis: String, lenses: Array) -> void:
	if not _nodes.has(node_id):
		_nodes[node_id] = {"offset": float(abs(hash(node_id)) % 1000) / 1000.0 * CYCLE, "heads": {"ns": [], "ew": []}, "last": ""}
	_nodes[node_id].heads[axis].append(lenses)


## State of one axis ("ns" = traffic along Z, "ew" = traffic along X): "green" / "yellow" / "red".
func state(node_id: StringName, axis: String) -> String:
	var off: float = _nodes[node_id].offset if _nodes.has(node_id) else float(abs(hash(node_id)) % 1000) / 1000.0 * CYCLE
	var t := fposmod(Time.get_ticks_msec() / 1000.0 + off, CYCLE)
	var ns := "red"
	var ew := "red"
	if t < GREEN_NS:
		ns = "green"
	elif t < GREEN_NS + YELLOW:
		ns = "yellow"
	elif t < GREEN_NS + YELLOW + ALL_RED:
		pass
	elif t < GREEN_NS + YELLOW + ALL_RED + GREEN_EW:
		ew = "green"
	elif t < GREEN_NS + YELLOW + ALL_RED + GREEN_EW + YELLOW:
		ew = "yellow"
	return ns if axis == "ns" else ew


## State for a vehicle travelling along `heading` (any Vector3, y ignored) at a signal node.
func state_for_heading(node_id: StringName, heading: Vector3) -> String:
	return state(node_id, "ns" if absf(heading.z) > absf(heading.x) else "ew")


func has_node_signal(node_id: StringName) -> bool:
	return _nodes.has(node_id)


func _process(_delta: float) -> void:
	for id in _nodes:
		var n: Dictionary = _nodes[id]
		var ns := state(id, "ns")
		var ew := state(id, "ew")
		var key := ns + "/" + ew
		if key == n.last:
			continue
		n.last = key
		_paint(n.heads.ns, ns)
		_paint(n.heads.ew, ew)
		state_changed.emit(id, ns, ew)


func _paint(heads: Array, current: String) -> void:
	for head in heads:
		for i in 3:
			var color: String = ["red", "yellow", "green"][i]
			(head[i] as MeshInstance3D).material_override = _mats[color].on if color == current else _mats[color].off
