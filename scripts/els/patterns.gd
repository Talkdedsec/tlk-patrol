class_name ElsPatterns
extends RefCounted
## ELS light patterns: name -> timed frame sequence over 10 light cells (bit i = cell i on).
## Timings are tuned values (60 fps sampling of the panel cell row).
## Patterns marked guess have only a name; their timing is invented.
##
## Two sources: the six patterns tied to sirens (Double cross, Counter-rotating, Triple alternate, Sparkle,
## Six-burst cross fast, Bounce) keep their hand-built timing measured on the new panel (above). Every other name
## (57 names, `Stage 3: <name>` toasts) is loaded from pattern_data.json, measured at 60 fps on the old
## panel's FRONT/REAR/PODS/WIG rows. rows_at() always comes from that file.

const CELL_COUNT := 10
const FRAME := 1.0 / 60.0

const RED := Color("ff1010")
const BLUE := Color("1a50ff")
const WHITE := Color("ffffff")

const DATA_PATH := "res://scripts/els/pattern_data.json"

## Names in the order PTRN < > steps through them: the 57 names in their panel order,
## then "Slow alternate" (traffic stop only; timing is a guess).
const ORDER: Array[String] = [
	"Rear warning", "Response triple", "Response quad cross", "Priority sweep", "Scene (officer out)",
	"Single alternate", "Double alternate", "Triple alternate", "Quad alternate", "Quint alternate",
	"Six-burst alternate", "Double alternate slow", "Quad alternate fast", "Triple alternate with white",
	"Long burn alternate", "Hyper burst alternate", "Single together", "Double together", "Triple together",
	"Quad together", "Slow pulse together", "Double cross", "Triple cross", "Quad cross", "Six-burst cross fast",
	"Front-back double", "Front-back quad", "Front-back crossed", "Sweep driver to passenger",
	"Sweep passenger to driver", "Bounce", "Centre out", "Outside in", "Comet", "Sweep and flash",
	"Crossing waves", "Centre out and flash", "Rotator", "Rotator slow", "Counter-rotating", "Beacon",
	"Random strobe", "Chaos", "Sparkle", "Tri-colour alternate", "Colour cycle", "Colour sweep",
	"Red, white and blue burst", "White strobe split", "Amber rear, colours front", "Steady burn and flash",
	"Steady burn, rear flashing", "Steady dim", "Rear alternate", "Rear amber alternate", "Rear sweep", "Auto",
	"Slow alternate",
]

## Patterns whose 10-cell timing comes from the hand-built (new panel) measurements below.
const LEGACY := ["Double cross", "Counter-rotating", "Triple alternate", "Sparkle", "Six-burst cross fast", "Bounce",
	"Slow alternate"]

const ROW_NAMES := ["FRONT", "REAR", "PODS", "WIG"]
const CLASS_COLORS := {
	"R": Color("ff0000"), "B": Color("0060ff"), "W": Color("ffffff"), "C": Color("fef5e2"),
	"r": Color("731414"), "b": Color("142e73"), "A": Color("ffa000"),
}

# Measured group masks (cell indices).
const MASK_P := [2, 3, 4, 5, 7, 8, 9]
const MASK_Q := [0, 1, 2, 4, 5, 6, 7]
const MASK_TA := [0, 1, 3, 4, 5, 7]
const MASK_TB := [2, 4, 5, 6, 8, 9]

static var _cache: Dictionary = {}
static var _data: Dictionary = {}
static var _data_loaded := false
static var _sparkle: PackedInt32Array = PackedInt32Array()


static func mask(cells: Array) -> int:
	var m := 0
	for c in cells:
		m |= 1 << int(c)
	return m


## Flash group: `count` flashes of `on` seconds separated by `gap`, then `dark` seconds, as [dur, mask] steps.
static func _burst(cells: Array, count: int, on: float, gap: float, dark: float) -> Array:
	var steps: Array = []
	var m := mask(cells)
	for i in count:
		steps.append([on, m])
		if i < count - 1:
			steps.append([gap, 0])
	steps.append([dark, 0])
	return steps


## Scales every step duration so the whole sequence lasts exactly `period`.
static func _fit(steps: Array, period: float) -> Dictionary:
	var total := 0.0
	for s in steps:
		total += s[0]
	var scale := period / total
	var times := PackedFloat32Array()
	var masks := PackedInt32Array()
	var t := 0.0
	for s in steps:
		times.append(t)
		masks.append(s[1])
		t += s[0] * scale
	return {"period": period, "times": times, "masks": masks}


static func _build(pattern_name: String) -> Dictionary:
	var steps: Array = []
	var period := 1.0
	match pattern_name:
		"Double cross":
			# P, Q, P, Q: two flashes each (3-5 frames on, ~5 off, ~13 dark), full cycle 1.683 s.
			period = 1.683
			for g in [MASK_P, MASK_Q, MASK_P, MASK_Q]:
				steps.append_array(_burst(g, 2, 4.7 * FRAME, 4.5 * FRAME, 12.0 * FRAME))
		"Triple alternate":
			# Group A x3 (8.5 frames on, 4.5 off, 18 dark), group B x3 (dark 17), cycle 1.683 s.
			period = 1.683
			steps.append_array(_burst(MASK_TA, 3, 8.5 * FRAME, 4.5 * FRAME, 18.0 * FRAME))
			steps.append_array(_burst(MASK_TB, 3, 8.5 * FRAME, 4.5 * FRAME, 17.0 * FRAME))
		"Six-burst cross fast":
			# P and Q, six 3-frame flashes each (2.5 off), 8 dark; cycle 1.25 s.
			period = 1.25
			steps.append_array(_burst(MASK_P, 6, 3 * FRAME, 2.5 * FRAME, 8 * FRAME))
			steps.append_array(_burst(MASK_Q, 6, 3 * FRAME, 2.5 * FRAME, 8 * FRAME))
		"Counter-rotating":
			# Sub-cycle 0.967 s: left block, centre pair, right block, then cells 2 and 7 hold.
			period = 0.967
			steps = [
				[2 * FRAME, mask(MASK_TA)],
				[0.17, mask([4, 5])],
				[0.16, mask([2, 4, 5, 6, 7, 8, 9])],
				[0.55, mask([2, 7])],
			]
		"Bounce":
			# Period 0.817 s: right half 4x strobe (centre pair stays lit between), then left half.
			period = 0.817
			for i in 4:
				steps.append([3 * FRAME, mask([5, 6, 7, 8, 9])])
				steps.append([2.5 * FRAME, mask([5, 7])])
			for i in 4:
				steps.append([2.5 * FRAME, mask([0, 1, 2, 3, 4])])
				steps.append([3.5 * FRAME, mask([2, 4])])
		"Slow alternate": # guess
			period = 1.6
			steps = [[0.8, mask([0, 1, 2, 3, 4])], [0.8, mask([5, 6, 7, 8, 9])]]
		"Double alternate slow": # guess
			period = 1.6
			steps = [
				[0.15, mask([0, 1, 2, 3, 4])], [0.1, 0], [0.15, mask([0, 1, 2, 3, 4])], [0.4, 0],
				[0.15, mask([5, 6, 7, 8, 9])], [0.1, 0], [0.15, mask([5, 6, 7, 8, 9])], [0.4, 0],
			]
		"Slow pulse together": # guess
			period = 1.2
			steps = [[0.6, mask(range(10))], [0.6, 0]]
		"Rotator slow": # guess
			period = 1.6
			for i in 8:
				steps.append([0.2, mask([i, (i + 1) % 10])])
		"Response quad cross": # guess, base period 2.667 s measured on the old panel
			period = 2.667
			for g in [MASK_P, MASK_Q]:
				steps.append_array(_burst(g, 4, 5 * FRAME, 5 * FRAME, 20 * FRAME))
		_:
			steps = [[1.0, 0]]
	return _fit(steps, period)


static func _sparkle_frames() -> PackedInt32Array:
	if _sparkle.is_empty():
		# Each cell flashes 2-4 frames at random; mean 3.7 cells lit. Looped 16 s table.
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260
		var frames := 960
		_sparkle.resize(frames)
		var remaining: Array[int] = []
		remaining.resize(CELL_COUNT)
		remaining.fill(0)
		for f in frames:
			var m := 0
			for c in CELL_COUNT:
				if remaining[c] > 0:
					remaining[c] -= 1
					m |= 1 << c
				elif rng.randf() < 0.17: # start probability tuned for ~37% duty at mean 3 frames on
					remaining[c] = rng.randi_range(1, 3)  # this frame + 1..3 more = 2-4 frames
					m |= 1 << c
			_sparkle[f] = m
	return _sparkle


static func has_pattern(pattern_name: String) -> bool:
	return ORDER.has(pattern_name)


static func _load_data() -> void:
	if _data_loaded:
		return
	_data_loaded = true
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_warning("ElsPatterns: %s missing, only the legacy patterns are available" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary and parsed.has("patterns")):
		return
	for pattern_name in parsed["patterns"]:
		var src: Dictionary = parsed["patterns"][pattern_name]
		var times := PackedFloat32Array()
		var rows: Array = []
		var t := 0.0
		for step in src["steps"]:
			times.append(t)
			t += float(step[0])
			rows.append(PackedStringArray([step[1], step[2], step[3], step[4]]))
		# Steady-burn patterns never light the PODS row: their 10-cell mask then comes from FRONT/REAR (dim cells count).
		var pods_dead := true
		for r in rows:
			if (r as PackedStringArray)[2].replace(".", "").replace("r", "").replace("b", "") != "":
				pods_dead = false
		_data[pattern_name] = {"period": maxf(t, 0.05), "times": times, "rows": rows, "pods_dead": pods_dead}


static func _data_step(pattern_name: String, t: float) -> int:
	var p: Dictionary = _data[pattern_name]
	var x := fposmod(t, p["period"])
	var times: PackedFloat32Array = p["times"]
	var idx := 0
	for i in times.size():
		if times[i] > x:
			break
		idx = i
	return idx


## The four rows (FRONT, REAR, PODS, WIG) of a pattern at time t as 10-character strings: '.' off, R red, B blue,
## W white, C cream, r/b dim red/blue, A amber (measured on the old panel at 60 fps).
static func rows_at(pattern_name: String, t: float) -> PackedStringArray:
	_load_data()
	if not _data.has(pattern_name):
		return PackedStringArray([".........." , "..........", "..........", ".........."])
	var p: Dictionary = _data[pattern_name]
	return p["rows"][_data_step(pattern_name, t)]


## Colors of the 10 cells of one row (0 FRONT, 1 REAR, 2 PODS, 3 WIG); off = black.
static func row_colors(pattern_name: String, row: int, t: float) -> PackedColorArray:
	var text := rows_at(pattern_name, t)[row]
	var colors := PackedColorArray()
	for i in CELL_COUNT:
		var ch := text[i]
		colors.append(CLASS_COLORS[ch] if CLASS_COLORS.has(ch) else Color(0, 0, 0))
	return colors


## 10 pods colors honouring white and other measured cell colors (legacy patterns use red left, blue right).
static func colors_at(pattern_name: String, t: float) -> PackedColorArray:
	_load_data()
	if LEGACY.has(pattern_name) or not _data.has(pattern_name):
		var base := default_colors()
		var m := mask_at(pattern_name, t)
		for i in CELL_COUNT:
			if not m & (1 << i):
				base[i] = Color(0, 0, 0)
		return base
	if _data[pattern_name]["pods_dead"]:
		var front := row_colors(pattern_name, 0, t)
		var rear := row_colors(pattern_name, 1, t)
		var merged := PackedColorArray()
		for i in CELL_COUNT:
			merged.append(front[i] if front[i] != Color(0, 0, 0) else rear[i])
		return merged
	return row_colors(pattern_name, 2, t)


## Cell bit mask of `pattern_name` at time `t` seconds.
static func mask_at(pattern_name: String, t: float) -> int:
	_load_data()
	if not LEGACY.has(pattern_name) and _data.has(pattern_name):
		var rows := rows_at(pattern_name, t)
		var dead: bool = _data[pattern_name]["pods_dead"]
		var bits := 0
		for i in CELL_COUNT:
			var ch := rows[2][i]
			if dead:
				if rows[0][i] != "." or rows[1][i] != ".":
					bits |= 1 << i
			elif ch != "." and ch != "r" and ch != "b":
				bits |= 1 << i
		return bits
	if pattern_name == "Sparkle":
		var table := _sparkle_frames()
		return table[int(floorf(t * 60.0)) % table.size()]
	if not _cache.has(pattern_name):
		_cache[pattern_name] = _build(pattern_name)
	var p: Dictionary = _cache[pattern_name]
	var x := fposmod(t, p["period"])
	var times: PackedFloat32Array = p["times"]
	var idx := times.size() - 1
	for i in times.size():
		if times[i] > x:
			idx = i - 1
			break
	return (p["masks"] as PackedInt32Array)[maxi(idx, 0)]


static func period_of(pattern_name: String) -> float:
	_load_data()
	if not LEGACY.has(pattern_name) and _data.has(pattern_name):
		return _data[pattern_name]["period"]
	if pattern_name == "Sparkle":
		return 16.0
	if not _cache.has(pattern_name):
		_cache[pattern_name] = _build(pattern_name)
	return _cache[pattern_name]["period"]


## Default world colors per cell: left half red, right half blue.
static func default_colors() -> PackedColorArray:
	var colors := PackedColorArray()
	for i in CELL_COUNT:
		colors.append(RED if i < CELL_COUNT / 2 else BLUE)
	return colors
