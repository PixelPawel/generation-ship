shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

uniform sampler2D sun_texture : filter_linear;
// Screen-space position and size in NDC coordinates (-1..1, Y up).
uniform vec2 ndc_pos   = vec2(0.0, 0.26);
uniform vec2 ndc_size  = vec2(0.13, 0.17);
// Dim the sun without changing its colour. 1.0 = full brightness.
uniform float intensity : hint_range(0.0, 1.0) = 0.6;

void vertex() {
	POSITION = vec4(ndc_pos + VERTEX.xy * ndc_size, 0.9999, 1.0);
}

void fragment() {
	vec4 col = texture(sun_texture, UV);
	ALBEDO = col.rgb;
	ALPHA  = col.a * intensity;
}
