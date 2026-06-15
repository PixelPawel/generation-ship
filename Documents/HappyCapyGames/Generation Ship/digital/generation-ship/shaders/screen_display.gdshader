shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;

uniform sampler2D viewport_tex : filter_linear;
uniform vec3 aabb_min;
uniform vec3 aabb_max;

uniform float emission_strength    : hint_range(0.0, 3.0)  = 1.3;
uniform float scanline_count       : hint_range(0.0, 300.0) = 120.0;
uniform float scanline_depth       : hint_range(0.0, 1.0)  = 0.08;
uniform float vignette_strength    : hint_range(0.0, 1.0)  = 0.35;
uniform float vignette_falloff     : hint_range(0.5, 8.0)  = 3.0;
uniform float border_glow_width    : hint_range(0.0, 0.15) = 0.04;
uniform float border_glow_strength : hint_range(0.0, 2.0)  = 0.5;
uniform vec3  border_glow_color                             = vec3(0.18, 0.52, 0.90);

varying vec3 m;

void vertex() {
	m = VERTEX;
}

void fragment() {
	float u = (m.x - aabb_min.x) / (aabb_max.x - aabb_min.x);
	float v = 1.0 - (m.y - aabb_min.y) / (aabb_max.y - aabb_min.y);
	vec2 uv = vec2(u, v);

	vec4 c = texture(viewport_tex, uv);

	// Scanlines
	float line_phase = fract(v * scanline_count);
	float scan_factor = 1.0 - scanline_depth * (1.0 - pow(abs(sin(line_phase * 3.14159)), 1.5));
	vec3 col = c.rgb * scan_factor;

	// Vignette
	vec2 vig_uv = uv * 2.0 - 1.0;
	float vig = pow(1.0 - dot(vig_uv, vig_uv) * 0.5, vignette_falloff);
	col *= mix(1.0 - vignette_strength, 1.0, clamp(vig, 0.0, 1.0));

	// Border glow
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	col += border_glow_color * (1.0 - smoothstep(0.0, border_glow_width, edge)) * border_glow_strength;

	ALBEDO   = col;
	ALPHA    = c.a;
	// EMISSION drives the HDR glow pass using raw source colour (pre-effects)
	// so bright UI pixels bloom at full intensity.
	EMISSION = c.rgb * emission_strength;
}
