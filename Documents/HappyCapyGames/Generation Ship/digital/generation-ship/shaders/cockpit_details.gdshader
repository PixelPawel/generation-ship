shader_type spatial;
// The cockpit's dash consoles, strut columns and running lights, baked in Blender
// (Render/cockpit/export_details.py): one atlas for colour, roughness (G) + metal (B)
// and glow colour. How strong each part glows depends on mode:
//   0 panels - UV2.y picks the part's row in schedule_tex (strength per frame of the
//              10 s loop / max_strength): lamps blink, two old bulbs stutter
//   1 wave   - the nav oscilloscope trace, UV2 = screen coords
//   2 radar  - the nav scope sweep with blips, UV2 = disc coords (radius 1)
//   3 accent - a pulse running along the light strips, UV2.x = 0..1 along the strip
// The patterns are the Blender shaders' (panels.py screen_mat / accent_mat) frame for frame.

uniform int mode = 0;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D rm_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D emit_tex : source_color, hint_default_black, filter_linear_mipmap;
uniform sampler2D schedule_tex : hint_default_white, filter_linear, repeat_enable;
uniform float max_strength = 6.0;
uniform float glow = 0.45;           // Blender emission strength -> Godot emission energy
uniform float fps = 24.0;
uniform float loop_frames = 240.0;

const float TWO_PI = 6.28318530718;
const vec2 BLIPS[4] = vec2[4](vec2(0.42, 0.3), vec2(-0.25, 0.55), vec2(-0.5, -0.38), vec2(0.2, -0.62));

float less(float a, float b) {
	return 1.0 - step(b, a);
}

float wave(vec2 p, float f) {
	float ph = f * 4.0 * TWO_PI / loop_frames;
	float yw = sin(p.x * 9.0 - ph) * 0.55 * (sin(p.x * 2.3 + ph * 0.5) * 0.35 + 0.65);
	float line = pow(max(1.0 - abs(p.y - yw) / 0.09, 0.0), 2.0);
	float gx = less(abs(fract(p.x * 2.5) - 0.5), 0.02);
	float gy = less(abs(fract(p.y * 1.5) - 0.5), 0.03);
	return line * 4.0 + max(gx, gy) * 0.18 + 0.04;
}

float radar(vec2 p, float f) {
	float sweep = f * -2.0 * TWO_PI / loop_frames;   // two turns per loop, clockwise
	float trail = pow(1.0 - fract((atan(p.y, p.x) - sweep) / TWO_PI), 7.0);
	float rings = less(abs(fract(length(p) * 4.0) - 0.5), 0.035);
	float cross_lines = less(min(abs(p.x), abs(p.y)), 0.008);
	float v = trail * 1.6 + max(rings, cross_lines) * 0.35;
	for (int i = 0; i < 4; i++) {
		float dot_ = pow(max(1.0 - distance(p, BLIPS[i]) / 0.055, 0.0), 1.5);
		v += dot_ * trail * 12.0;
	}
	return v + 0.05;
}

float accent(float u, float f) {
	float d = fract(u - f * 2.0 / loop_frames);
	return 0.45 + pow(max(1.0 - abs(d - 0.5) * 7.0, 0.0), 3.0) * 6.0;
}

void fragment() {
	float t = mod(TIME * fps, loop_frames);   // 0..240 = Blender frames 1..241
	vec2 p = vec2(UV2.x, 1.0 - UV2.y);        // glTF stores V flipped
	float s;
	if (mode == 1) {
		s = wave(p, t + 1.0);
	} else if (mode == 2) {
		s = radar(p, t + 1.0);
	} else if (mode == 3) {
		s = accent(UV2.x, t + 1.0);
	} else {
		s = texture(schedule_tex, vec2((t + 0.5) / loop_frames, UV2.y)).r * max_strength;
	}
	vec3 rm = texture(rm_tex, UV).rgb;
	ALBEDO = texture(albedo_tex, UV).rgb;
	ROUGHNESS = rm.g;
	METALLIC = rm.b;
	EMISSION = texture(emit_tex, UV).rgb * s * glow;
}
