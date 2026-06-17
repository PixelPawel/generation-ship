shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;

uniform float speed        : hint_range(0.0, 0.02)  = 0.003;
uniform float emission_str : hint_range(1.0, 40.0)  = 22.0;
uniform float star_density : hint_range(0.02, 0.35) = 0.09;

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

vec2 cube_uv(vec3 d) {
	vec3 a = abs(d);
	if (a.x >= a.y && a.x >= a.z) return d.yz / a.x;
	if (a.y >= a.x && a.y >= a.z) return d.xz / a.y;
	return d.xy / a.z;
}

float star_layer(vec3 dir, float lid, float grid_scale, float drift) {
	float ca = cos(lid * 0.927);
	float sa = sin(lid * 0.927);
	vec3 r = vec3(dir.x * ca + dir.z * sa, dir.y, -dir.x * sa + dir.z * ca);

	vec2 uv = cube_uv(r);
	uv.x += drift;

	vec2 g    = uv * grid_scale;
	vec2 cell = floor(g);
	vec2 frac = fract(g) - 0.5;

	if (h12(cell + lid * 17.3) > star_density)
		return 0.0;

	vec2 off = vec2(h12(cell + lid * 7.0 + 0.5), h12(cell + lid * 13.0 + 1.5)) - 0.5;
	off *= 0.75;

	float dist = length(frac - off);

	// sz is the hard core radius; halo extends 25x further for a visible glow
	float sz   = 0.015 + h12(cell + lid * 29.0 + 2.5) * 0.04;
	float core = 1.0 - smoothstep(0.0, sz, dist);
	float halo = (1.0 - smoothstep(0.0, sz * 25.0, dist)) * 0.45;
	float brt  = 0.3 + h12(cell + lid * 41.0 + 3.5) * 0.7;

	return (core + halo) * brt;
}

void vertex() {
	v_dir = VERTEX;
}

void fragment() {
	vec3 dir  = normalize(v_dir);
	float tot = 0.0;

	for (int i = 0; i < 8; i++) {
		float fi    = float(i);
		float drift = TIME * speed * mix(1.0, 0.15, fi / 7.0);
		float grid  = 18.0 + fi * 11.0;
		float dim   = 1.0 - fi * 0.07;
		tot += star_layer(dir, fi, grid, drift) * dim;
	}

	tot = clamp(tot, 0.0, 1.0);

	float hue = h13(floor(dir * 28.0 + 0.5));
	vec3 col;
	if (hue > 0.91) {
		col = vec3(1.0, 0.78, 0.38);
	} else if (hue > 0.76) {
		col = vec3(0.58, 0.68, 1.0);
	} else {
		col = vec3(0.93, 0.96, 1.0);
	}

	ALBEDO   = col * tot;
	EMISSION = col * tot * emission_str;
}
