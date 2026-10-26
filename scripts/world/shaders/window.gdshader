// Window glass: vertex color rgb = lit tint, alpha >= 0.5 marks a window that is lit at night.
shader_type spatial;
render_mode cull_back;

uniform float glow : hint_range(0.0, 1.0) = 1.0;   // 0 = daytime glass, 1 = night
uniform float energy = 2.4;
uniform vec3 day_glass : source_color = vec3(0.30, 0.38, 0.46);
uniform vec3 night_glass : source_color = vec3(0.04, 0.05, 0.075);

void fragment() {
	vec3 tint = pow(COLOR.rgb, vec3(2.2));
	float lit = step(0.5, COLOR.a) * glow;
	ALBEDO = mix(day_glass, night_glass, glow);
	EMISSION = tint * energy * lit;
	ROUGHNESS = 0.25;
	SPECULAR = 0.5;
}
