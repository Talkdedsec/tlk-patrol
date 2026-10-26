class_name Lighting
extends Node3D
## Day/night cycle, weather, street lamp pools and light factories for vehicles.
## Follows GameState.minutes / GameState.weather unless `follow_game_state` is false.
## Night: near-black sky, cool blue ambient, white lamp pools,
## red/blue ELS light on the ground); dawn 05:40, pink-orange 06:45, blue sky 07:00.

signal lamps_changed(factor: float)

const WINDOW_SHADER := preload("res://scripts/world/shaders/window.gdshader")

## Spot lights assigned to the lamps nearest to the camera (the rest are drawn as cheap additive pools).
const LAMP_LIGHT_POOL := 14
const LAMP_LIGHT_SHADOWS := 4
const LAMP_REAL_RADIUS := 65.0
const LAMP_POOL_SIZE := 17.0

## Colors: [hour, top, horizon, ground, sun_energy, sun_color, ambient_color, ambient_energy, lamps, windows]
const KEYS := [
	[0.0, "#020204", "#07050B", "#040408", 0.0, "#FFD9A0", "#4A5A8A", 0.17, 1.0, 1.0],
	[5.0, "#020204", "#07050B", "#040408", 0.0, "#FFD9A0", "#4A5A8A", 0.17, 1.0, 1.0],
	[5.5, "#0A1228", "#1C2442", "#0A0E1C", 0.0, "#FFD9A0", "#4A5A8A", 0.17, 1.0, 1.0],
	[5.95, "#1B2748", "#6A4E6A", "#2A2030", 0.0, "#FFB080", "#7A82B8", 0.35, 1.0, 0.9],
	[6.4, "#3F5588", "#F09878", "#4A3A4A", 1.4, "#FFB080", "#9AA6D0", 0.85, 0.55, 0.6],
	[6.85, "#6A98CC", "#CBDCEC", "#6E7A86", 1.6, "#FFE0B8", "#B5C6E0", 0.36, 0.0, 0.1],
	[9.0, "#6F9CCB", "#C8D8E6", "#707C88", 0.7, "#FFF2DC", "#C0D0E8", 0.34, 0.0, 0.0],
	[13.0, "#6C9BCB", "#C6D8E8", "#707C88", 0.72, "#FFF6E6", "#C8D6EC", 0.34, 0.0, 0.0],
	[16.5, "#6F9CCB", "#C8D8E6", "#707C88", 0.7, "#FFF0D8", "#C0D0E8", 0.34, 0.0, 0.0],
	[17.2, "#5878B0", "#F0B882", "#6A6A74", 0.9, "#FFC890", "#B0B8D8", 0.45, 0.3, 0.3],
	[17.7, "#25365F", "#E0784C", "#3A3040", 0.22, "#FF9060", "#8C94C0", 0.26, 1.0, 0.9],
	[18.05, "#0A1030", "#3A2A44", "#14101C", 0.0, "#FF9060", "#4A5A8A", 0.19, 1.0, 1.0],
	[18.3, "#020204", "#07050B", "#040408", 0.0, "#FFD9A0", "#4A5A8A", 0.17, 1.0, 1.0],
	[24.0, "#020204", "#07050B", "#040408", 0.0, "#FFD9A0", "#4A5A8A", 0.17, 1.0, 1.0],
]

# TODO(tahmin): lamp color is neutral white; a traffic stop at night suggests sodium orange ("sodium" style).
const LAMP_COLORS := {"white": Color("#EAF0FF"), "sodium": Color("#FFB35A")}

# TODO(tahmin): headlight cone angles/range and ELS ground-light energy are tuned by eye.
## Headlight / ELS light specs for the vehicle module (see make_headlight / make_els_light).
const HEADLIGHT := {"energy": 7.0, "range": 28.0, "angle": 30.0, "pitch_deg": -9.0, "color": Color("#FFF6EA")}
const ELS_LIGHT := {"energy": 4.5, "range": 10.0}

var follow_game_state := true
var lamp_style := "white":
	set(v):
		lamp_style = v
		_apply_lamp_color()
		_apply()
var weather := "Clear"
var hours := 13.0
var moon_enabled := false
## Multiplies the night ambient energy (daytime pursuit scenes are much brighter).
var night_boost := 1.0:
	set(v):
		night_boost = v
		_apply()
## Emission energy of lit windows.
var window_energy := 2.4:
	set(v):
		window_energy = v
		_apply()
## Node whose position decides which lamps get real lights; defaults to the active camera.
var focus_node: Node3D

var environment: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var window_material: ShaderMaterial
var lamp_glow_material: StandardMaterial3D
var lamp_factor := 0.0

var _lamps: Array[Dictionary] = []     # {pos: head position, dir: Vector3 outward}
var _pool_lights: Array[SpotLight3D] = []
var _pool_mm: Array[MultiMeshInstance3D] = []
var _pool_mm_lamps: Array = []         # per chunk: Array of lamp indices
var _pool_strength: PackedFloat32Array = PackedFloat32Array()
var _assign_timer := 0.0
var _last_minutes := -1.0
var _cloud := 0.0
var _cloud_target := 0.0


func _init() -> void:
	name = "Lighting"
	window_material = ShaderMaterial.new()
	window_material.shader = WINDOW_SHADER
	lamp_glow_material = StandardMaterial3D.new()
	lamp_glow_material.resource_name = "lamp_glow"
	lamp_glow_material.albedo_color = Color("#2A2C30")
	lamp_glow_material.emission_enabled = true
	lamp_glow_material.emission_energy_multiplier = 0.0
	_apply_lamp_color()


func _ready() -> void:
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_curve = 0.12
	sky_material.ground_curve = 0.05
	sky_material.sun_angle_max = 8.0
	sky_material.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.1
	environment.glow_hdr_scale = 1.6
	environment.fog_enabled = true
	environment.fog_density = 0.0005
	environment.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = environment
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.light_angular_distance = 0.4
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color("#8FA8FF")
	moon.shadow_enabled = false
	moon.rotation_degrees = Vector3(-55.0, 70.0, 0.0)
	add_child(moon)

	for i in LAMP_LIGHT_POOL:
		var l := SpotLight3D.new()
		l.name = "LampLight%d" % i
		l.spot_angle = 68.0
		l.spot_angle_attenuation = 0.8
		l.spot_attenuation = 1.1
		l.light_energy = 14.0
		l.spot_range = 30.0
		l.shadow_enabled = i < LAMP_LIGHT_SHADOWS
		l.shadow_bias = 0.05
		l.light_specular = 0.2
		l.visible = false
		add_child(l)
		_pool_lights.append(l)
	_apply_lamp_color()
	if follow_game_state:
		hours = GameState.minutes / 60.0
		weather = GameState.weather
	_cloud = 1.0 if weather == "Cloudy" else 0.0
	_cloud_target = _cloud
	_apply()


func _process(delta: float) -> void:
	if follow_game_state:
		if absf(GameState.minutes - _last_minutes) > 0.05 or GameState.weather != weather:
			_last_minutes = GameState.minutes
			hours = fposmod(GameState.minutes / 60.0, 24.0)
			weather = GameState.weather
			_cloud_target = 1.0 if weather == "Cloudy" else 0.0
			_apply()
	if not is_equal_approx(_cloud, _cloud_target):
		_cloud = move_toward(_cloud, _cloud_target, delta / 6.0)  # weather fades over ~6 s
		_apply()
	_assign_timer -= delta
	if _assign_timer <= 0.0:
		_assign_timer = 0.2
		_assign_lamp_lights()


func set_time(h: float) -> void:
	hours = fposmod(h, 24.0)
	if follow_game_state:
		GameState.minutes = hours * 60.0
		_last_minutes = GameState.minutes
	_apply()


func set_weather(name_: String) -> void:
	weather = "Cloudy" if name_.to_lower() == "cloudy" else "Clear"
	_cloud_target = 1.0 if weather == "Cloudy" else 0.0
	_cloud = _cloud_target
	if follow_game_state:
		GameState.set_weather(weather)
	_apply()


func is_night() -> bool:
	return lamp_factor > 0.5


## Registers lamp heads: Array of {pos: Vector3 (light position), dir: Vector3 (toward the road, unused for now)}.
func set_lamps(lamps: Array[Dictionary]) -> void:
	_lamps = lamps
	_build_pool_quads()
	_assign_timer = 0.0
	_apply_lamp_color()


# ---- factories used by the vehicle module ------------------------------------------------------------------

## Low-beam headlight spot (add as child of the vehicle at the lamp position, it points forward -Z).
static func make_headlight() -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = HEADLIGHT.color
	l.light_energy = HEADLIGHT.energy
	l.spot_range = HEADLIGHT.range
	l.spot_angle = HEADLIGHT.angle
	l.spot_angle_attenuation = 0.9
	l.spot_attenuation = 1.3
	l.rotation_degrees.x = HEADLIGHT.pitch_deg
	l.shadow_enabled = false
	return l


## Ground-glow omni light for one ELS color (red / blue), casts shadows so the car throws a colored silhouette.
static func make_els_light(color: Color, shadows := true) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = ELS_LIGHT.energy
	l.omni_range = ELS_LIGHT.range
	l.omni_attenuation = 1.5
	l.shadow_enabled = shadows
	l.shadow_bias = 0.06
	return l


# ---- internals -----------------------------------------------------------------------------------------

func _key(i: int) -> Array:
	return KEYS[i]


func _sample(h: float) -> Dictionary:
	var i := 0
	while i < KEYS.size() - 2 and h >= KEYS[i + 1][0]:
		i += 1
	var a: Array = KEYS[i]
	var b: Array = KEYS[i + 1]
	var t := clampf((h - a[0]) / maxf(b[0] - a[0], 0.0001), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	return {
		"top": Color(a[1]).lerp(Color(b[1]), t),
		"horizon": Color(a[2]).lerp(Color(b[2]), t),
		"ground": Color(a[3]).lerp(Color(b[3]), t),
		"sun_energy": lerpf(a[4], b[4], t),
		"sun_color": Color(a[5]).lerp(Color(b[5]), t),
		"ambient": Color(a[6]).lerp(Color(b[6]), t),
		"ambient_energy": lerpf(a[7], b[7], t),
		"lamps": lerpf(a[8], b[8], t),
		"windows": lerpf(a[9], b[9], t),
	}


func _apply() -> void:
	if environment == null:
		return
	var s := _sample(hours)
	var day_f := clampf(s.sun_energy / 1.8, 0.0, 1.0)
	var top: Color = s.top
	var horizon: Color = s.horizon
	var ground: Color = s.ground
	var sun_energy: float = s.sun_energy
	var amb_energy: float = s.ambient_energy * lerpf(night_boost, 1.0, day_f)
	var amb: Color = s.ambient
	if _cloud > 0.0:
		# Cloudy: flat grey-blue overcast (day colors #8FA3B8 / #B9C4CF), weaker direct sun.
		var grey_top := Color("#8FA3B8") * day_f + top.lerp(Color(top.get_luminance(), top.get_luminance(), top.get_luminance() * 1.1), 0.6) * (1.0 - day_f)
		var grey_hor := Color("#B9C4CF") * day_f + horizon.lerp(Color(horizon.get_luminance(), horizon.get_luminance(), horizon.get_luminance() * 1.05), 0.6) * (1.0 - day_f)
		top = top.lerp(grey_top, _cloud)
		horizon = horizon.lerp(grey_hor, _cloud)
		ground = ground.lerp(grey_hor.darkened(0.35), _cloud)
		sun_energy *= lerpf(1.0, 0.3, _cloud)
		# Cloudy dusk (17:00-18:20) is warm brown-grey and dim not blue-violet.
		var dusk := clampf(1.0 - absf(hours - 17.65) / 0.75, 0.0, 1.0) * _cloud
		top = top.lerp(Color("#4A3E3C"), 0.75 * dusk)
		horizon = horizon.lerp(Color("#8A6A58"), 0.75 * dusk)
		amb = amb_dusk_warm(amb, dusk)
		amb_energy *= lerpf(1.0, 1.55, _cloud)
	sky_material.sky_top_color = top
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = horizon
	sky_material.ground_bottom_color = ground
	sky_material.sun_angle_max = lerpf(8.0, 0.0, _cloud)
	if lamp_style == "sodium":
		amb = amb.lerp(Color("#8A6A58"), 0.85 * s.lamps)
		amb_energy *= lerpf(1.0, 2.4, s.lamps * (1.0 - day_f))
	environment.ambient_light_color = amb
	sky_material.sky_energy_multiplier = lerpf(1.0, 0.78, day_f)
	# Daylight exposure trim: tuned values (clear 94 vs 114 cloudy mean brightness).
	environment.tonemap_exposure = lerpf(1.0, lerpf(0.76, 0.9, _cloud), day_f)
	environment.ambient_light_energy = amb_energy
	environment.fog_light_color = horizon
	environment.fog_density = lerpf(0.0005, 0.0013, _cloud) * lerpf(1.0, 0.6, day_f)
	# Sun path: rises in the east at 06:50, sets in the west at 17:50, a bit south of overhead.
	var a := (hours - 6.83) / 11.0 * PI
	var dir := Vector3(cos(a), sin(a), 0.4).normalized()
	sun.light_energy = sun_energy
	sun.light_color = s.sun_color
	sun.visible = sun_energy > 0.01
	sun.shadow_enabled = sun_energy > 0.05
	sun.look_at_from_position(dir * 100.0, Vector3.ZERO)
	moon.visible = moon_enabled and sun_energy < 0.2 and _cloud < 0.5
	moon.light_energy = 0.03
	var lf: float = s.lamps
	if absf(lf - lamp_factor) > 0.001:
		lamp_factor = lf
		lamps_changed.emit(lamp_factor)
	_update_emitters()
	window_material.set_shader_parameter("glow", s.windows)
	window_material.set_shader_parameter("energy", window_energy)


func amb_dusk_warm(c: Color, w: float) -> Color:
	return c.lerp(Color("#8A7468"), 0.6 * w)


func _lamp_color() -> Color:
	return LAMP_COLORS.get(lamp_style, LAMP_COLORS.white)


func _apply_lamp_color() -> void:
	if lamp_glow_material == null:
		return
	lamp_glow_material.emission = _lamp_color()
	for l in _pool_lights:
		l.light_color = _lamp_color()
	_update_emitters()


func _update_emitters() -> void:
	lamp_glow_material.emission_energy_multiplier = 2.2 * lamp_factor
	for l in _pool_lights:
		if not l.visible and lamp_factor <= 0.01:
			continue
	# pool quads are refreshed in _assign_lamp_lights


func _build_pool_quads() -> void:
	for m in _pool_mm:
		m.queue_free()
	_pool_mm.clear()
	_pool_mm_lamps.clear()
	_pool_strength.resize(_lamps.size())
	if _lamps.is_empty():
		return
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.6, 0.6, 0.6, 1), Color(0.18, 0.18, 0.18, 1), Color(0, 0, 0, 1)])
	tex.gradient = grad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = tex
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.disable_receive_shadows = true
	var quad := PlaneMesh.new()
	quad.size = Vector2(LAMP_POOL_SIZE * 2.0, LAMP_POOL_SIZE * 2.0)
	quad.material = mat
	var chunks := {}
	for i in _lamps.size():
		var p: Vector3 = _lamps[i].pos
		var key := Vector2i(floori(p.x / 400.0), floori(p.z / 400.0))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(i)
	for key in chunks:
		var idxs: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = idxs.size()
		for j in idxs.size():
			var p: Vector3 = _lamps[idxs[j]].pos
			var ground := Vector3(p.x, 0.07, p.z)
			mm.set_instance_transform(j, Transform3D(Basis(), ground))
			mm.set_instance_color(j, Color(0, 0, 0, 1))
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.visibility_range_end = 700.0
		add_child(inst)
		_pool_mm.append(inst)
		_pool_mm_lamps.append(idxs)


func _focus_position() -> Vector3:
	if focus_node != null and focus_node.is_inside_tree():
		return focus_node.global_position
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam != null else Vector3.ZERO


func _assign_lamp_lights() -> void:
	if _lamps.is_empty():
		return
	var f := _focus_position()
	var on := lamp_factor > 0.01
	# Pick the nearest lamps within LAMP_REAL_RADIUS.
	var near: Array = []
	if on:
		for i in _lamps.size():
			var d: float = _lamps[i].pos.distance_squared_to(f)
			if d < LAMP_REAL_RADIUS * LAMP_REAL_RADIUS:
				near.append([d, i])
		near.sort_custom(func(a, b): return a[0] < b[0])
	var assigned := {}
	for k in _pool_lights.size():
		var l := _pool_lights[k]
		if k < near.size():
			var idx: int = near[k][1]
			assigned[idx] = true
			l.global_position = _lamps[idx].pos
			l.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
			l.light_energy = 14.0 * lamp_factor
			l.visible = true
		else:
			l.visible = false
	var color := _lamp_color()
	for c in _pool_mm.size():
		var mm: MultiMesh = _pool_mm[c].multimesh
		var idxs: Array = _pool_mm_lamps[c]
		for j in idxs.size():
			var strength := 0.0
			if on:
				strength = (0.3 if assigned.has(idxs[j]) else 0.9) * lamp_factor
			mm.set_instance_color(j, Color(color.r * strength * 0.33, color.g * strength * 0.33, color.b * strength * 0.33, 1.0))
