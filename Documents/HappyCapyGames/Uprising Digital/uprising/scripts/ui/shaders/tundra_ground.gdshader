shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// The frozen tundra the board lies on. Ground textures: Poly Haven
// "snow_field_aerial" (macro, wind-swept snow with scrub showing through)
// and "snow_02" (close detail), both CC0. Graded cold and kept darker than
// the board so the game stays the brightest thing on screen.
//   - drifts rise out of the height map, flat for a margin round the board
//   - pools of teal ice like the board's Ice Waste spaces
//   - wind-blown snow streaks race across the ground
//   - the ground melts into the night haze far from the board

uniform sampler2D macro_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_height : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float macro_scale = 64.0;
uniform float detail_scale = 7.0;
uniform vec4 snow_tint : source_color = vec4(0.52, 0.6, 0.68, 1.0);
uniform vec4 scrub_tint : source_color = vec4(0.2, 0.25, 0.3, 1.0);
uniform vec4 ice_color : source_color = vec4(0.03, 0.3, 0.36, 1.0);
uniform float ice_amount = 1.0;

uniform float board_half = 13.4;
uniform float flat_margin = 2.0;
uniform float drift_ramp = 12.0;
uniform float drift_height = 1.8;

uniform vec4 haze_color : source_color = vec4(0.03, 0.055, 0.068, 1.0);
uniform float haze_start = 22.0;
uniform float haze_end = 80.0;

uniform vec2 wind_dir = vec2(1.0, 0.3);
uniform float wind_speed = 4.0;
uniform float streak_strength = 0.22;
uniform float sparkle_strength = 0.5;

varying vec3 world_pos;

float board_distance(vec2 p) {
	vec2 d = abs(p) - vec2(board_half);
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float drift(vec2 p) {
	float rise = smoothstep(flat_margin, flat_margin + drift_ramp, board_distance(p));
	float h = textureLod(macro_height, p / macro_scale, 0.0).r;
	float big = textureLod(macro_height, p / (macro_scale * 3.1) + vec2(0.37, 0.11), 0.0).r;
	return ((h - 0.4) * 0.6 + (big - 0.45) * 1.4) * drift_height * rise;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = drift(wp.xz);
	float e = 0.6;
	float hx = drift(wp.xz + vec2(e, 0.0));
	float hz = drift(wp.xz + vec2(0.0, e));
	VERTEX.y += h;
	NORMAL = normalize(vec3(-(hx - h) / e, 1.0, -(hz - h) / e));
	world_pos = wp + vec3(0.0, h, 0.0);
}

void fragment() {
	vec2 uvm = world_pos.xz / macro_scale;
	vec2 uvd = world_pos.xz / detail_scale;
	// Snow / scrub mask from a blurred (high mip) read of the aerial map, so
	// the snow lies in soft drifts instead of salt-and-pepper grains; a
	// second, larger and turned copy hides the texture's repeat.
	vec3 macro = textureLod(macro_albedo, uvm, 2.5).rgb;
	vec3 macro2 = textureLod(macro_albedo, vec2(-world_pos.z, world_pos.x) / (macro_scale * 2.37) + vec2(0.17, 0.43), 2.0).rgb;
	vec3 fine = texture(macro_albedo, uvm).rgb;
	vec3 det = texture(detail_albedo, uvd).rgb;
	float lum = dot(mix(macro, macro2, 0.45), vec3(0.299, 0.587, 0.114));
	vec3 col = mix(scrub_tint.rgb, snow_tint.rgb, smoothstep(0.12, 0.42, lum));
	col *= mix(0.9, 1.06, dot(fine, vec3(0.333)));
	col *= mix(0.94, 1.04, dot(det, vec3(0.333)));

	// frozen pools: teal ice where a slow noise dips, never at the board edge
	float pool_n = texture(macro_height, uvm * 0.41 + vec2(0.23, 0.61)).r;
	float away = smoothstep(flat_margin + 1.0, flat_margin + 6.0, board_distance(world_pos.xz));
	float ice = smoothstep(0.66, 0.7, pool_n) * away * ice_amount;
	col = mix(col, ice_color.rgb, ice);

	// wind-blown snow: noise stretched along the wind, scrolling with it
	vec2 wd = normalize(wind_dir);
	vec2 perp = vec2(-wd.y, wd.x);
	float along = dot(world_pos.xz, wd) - TIME * wind_speed;
	float across = dot(world_pos.xz, perp);
	float s1 = texture(macro_height, vec2(along * 0.011, across * 0.085)).r;
	float s2 = texture(macro_height, vec2(along * 0.023 + 0.5, across * 0.16 + 0.2)).r;
	float streak = smoothstep(0.62, 0.92, s1 * 0.62 + s2 * 0.48);

	// a few glints that twinkle as the view moves
	vec2 cell = floor(world_pos.xz * 9.0);
	float rnd = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	float tw = fract(rnd * 7.13 + dot(VIEW, vec3(1.7, 2.9, 3.3)) * 0.6);
	float glint = step(0.985, rnd) * smoothstep(0.82, 1.0, tw) * (1.0 - ice);

	float haze = smoothstep(haze_start, haze_end, length(world_pos.xz));
	ALBEDO = col * (1.0 - haze);
	ROUGHNESS = mix(0.88, 0.14, ice);
	SPECULAR = mix(0.35, 0.6, ice);
	NORMAL_MAP = mix(texture(macro_normal, uvm).rgb, texture(detail_normal, uvd).rgb, 0.45);
	NORMAL_MAP_DEPTH = 1.0;
	vec3 lift = vec3(0.75, 0.86, 1.0) * (streak * streak_strength + glint * sparkle_strength) * (1.0 - haze);
	EMISSION = haze_color.rgb * haze + lift;
}
