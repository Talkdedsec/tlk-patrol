extends RefCounted
## Procedural shot effects, all generated in code (no external assets): muzzle flame + warm flash light (about 0.05 s),
## white-grey smoke puffs (1-1.5 s), tracer streak, brass casing, impact dust.
## Every spawn takes the parent node and a time scale (Weapons.fx_time_scale) so tests can slow the effects down.

const FLASH_TIME := 0.05
const TRACER_TIME := 0.07
const CASING_LIFE := 3.5

static var _star_mesh: ArrayMesh
static var _soft_texture: GradientTexture2D
static var _smoke_material: StandardMaterial3D
static var _dust_material: StandardMaterial3D
static var _smoke_curve: Curve


## Warm flash light + flame star at `at` (muzzle transform, -Z forward).
static func muzzle_flash(parent: Node, at: Transform3D, def: RefCounted, time_scale: float) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_transform = Transform3D(at.basis.orthonormalized(), at.origin)
	var duration := FLASH_TIME * time_scale

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.4)
	light.light_energy = def.flash_energy
	light.omni_range = def.flash_range
	light.shadow_enabled = false
	light.position = Vector3(0.0, 0.0, -0.25)
	root.add_child(light)

	var flame := MeshInstance3D.new()
	flame.mesh = _get_star_mesh()
	flame.scale = Vector3.ONE * def.flash_size
	flame.position = Vector3(0.0, 0.0, -0.12)
	flame.material_override = _flame_material(Color(1.0, 0.55, 0.12), 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)
	var core := MeshInstance3D.new()
	core.mesh = _get_star_mesh()
	core.scale = Vector3.ONE * def.flash_size * 0.55
	core.position = Vector3(0.0, 0.0, -0.12)
	core.material_override = _flame_material(Color(1.0, 0.95, 0.7), 1)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)

	var tween := root.create_tween()
	tween.tween_property(light, "light_energy", 0.0, duration)
	tween.parallel().tween_property(flame, "scale", flame.scale * 1.35, duration)
	tween.tween_callback(root.queue_free)


## Soft smoke burst leaving the muzzle; lifetime from the weapon def (1-1.5 s, shotgun longer).
static func smoke(parent: Node, at: Transform3D, def: RefCounted, time_scale: float) -> void:
	var p := CPUParticles3D.new()
	var life: float = def.smoke_life * time_scale
	p.one_shot = true
	p.amount = def.smoke_count
	p.lifetime = life
	p.explosiveness = 0.85
	p.randomness = 0.6
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.07
	p.direction = Vector3(0.0, 0.12, -1.0)
	p.spread = 28.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.8 if def.pellets > 1 else 1.2
	p.damping_min = 0.8
	p.damping_max = 1.4
	p.gravity = Vector3(0.0, 0.3, 0.0)
	p.scale_amount_min = def.smoke_size * 0.6
	p.scale_amount_max = def.smoke_size * 1.2
	p.scale_amount_curve = _get_smoke_curve()
	p.color_ramp = _smoke_ramp()
	p.mesh = _smoke_quad(_get_smoke_material())
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_transform = Transform3D(at.basis.orthonormalized(), at.origin)
	p.emitting = true
	_free_later(parent, p, life * 1.15 + 0.1)


## Bullet streak travelling from the muzzle to the impact point (off by default: toggled by Weapons).
static func tracer(parent: Node, from: Vector3, to: Vector3, time_scale: float) -> void:
	var dist := from.distance_to(to)
	if dist < 1.0:
		return
	var length := minf(3.0, dist)
	var dir := (to - from) / dist
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.012, length)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.9, 0.55, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(dir, up)
	node.global_transform = Transform3D(basis, from + dir * length * 0.5)
	var duration := TRACER_TIME * time_scale
	var tween := node.create_tween()
	tween.tween_property(node, "global_position", to - dir * length * 0.5, duration)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, duration)
	tween.tween_callback(node.queue_free)


## Ejected brass / hull: a tiny RigidBody3D that ignores everything except the world.
static func casing(parent: Node, at: Transform3D, def: RefCounted, ignore: Node, time_scale: float) -> void:
	var body := RigidBody3D.new()
	body.mass = 0.02
	body.collision_layer = 0
	body.collision_mask = 1
	body.continuous_cd = false
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.35
	mat.friction = 0.6
	body.physics_material_override = mat
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = def.casing_size
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = def.casing_size
	var material := StandardMaterial3D.new()
	material.albedo_color = def.casing_color
	material.metallic = 0.6
	material.roughness = 0.4
	mesh.material = material
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)
	parent.add_child(body)
	if ignore is PhysicsBody3D:
		body.add_collision_exception_with(ignore)
	var basis := at.basis.orthonormalized()
	body.global_transform = Transform3D(basis, at.origin)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	body.linear_velocity = basis * Vector3(rng.randf_range(1.6, 2.6), rng.randf_range(1.4, 2.4), rng.randf_range(-0.2, 0.8))
	body.angular_velocity = Vector3(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0))
	_free_later(parent, body, CASING_LIFE * maxf(time_scale, 1.0))


## Small dust puff where a bullet lands (brown dust on asphalt, no blood).
static func impact(parent: Node, point: Vector3, normal: Vector3, on_target: bool, time_scale: float) -> void:
	var p := CPUParticles3D.new()
	var life := 0.5 * time_scale
	p.one_shot = true
	p.amount = 5 if on_target else 7
	p.lifetime = life
	p.explosiveness = 1.0
	p.randomness = 0.4
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	p.direction = normal
	p.spread = 50.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.4
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.gravity = Vector3(0.0, -2.5, 0.0)
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.22
	var ramp := Gradient.new()
	var tint := Color(0.78, 0.78, 0.8) if on_target else Color(0.6, 0.53, 0.43)
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(tint, 0.0), Color(tint, 0.7), Color(tint, 0.0)])
	p.color_ramp = ramp
	p.mesh = _smoke_quad(_get_dust_material())
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = point + normal * 0.03
	p.emitting = true
	_free_later(parent, p, life * 1.2 + 0.1)


# --- shared resources ---------------------------------------------------------

static func _free_later(parent: Node, node: Node, seconds: float) -> void:
	var tree := parent.get_tree()
	if tree == null:
		return
	tree.create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(node):
			node.queue_free())


static func _get_star_mesh() -> ArrayMesh:
	if _star_mesh != null:
		return _star_mesh
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spikes := 8
	var count := spikes * 2
	for i in count:
		var a0 := TAU * float(i) / float(count)
		var a1 := TAU * float(i + 1) / float(count)
		var r0 := 1.0 if i % 2 == 0 else 0.36
		var r1 := 1.0 if (i + 1) % 2 == 0 else 0.36
		tool.add_vertex(Vector3.ZERO)
		tool.add_vertex(Vector3(cos(a0) * r0, sin(a0) * r0, 0.0))
		tool.add_vertex(Vector3(cos(a1) * r1, sin(a1) * r1, 0.0))
	_star_mesh = tool.commit()
	return _star_mesh


static func _flame_material(color: Color, priority: int) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = priority
	return mat


static func _get_soft_texture() -> GradientTexture2D:
	if _soft_texture != null:
		return _soft_texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0.0)])
	_soft_texture = GradientTexture2D.new()
	_soft_texture.gradient = gradient
	_soft_texture.fill = GradientTexture2D.FILL_RADIAL
	_soft_texture.fill_from = Vector2(0.5, 0.5)
	_soft_texture.fill_to = Vector2(1.0, 0.5)
	_soft_texture.width = 128
	_soft_texture.height = 128
	return _soft_texture


static func _particle_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _get_soft_texture()
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.particles_anim_h_frames = 1
	mat.particles_anim_v_frames = 1
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	return mat


static func _get_smoke_material() -> StandardMaterial3D:
	if _smoke_material == null:
		_smoke_material = _particle_material()
	return _smoke_material


static func _get_dust_material() -> StandardMaterial3D:
	if _dust_material == null:
		_dust_material = _particle_material()
	return _dust_material


static func _smoke_quad(material: Material) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	return quad


static func _smoke_ramp() -> Gradient:
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
	ramp.colors = PackedColorArray([Color(0.92, 0.92, 0.94, 0.0), Color(0.9, 0.9, 0.92, 0.6),
			Color(0.78, 0.78, 0.8, 0.32), Color(0.7, 0.7, 0.72, 0.0)])
	return ramp


static func _get_smoke_curve() -> Curve:
	if _smoke_curve == null:
		_smoke_curve = Curve.new()
		_smoke_curve.add_point(Vector2(0.0, 0.35))
		_smoke_curve.add_point(Vector2(0.3, 0.8))
		_smoke_curve.add_point(Vector2(1.0, 1.4))
	return _smoke_curve
