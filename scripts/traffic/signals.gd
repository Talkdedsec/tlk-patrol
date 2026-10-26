extends RefCounted
## Fallback traffic-signal cycle, used only when the World module exposes no signal state.
## Two axes (ns / ew) with green, yellow and an all-red gap; every node gets its own phase offset.

const CYCLE := 72.0


static func state(node_id: StringName, approach_dir: Vector3, t: float) -> StringName:
	var offset := float(absi(hash(String(node_id))) % 24)
	var tt := fposmod(t + offset, CYCLE)
	var ns := absf(approach_dir.z) >= absf(approach_dir.x)
	if ns:
		if tt < 30.0:
			return &"green"
		if tt < 33.0:
			return &"yellow"
		return &"red"
	if tt < 36.0:
		return &"red"
	if tt < 66.0:
		return &"green"
	if tt < 69.0:
		return &"yellow"
	return &"red"
