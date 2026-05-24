shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

const float GRID_X = 1.0;
const float GRID_Z = 0.80;
const float SEAM_W = 0.025;
const float BOLT_R = 0.052;

const vec3 COL_BASE  = vec3(0.11, 0.13, 0.16);
const vec3 COL_PANEL = vec3(0.17, 0.19, 0.22);
const vec3 COL_SEAM  = vec3(0.05, 0.06, 0.07);
const vec3 COL_BOLT  = vec3(0.24, 0.26, 0.30);
const vec3 COL_RUST1 = vec3(0.52, 0.20, 0.06);
const vec3 COL_RUST2 = vec3(0.36, 0.13, 0.03);

varying vec3 surface_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float rust_fbm(vec2 p) {
	return vnoise(p * 2.1) * 0.50
	     + vnoise(p * 4.5) * 0.30
	     + vnoise(p * 9.8) * 0.20;
}

void vertex() {
	surface_pos = VERTEX;
}

void fragment() {
	vec3 p = surface_pos;

	// ── Hull panel grid ───────────────────────────────────────────────────────
	float gx     = mod(abs(p.x) + GRID_X * 0.5, GRID_X);
	float gz     = mod(abs(p.z) + GRID_Z * 0.5, GRID_Z);
	float seam_d = min(min(gx, GRID_X - gx), min(gz, GRID_Z - gz));
	float seam_t = 1.0 - smoothstep(0.0, SEAM_W, seam_d);

	float cx = 1.0 - abs(gx / GRID_X - 0.5) * 2.0;
	float cz = 1.0 - abs(gz / GRID_Z - 0.5) * 2.0;

	vec3  col   = mix(COL_BASE, COL_PANEL, cx * cz * 0.45);
	col         = mix(col, COL_SEAM, seam_t);
	float metal = mix(0.90, 0.18, seam_t * 0.65);
	float rough = mix(0.32, 0.78, seam_t * 0.55);

	// ── Rivets at intersections ───────────────────────────────────────────────
	float bx  = mod(abs(p.x), GRID_X);
	float bz  = mod(abs(p.z), GRID_Z);
	float bd  = length(vec2(min(bx, GRID_X - bx), min(bz, GRID_Z - bz)));
	float bt  = 1.0 - smoothstep(BOLT_R * 0.55, BOLT_R, bd);
	float bhi = 1.0 - smoothstep(0.0, BOLT_R * 0.45, bd);

	col   = mix(col, COL_BOLT, bt * 0.88);
	col  += vec3(0.14, 0.15, 0.17) * bhi * bt;
	metal = mix(metal, 0.95, bt * 0.65);
	rough = mix(rough, 0.18, bt * 0.72);

	// ── Rust patches ─────────────────────────────────────────────────────────
	float rust = rust_fbm(vec2(p.x, p.z));
	rust = smoothstep(0.50, 0.74, rust);
	rust = max(rust, seam_t * 0.35);          // rust pools in seams

	vec3 rust_col = mix(COL_RUST2, COL_RUST1, vnoise(vec2(p.x, p.z) * 5.2));
	col   = mix(col, rust_col, rust * (1.0 - bt * 0.85));
	metal = mix(metal, 0.04, rust * 0.88);
	rough = mix(rough, 0.90, rust * 0.82);

	ALBEDO    = col;
	METALLIC  = metal;
	ROUGHNESS = rough;
}
