shader_type canvas_item;
uniform float corner_radius : hint_range(0.0, 0.5) = 0.06;
uniform float contrast   : hint_range(0.5, 2.0) = 1.2;
uniform float saturation : hint_range(0.0, 2.0) = 1.1;

void fragment() {
	vec2 c = vec2(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	vec4 tex = texture(TEXTURE, UV);

	vec3 col = tex.rgb;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation);
	col = (col - 0.5) * contrast + 0.5;
	col = clamp(col, 0.0, 1.0);

	float alpha = tex.a;
	if (c.x < corner_radius && c.y < corner_radius) {
		float d = length(c - vec2(corner_radius));
		alpha *= smoothstep(corner_radius, corner_radius - 0.01, d);
	}
	COLOR = vec4(col, alpha);
}
