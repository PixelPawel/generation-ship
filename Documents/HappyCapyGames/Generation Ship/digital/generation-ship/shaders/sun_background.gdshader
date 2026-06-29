shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform sampler2D sun_texture : filter_linear;
// Screen-space position and size in NDC coordinates (-1..1, Y up).
// Tune ndc_pos and ndc_size to reposition/resize the sun on screen.
uniform vec2 ndc_pos  = vec2(0.0, 0.26);
uniform vec2 ndc_size = vec2(0.13, 0.17);

void vertex() {
	// Pin the quad in clip space at a depth just below the far plane so it
	// depth-tests behind all opaque 3D geometry (cockpit, cards, etc).
	POSITION = vec4(ndc_pos + VERTEX.xy * ndc_size, 0.9999, 1.0);
}

void fragment() {
	vec4 col = texture(sun_texture, UV);
	ALBEDO = col.rgb;
	ALPHA  = col.a;
}
