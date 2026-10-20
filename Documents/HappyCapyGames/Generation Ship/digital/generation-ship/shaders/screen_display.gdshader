shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;

// A cockpit monitor showing a SubViewport, true to the UI's own colours: the
// viewport holds sRGB values (converted to linear here, not read as if linear),
// and the scene's Filmic tonemapper - which would lift the mid-tones and squash
// the highlights, washing cards and text out - is undone by passing the colour
// through its inverse. The monitor then shows the UI as designed, times
// `exposure`. Keep filmic_inverse() in sync with the Environment (Filmic,
// white 1.0, no exposure change).

uniform sampler2D viewport_tex : filter_linear;
uniform vec3 aabb_min;
uniform vec3 aabb_max;

uniform float emission_strength    : hint_range(0.0, 3.0)  = 1.3;
uniform float exposure             : hint_range(0.0, 2.0)  = 1.0;
uniform float vignette_strength    : hint_range(0.0, 1.0)  = 0.35;
uniform float vignette_falloff     : hint_range(0.5, 8.0)  = 3.0;
// glow: only pixels brighter than this (sRGB) glow, so panels and text stay crisp
uniform float bloom_threshold      : hint_range(0.0, 1.0)  = 0.7;

varying vec3 m;

void vertex() {
	m = VERTEX;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// Godot's tonemap_filmic() (exposure bias 2 baked in, white 1.0), solved for its input
vec3 filmic_inverse(vec3 y) {
	const float FA = 0.88;      // Godot's A..F (E is a built-in constant here)
	const float FB = 0.6;
	const float FC = 0.1;
	const float FD = 0.2;
	const float FE = 0.01;
	const float FF = 0.3;
	const float FW = 0.578355;  // filmic(1.0): the curve is normalised so white stays 1
	vec3 k = clamp(y, 0.0, 0.999) * FW + FE / FF;
	vec3 a = FA * (1.0 - k);
	vec3 b = FB * (FC - k);
	vec3 c = FD * (FE - k * FF);
	return (-b + sqrt(max(b * b - 4.0 * a * c, vec3(0.0)))) / (2.0 * a);
}

void fragment() {
	float u = (m.x - aabb_min.x) / (aabb_max.x - aabb_min.x);
	float v = 1.0 - (m.y - aabb_min.y) / (aabb_max.y - aabb_min.y);
	vec2 uv = vec2(u, v);

	// four taps spread over the pixel's footprint: the monitors usually show the
	// viewport a little smaller than it is, and thin text shimmered with one
	vec2 dx = dFdx(uv) * 0.25;
	vec2 dy = dFdy(uv) * 0.25;
	vec4 c = (texture(viewport_tex, uv + dx + dy) + texture(viewport_tex, uv + dx - dy)
			+ texture(viewport_tex, uv - dx + dy) + texture(viewport_tex, uv - dx - dy)) * 0.25;

	vec3 col = srgb_to_linear(c.rgb) * exposure;

	// Vignette
	vec2 vig_uv = uv * 2.0 - 1.0;
	float vig = pow(1.0 - dot(vig_uv, vig_uv) * 0.5, vignette_falloff);
	col *= mix(1.0 - vignette_strength, 1.0, clamp(vig, 0.0, 1.0));

	ALBEDO = filmic_inverse(col);
	ALPHA  = c.a;

	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114)) * exposure;
	float bloom = max(0.0, lum - bloom_threshold) / max(0.001, 1.0 - bloom_threshold);
	EMISSION = col * bloom * emission_strength;
}
