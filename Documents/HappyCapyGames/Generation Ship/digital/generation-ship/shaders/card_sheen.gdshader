shader_type spatial;
render_mode blend_mix, depth_draw_never, depth_test_disabled, cull_back, unshaded;

uniform sampler2D card_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 tilt = vec2(0.0, 0.0);
uniform float sheen_strength : hint_range(0.0, 1.0) = 0.22;
uniform vec3 discount_glow_color = vec3(0.0);
uniform float corner_radius : hint_range(0.0, 0.2) = 0.06;
uniform float brightness : hint_range(0.0, 1.5) = 0.80;

void fragment() {
	vec4 face = texture(card_texture, UV);

	vec2 highlight_center = vec2(0.5) - tilt * 0.35;
	float sheen_dist = length(UV - highlight_center);
	float sheen = pow(max(0.0, 1.0 - sheen_dist * 2.2), 3.0) * sheen_strength;

	vec2 c = vec2(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));

	vec3 lit = (face.rgb + vec3(sheen * 0.6, sheen * 0.75, sheen)) * brightness;
	ALBEDO = lit;
	ROUGHNESS = 0.78;
	SPECULAR = 0.1;
	float alpha = face.a;
	if (c.x < corner_radius && c.y < corner_radius) {
		float d = length(c - vec2(corner_radius));
		alpha *= smoothstep(corner_radius, corner_radius - 0.01, d);
	}
	ALPHA = alpha;

	float edge = min(c.x, c.y);
	float rim = 1.0 - smoothstep(0.0, 0.04, edge);
	EMISSION = discount_glow_color * rim * 1.8;
}
