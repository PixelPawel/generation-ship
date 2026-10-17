shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// A Curse on a hex: black rot creeping in from the hex rim with sickly
// green veins pulsing through it, leaving the card art readable in the
// middle. Drawn on a flat hexagon just above the tile (board_view.gd);
// `coverage` animates 0 -> 0.62 when the Curse lands and back on removal.

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float coverage : hint_range(0.0, 1.0) = 0.62;
uniform vec4 rot_color : source_color = vec4(0.025, 0.05, 0.02, 1.0);
uniform vec4 vein_color : source_color = vec4(0.62, 1.0, 0.18, 1.0);
uniform float vein_energy = 2.6;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 p = local_pos.xz * 0.5;
	float r = length(p);
	float n1 = texture(noise_tex, p * 0.55 + vec2(TIME * 0.006, 0.0)).r;
	float n2 = texture(noise_tex, p * 1.35 + vec2(0.31, -TIME * 0.01)).r;
	float creep = r + (n1 - 0.5) * 0.55;
	float edge = 1.0 - coverage;
	float mask = smoothstep(edge, edge + 0.22, creep);
	float veins = 1.0 - smoothstep(0.0, 0.035, abs(n2 - 0.5));
	float pulse = 0.55 + 0.45 * sin(TIME * 1.6 + n1 * 9.0);
	vec3 col = mix(rot_color.rgb, vein_color.rgb * vein_energy, veins * pulse);
	ALBEDO = col;
	ALPHA = clamp(mask * (0.78 + veins * 0.22), 0.0, 1.0);
}
