shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, unshaded, cull_disabled;

const float HALF_X = 0.46;
const float HALF_Z = 0.34;

uniform float highlight_t : hint_range(0.0, 1.0) = 0.0;

varying vec2 slot_uv;

void vertex() {
	slot_uv = vec2(
		VERTEX.x / HALF_X * 0.5 + 0.5,
		VERTEX.z / HALF_Z * 0.5 + 0.5
	);
}

float sdf_chamfered_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	float aspect = HALF_X / HALF_Z;
	vec2 p = vec2((slot_uv.x - 0.5) * aspect, slot_uv.y - 0.5);

	float chamfer = 0.055;
	vec2  bh = vec2(aspect * 0.5 - 0.02, 0.5 - 0.02);

	float d = sdf_chamfered_box(p, bh, chamfer);

	float inside   = 1.0 - smoothstep(-0.005, 0.005, d);
	float border   = 1.0 - smoothstep(0.0, 0.016, abs(d));
	float glow_in  = smoothstep(-0.10, 0.0, d) * inside;
	float glow_out = (1.0 - smoothstep(0.0, 0.055, d)) * step(0.0, d);

	float pulse = 0.60 + 0.40 * sin(TIME * 1.7);
	float h_t   = highlight_t * (0.5 + 0.5 * sin(TIME * 4.0));

	vec3 bg  = vec3(0.010, 0.025, 0.068);
	vec3 bdr = mix(vec3(0.18, 0.52, 0.95), vec3(0.18, 0.85, 0.30), h_t);

	// Subtle blueprint grid
	float gx   = smoothstep(0.88, 1.0, abs(sin(p.x * PI * 4.0)));
	float gy   = smoothstep(0.88, 1.0, abs(sin(p.y * PI * 6.0)));
	float grid = max(gx, gy) * inside * 0.06;

	// Sweeping scan line
	float st   = fract(TIME * 0.30);
	float spos = mix(-bh.y, bh.y, st);
	float scan = (1.0 - smoothstep(0.0, 0.035, abs(p.y - spos)))
	           * (1.0 - smoothstep(0.75, 1.0, st))
	           * inside * 0.18;

	// Corner L-marks (abs mirrors to all 4 corners)
	vec2 ap = abs(p);
	vec2 ci = bh - vec2(chamfer + 0.010);
	float tl = 0.075, tw = 0.007;
	float arm_h = (1.0 - smoothstep(0.0, tw, abs(ap.y - ci.y)))
	            * step(ci.x - tl, ap.x) * step(ap.x, ci.x + tw * 0.5);
	float arm_v = (1.0 - smoothstep(0.0, tw, abs(ap.x - ci.x)))
	            * step(ci.y - tl, ap.y) * step(ap.y, ci.y + tw * 0.5);
	float corners = max(arm_h, arm_v) * inside;

	// Compose
	vec3 col  = bg * inside;
	col      += bdr * glow_in  * 0.22 * pulse;
	col      += bdr * glow_out * 0.10 * pulse;
	col      += bdr * grid;
	col      += bdr * scan;
	col      += bdr * corners * 0.80;
	col      += bdr * border  * (0.80 + 0.20 * pulse);

	float alpha = inside * 0.85 + glow_out * 0.20;

	ALBEDO   = col;
	EMISSION = col * 1.2;
	ALPHA    = clamp(alpha, 0.0, 1.0);
}
