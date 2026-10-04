shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;

// The space around the ship, on the inside of a big sphere (starfield.gd):
// travelling star layers (parallax), twinkle, real star colours, nebula
// clouds, a galaxy band with dust lanes, and the odd shooting star.
// The menu turns the extras up; the game keeps them calmer behind the table.

uniform float speed        : hint_range(0.0, 0.1)   = 0.012;
uniform float emission_str : hint_range(1.0, 40.0)  = 22.0;
uniform float star_density : hint_range(0.02, 0.35) = 0.05;
// Direction the ship is travelling toward (world space, need not be normalised)
uniform vec3  travel_dir                            = vec3(0.0, 0.0, 1.0);

uniform float twinkle        : hint_range(0.0, 1.0) = 0.5;
uniform float nebula_str     : hint_range(0.0, 2.0) = 0.6;
uniform vec3  nebula_col_a   : source_color = vec3(0.45, 0.12, 0.55);
uniform vec3  nebula_col_b   : source_color = vec3(0.05, 0.35, 0.55);
uniform float galaxy_str     : hint_range(0.0, 2.0) = 0.6;
uniform vec3  galaxy_normal                  = vec3(0.35, 0.45, 0.82);
uniform float shooting_rate  : hint_range(0.0, 1.0) = 0.35;  // 0 = none, 1 = frequent
// where shooting stars appear (the part of the sky the camera sees)
uniform vec3  view_dir                       = vec3(0.0, -1.0, 0.0);

// Rendered backdrop (Render/space_panorama): nebula, galaxy band and a
// planet, as a partial equirect panorama centred on the cockpit camera's
// view (-Y, screen up = -Z), BACKDROP_SPAN degrees across. Replaces the
// procedural nebula/galaxy (set their strengths to 0 when this is on).
uniform sampler2D backdrop_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float backdrop_str     : hint_range(0.0, 2.0) = 0.0;
const vec2 BACKDROP_SPAN = vec2(150.0, 100.0);
// the planet in it (make_panorama.py PLANET_DIR / PLANET_ANG_R, in this
// sphere's space): stars behind its disk are hidden
const vec3  BACKDROP_PLANET_DIR = vec3(-0.4330, -0.8877, -0.1564);
const float BACKDROP_PLANET_R   = 2.05;   // degrees, incl. the atmosphere rim

varying vec3 v_dir;

float h12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float h13(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float h11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = h13(i), n100 = h13(i + vec3(1.0, 0.0, 0.0));
	float n010 = h13(i + vec3(0.0, 1.0, 0.0)), n110 = h13(i + vec3(1.0, 1.0, 0.0));
	float n001 = h13(i + vec3(0.0, 0.0, 1.0)), n101 = h13(i + vec3(1.0, 0.0, 1.0));
	float n011 = h13(i + vec3(0.0, 1.0, 1.0)), n111 = h13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
	           mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return v;
}

vec2 cube_uv(vec3 d) {
	vec3 a = abs(d);
	if (a.x >= a.y && a.x >= a.z) return d.yz / a.x;
	if (a.y >= a.x && a.y >= a.z) return d.xz / a.y;
	return d.xy / a.z;
}

// A star's colour from its own hash: mostly white, then blue-white, yellow,
// orange, a few red.
vec3 star_colour(float h) {
	if (h > 0.94) return vec3(1.0, 0.55, 0.38);
	if (h > 0.84) return vec3(1.0, 0.78, 0.45);
	if (h > 0.70) return vec3(1.0, 0.93, 0.75);
	if (h > 0.45) return vec3(0.68, 0.78, 1.0);
	return vec3(0.93, 0.96, 1.0);
}

// lid controls per-layer rotation only; seed controls star placement.
// Separating them means a new cycle keeps the same rotation but gets fresh stars.
vec3 star_layer(vec3 dir, float lid, float seed, float grid_scale, float drift) {
	float ca = cos(lid * 0.927);
	float sa = sin(lid * 0.927);
	vec3 r = vec3(dir.x * ca + dir.z * sa, dir.y, -dir.x * sa + dir.z * ca);

	vec3 fwd = normalize(vec3(travel_dir.x * ca + travel_dir.z * sa,
	                          travel_dir.y,
	                         -travel_dir.x * sa + travel_dir.z * ca));

	vec3 perp     = r - dot(r, fwd) * fwd;
	float sin_t   = length(perp);
	vec3 orig_dir = normalize(r + fwd * drift * sin_t);

	vec2 uv = cube_uv(orig_dir);
	vec2 g    = uv * grid_scale;
	vec2 cell = floor(g);
	vec2 frac = fract(g) - 0.5;

	if (h12(cell + seed * 17.3) > star_density)
		return vec3(0.0);

	vec2 off = vec2(h12(cell + seed * 7.0 + 0.5), h12(cell + seed * 13.0 + 1.5)) - 0.5;
	off *= 0.75;

	float dist = length(frac - off);
	float big  = h12(cell + seed * 53.0 + 4.5);           // a few bright, glowing stars
	float sz   = 0.015 + h12(cell + seed * 29.0 + 2.5) * 0.04 + step(0.97, big) * 0.03;
	float core = 1.0 - smoothstep(0.0, sz, dist);
	// a cell only draws its own star, so the glow must fade out before the
	// nearest cell edge or it gets cut off into a square
	float room = 0.5 - max(abs(off.x), abs(off.y));
	float halo_r = min(sz * (5.0 + step(0.97, big) * 4.0), room);
	float halo = exp(-dist * dist / (halo_r * halo_r) * 4.0) * (0.05 + step(0.97, big) * 0.08);
	float brt  = 0.3 + h12(cell + seed * 41.0 + 3.5) * 0.7;
	// twinkle: each star its own rate and phase
	float th   = h12(cell + seed * 61.0 + 5.5);
	brt *= 1.0 - twinkle * 0.5 * (0.5 + 0.5 * sin(TIME * (1.2 + th * 4.0) + th * 40.0)) * step(0.4, th);

	return star_colour(h12(cell + seed * 71.0 + 6.5)) * (core + halo) * brt;
}

// Nebula: soft clouds in two colours, slowly turning.
vec3 nebula(vec3 dir) {
	vec3 p = dir * 2.2 + vec3(0.0, TIME * 0.004, 0.0);
	float n1 = fbm(p);
	float n2 = fbm(p * 1.7 + vec3(4.0, 1.0, 7.0));
	float mask = smoothstep(0.45, 0.8, fbm(dir * 1.1 + vec3(9.0)));
	vec3 col = mix(nebula_col_a, nebula_col_b, smoothstep(0.3, 0.7, n2));
	return col * pow(n1, 2.4) * mask * nebula_str;
}

// Galaxy band: a glowing strip of tiny stars along a great circle, with dust lanes.
vec3 galaxy(vec3 dir) {
	vec3 n = normalize(galaxy_normal);
	float d = dot(dir, n);
	float band = exp(-d * d * 28.0);
	float core = exp(-d * d * 140.0);
	float dust = smoothstep(0.38, 0.62, fbm(dir * 6.0 + vec3(3.0)));
	vec2 cell = floor(cube_uv(dir) * 260.0);
	float tiny = step(0.985 - band * 0.06, h12(cell)) * (0.4 + 0.6 * h12(cell + 7.7));
	vec3 glow = vec3(0.55, 0.6, 0.85) * band * 0.25 + vec3(0.95, 0.85, 0.7) * core * 0.35;
	return (glow * (1.0 - dust * 0.75) + vec3(0.9, 0.92, 1.0) * tiny * band) * galaxy_str;
}

// Shooting stars: a few slots, each firing now and then on a random arc in view.
vec3 shooting(vec3 dir) {
	vec3 col = vec3(0.0);
	vec3 vd = normalize(view_dir);
	vec3 side = normalize(abs(vd.y) > 0.9 ? cross(vd, vec3(1.0, 0.0, 0.0)) : cross(vd, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(side, vd);
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float period = mix(14.0, 4.0, shooting_rate) + fk * 3.1;
		float slot = floor((TIME + fk * 5.7) / period);
		float t = fract((TIME + fk * 5.7) / period) * period;   // seconds into this slot
		float dur = 0.9;
		if (shooting_rate <= 0.0 || t > dur || h11(slot * 3.1 + fk) > shooting_rate + 0.25)
			continue;
		// start point near where the camera looks, heading off in a random direction
		vec3 s = normalize(vd + side * (h11(slot + fk * 9.1) - 0.5) * 1.1 + up * (h11(slot * 1.7 + fk) - 0.5) * 0.8);
		float ang = h11(slot * 2.3 + fk * 4.4) * 6.2832;
		vec3 v = normalize(cross(s, side * cos(ang) + up * sin(ang)));
		vec3 nrm = normalize(cross(s, v));
		float off = dot(dir, nrm);                       // distance across the path
		float along = atan(dot(dir, v), dot(dir, s));     // angle along the path
		float head = t / dur * 0.55;
		float tail = 0.12;
		if (along > head || along < head - tail || dot(dir, s) < 0.0)
			continue;
		float k_along = (along - (head - tail)) / tail;   // 0 tail end .. 1 head
		float width = 0.0015 + 0.002 * k_along;
		float line = smoothstep(width, 0.0, abs(off));
		float fade = sin(3.1416 * t / dur);
		col += vec3(0.9, 0.95, 1.0) * line * k_along * k_along * fade * 3.0;
	}
	return col;
}

vec3 backdrop_tex_col(vec3 dir) {
	float lon = atan(dir.x, -dir.y);
	float lat = asin(clamp(-dir.z, -1.0, 1.0));
	vec2 uv = vec2(0.5 + degrees(lon) / BACKDROP_SPAN.x, 0.5 - degrees(lat) / BACKDROP_SPAN.y);
	// fade out toward the panorama's edges instead of a hard border
	vec2 edge = min(uv, 1.0 - uv);
	float fade = smoothstep(0.0, 0.08, min(edge.x, edge.y));
	if (fade <= 0.0)
		return vec3(0.0);
	return texture(backdrop_tex, uv).rgb * fade;
}

void vertex() {
	v_dir = VERTEX;
}

// Stars converge toward the forward pole as drift grows unboundedly, eventually
// collapsing to a single UV cell.  Fix: cap drift at CYCLE and crossfade in a
// fresh batch of stars (different seed) before the old batch vanishes.
const float CYCLE      = 1.0;   // drift units before regenerating each layer
const float FADE_START = 0.75;  // fraction of CYCLE where crossfade begins

void fragment() {
	vec3 dir  = normalize(v_dir);
	vec3 stars = vec3(0.0);

	for (int i = 0; i < 8; i++) {
		float fi   = float(i);
		float mult = mix(1.5, 0.1, fi / 7.0);
		float drift_total = TIME * speed * mult;
		float grid = 18.0 + fi * 11.0;
		float dim  = 1.0 - fi * 0.07;

		float cycle = floor(drift_total / CYCLE);
		float t     = mod(drift_total, CYCLE);

		float blend = smoothstep(FADE_START, CYCLE, t);

		float seed_cur  = fi + cycle * 3.77;
		float t_cur     = min(t + (CYCLE - FADE_START), CYCLE);
		stars += star_layer(dir, fi, seed_cur, grid, t_cur) * dim * (1.0 - blend);

		float seed_next = fi + (cycle + 1.0) * 3.77;
		float t_next    = max(0.0, t - FADE_START);
		stars += star_layer(dir, fi, seed_next, grid, t_next) * dim * blend;
	}
	stars = min(stars, vec3(1.0));
	if (backdrop_str > 0.0) {
		float ang = degrees(acos(clamp(dot(dir, normalize(BACKDROP_PLANET_DIR)), -1.0, 1.0)));
		stars *= smoothstep(BACKDROP_PLANET_R - 0.15, BACKDROP_PLANET_R + 0.15, ang);
	}

	vec3 backdrop = vec3(0.0);
	if (nebula_str > 0.0)
		backdrop += nebula(dir);
	if (galaxy_str > 0.0)
		backdrop += galaxy(dir);
	if (backdrop_str > 0.0)
		backdrop += backdrop_tex_col(dir) * backdrop_str;
	vec3 meteors = shooting(dir);

	// the backdrop glows softly; stars and meteors are the bright points
	ALBEDO   = stars + backdrop + meteors;
	EMISSION = stars * emission_str + backdrop * 1.5 + meteors * emission_str;
}
