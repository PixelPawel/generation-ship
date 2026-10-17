shader_type canvas_item;

// Main-menu backdrop: draws the Blender-rendered still cover-fit (like
// TextureRect KEEP_ASPECT_COVERED), then adds cheap ambient life on top:
// a slow push-in, drifting low fog, breathing Empire/Chaos glows at the
// Capital and the Curse, and a left-side shade + vignette so the title
// and buttons stay readable. Glow centres are in IMAGE uv space, so they
// stay locked to the pieces whatever the window aspect.

uniform sampler2D backdrop : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D fog_noise : filter_linear_mipmap, repeat_enable;
uniform vec2 rect_size = vec2(1152.0, 648.0);
uniform vec2 image_size = vec2(2560.0, 1440.0);
uniform float zoom = 1.0;
uniform vec2 pan = vec2(0.0, 0.0);
uniform float fade = 1.0;

uniform vec4 fog_color : source_color = vec4(0.62, 0.74, 0.92, 1.0);
uniform float fog_strength = 0.16;
uniform float fog_speed = 0.006;

uniform vec2 capital_uv = vec2(0.585, 0.47);
uniform vec4 capital_color : source_color = vec4(1.0, 0.22, 0.66, 1.0);
uniform float capital_strength = 0.10;
uniform vec2 curse_uv = vec2(0.9, 0.44);
uniform vec4 curse_color : source_color = vec4(0.62, 1.0, 0.2, 1.0);
uniform float curse_strength = 0.08;

uniform float left_shade = 0.62;
uniform float left_shade_width = 0.52;
uniform float vignette = 0.45;

vec2 cover_uv(vec2 uv) {
	float rect_aspect = rect_size.x / max(rect_size.y, 1.0);
	float img_aspect = image_size.x / image_size.y;
	vec2 p = uv - 0.5;
	if (rect_aspect > img_aspect) {
		p.y *= img_aspect / rect_aspect;
	} else {
		p.x *= rect_aspect / img_aspect;
	}
	return p / zoom + 0.5 + pan;
}

float glow(vec2 iuv, vec2 centre, float radius) {
	vec2 d = (iuv - centre) * vec2(image_size.x / image_size.y, 1.0);
	return exp(-dot(d, d) / (radius * radius));
}

void fragment() {
	vec2 iuv = cover_uv(UV);
	vec3 col = texture(backdrop, iuv).rgb;

	// Drifting mist, two noise layers moving at different speeds, densest
	// low over the board and thinning towards the dark sky.
	vec2 fuv = iuv * vec2(1.6, 0.9);
	float n1 = texture(fog_noise, fuv + vec2(TIME * fog_speed, TIME * fog_speed * 0.2)).r;
	float n2 = texture(fog_noise, fuv * 1.9 + vec2(-TIME * fog_speed * 1.6, 0.13)).r;
	float mist = smoothstep(0.35, 0.95, n1 * 0.65 + n2 * 0.45);
	float band = smoothstep(0.08, 0.5, iuv.y) * (1.0 - smoothstep(0.75, 1.05, iuv.y) * 0.5);
	col += fog_color.rgb * mist * band * fog_strength;

	// Breathing light: the Capital's magenta, the Curse's sickly green.
	float t = TIME;
	float cap_pulse = 0.75 + 0.25 * sin(t * 1.1) + 0.08 * sin(t * 3.7);
	float cur_pulse = 0.7 + 0.3 * sin(t * 0.83 + 1.7) + 0.1 * sin(t * 5.3);
	col += capital_color.rgb * glow(iuv, capital_uv, 0.16) * capital_strength * cap_pulse;
	col += curse_color.rgb * glow(iuv, curse_uv, 0.12) * curse_strength * cur_pulse;

	// Readability: shade the left column, darken the corners.
	float shade = left_shade * pow(1.0 - smoothstep(0.0, left_shade_width, UV.x), 1.35);
	col = mix(col, vec3(0.008, 0.016, 0.03), shade);
	vec2 v = UV - vec2(0.55, 0.5);
	float vig = smoothstep(0.35, 0.95, length(v * vec2(1.0, 1.15)));
	col *= 1.0 - vig * vignette;

	COLOR = vec4(col * fade, 1.0);
}
