shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, unshaded, cull_disabled;

// Set per-material to match the PlaneMesh half-extents
uniform float half_x : hint_range(0.1, 5.0) = 1.1;
uniform float half_z : hint_range(0.1, 5.0) = 0.55;

const float CLIP    = 0.10;
const float C_LEN   = 0.18;
const float BORDER  = 0.014;
const float CORNER  = 0.028;
const float GLOW_W  = 0.08;

const vec4 COL_BG     = vec4(0.03, 0.04, 0.09, 0.93);
const vec4 COL_BORDER = vec4(0.22, 0.44, 0.70, 0.55);
const vec4 COL_CORNER = vec4(0.38, 0.80, 1.00, 1.00);
const vec4 COL_GLOW   = vec4(0.18, 0.52, 0.90, 0.09);

varying vec2 slot_uv;

void vertex() {
	slot_uv = vec2(
		VERTEX.x / half_x * 0.5 + 0.5,
		VERTEX.z / half_z * 0.5 + 0.5
	);
}

void fragment() {
	vec2 uv = slot_uv;

	float dl = uv.x;
	float dr = 1.0 - uv.x;
	float dt = uv.y;
	float db = 1.0 - uv.y;
	float ex = min(dl, dr);
	float ey = min(dt, db);
	float edge = min(ex, ey);

	float c = CLIP;
	bool tl = dl < c && dt < c;
	bool tr = dr < c && dt < c;
	bool bl = dl < c && db < c;
	bool br = dr < c && db < c;

	if ((tl && (dl + dt) > c) || (tr && (dr + dt) > c) ||
		(bl && (dl + db) > c) || (br && (dr + db) > c)) {
		discard;
	}

	vec4 col = COL_BG;

	float glow = (1.0 - smoothstep(0.0, GLOW_W, edge)) * COL_GLOW.a;
	col.rgb += COL_GLOW.rgb * glow;

	bool on_border = (ex < BORDER || ey < BORDER);
	if (tl) on_border = on_border || abs(dl + dt - c) < BORDER * 1.414;
	if (tr) on_border = on_border || abs(dr + dt - c) < BORDER * 1.414;
	if (bl) on_border = on_border || abs(dl + db - c) < BORDER * 1.414;
	if (br) on_border = on_border || abs(dr + db - c) < BORDER * 1.414;
	if (on_border) col = COL_BORDER;

	bool on_bracket = false;
	float cw = CORNER;
	float cl = C_LEN;

	if ((dt < cw && dl < cl) || (dl < cw && dt < cl)) on_bracket = true;
	if ((dt < cw && dr < cl) || (dr < cw && dt < cl)) on_bracket = true;
	if ((db < cw && dl < cl) || (dl < cw && db < cl)) on_bracket = true;
	if ((db < cw && dr < cl) || (dr < cw && db < cl)) on_bracket = true;

	if (tl && abs(dl + dt - c) < cw * 1.414) on_bracket = true;
	if (tr && abs(dr + dt - c) < cw * 1.414) on_bracket = true;
	if (bl && abs(dl + db - c) < cw * 1.414) on_bracket = true;
	if (br && abs(dr + db - c) < cw * 1.414) on_bracket = true;

	if (on_bracket) col = COL_CORNER;

	ALBEDO   = col.rgb;
	EMISSION = col.rgb * 0.5;
	ALPHA    = col.a;
}
