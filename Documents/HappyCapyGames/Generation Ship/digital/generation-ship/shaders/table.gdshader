shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, unshaded, cull_disabled;

const float HALF_X  = 7.0;
const float HALF_Z  = 5.0;
const vec2  PANEL   = vec2(2.0, 2.0);
const float SEAM_W  = 0.030;
const float GLOW_W  = 0.22;

const vec3 COL_BASE = vec3(0.052, 0.068, 0.105);
const vec3 COL_SEAM = vec3(0.016, 0.020, 0.035);
const vec3 COL_GLOW = vec3(0.10, 0.28, 0.60);

varying vec2 wuv;

float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void vertex() {
	wuv = vec2(VERTEX.x, VERTEX.z);
}

void fragment() {
	vec2 uv = wuv;

	// Panel seams
	vec2 pf = mod(uv, PANEL);
	vec2 sd = min(pf, PANEL - pf);
	float seam_d = min(sd.x, sd.y);

	float seam = smoothstep(0.0, SEAM_W, seam_d);
	float glow  = 1.0 - smoothstep(0.0, GLOW_W, seam_d);

	// Subtle highlight towards each panel's center
	vec2 pc  = abs(pf / PANEL - 0.5) * 2.0;
	float center = smoothstep(0.6, 1.0, 1.0 - max(pc.x, pc.y)) * 0.022;

	// Metal grain
	float grain = (noise(uv * 7.0) * 0.55 + noise(uv * 16.0) * 0.45 - 0.5) * 0.016;

	// Edge vignette — darken near table border
	float vx = smoothstep(0.0, 1.4, HALF_X - abs(uv.x));
	float vz = smoothstep(0.0, 1.4, HALF_Z - abs(uv.y));
	float vig = vx * vz;

	vec3 col = mix(COL_SEAM, COL_BASE, seam);
	col += COL_GLOW * glow * 0.14;
	col += vec3(center * 0.6, center * 0.75, center);
	col += grain;
	col *= mix(0.50, 1.0, vig);

	ALBEDO   = col;
	EMISSION = col * 0.38;
	ALPHA    = 1.0;
}
