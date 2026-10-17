shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Camera-facing burst of light rays (a Haven raised, a hex revealed, the
// Capital rising up): rays grow out from a hot core, then fade.

uniform vec4 ray_color : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float energy = 2.5;
uniform float ray_count = 14.0;
instance uniform float progress = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float spin = progress * 0.6;
	float rays = pow(0.5 + 0.5 * sin((ang + spin) * ray_count + sin(ang * 3.0) * 2.0), 6.0);
	float rays2 = pow(0.5 + 0.5 * sin((ang - spin) * ray_count * 0.5 + 1.7), 10.0);
	float reach = mix(0.2, 1.0, smoothstep(0.0, 0.35, progress));
	float radial = 1.0 - smoothstep(0.0, reach, r);
	float core = exp(-r * r * 28.0);
	float fade = 1.0 - smoothstep(0.5, 1.0, progress);
	float v = (max(rays, rays2) * radial * 0.9 + core * 1.4) * fade;
	ALBEDO = ray_color.rgb * energy * v;
	ALPHA = clamp(v, 0.0, 1.0);
}
