shader_type canvas_item;
uniform float corner_radius : hint_range(0.0, 0.5) = 0.06;
uniform float brightness : hint_range(0.0, 1.5) = 0.70;

// the node's modulate (popup fades, the menu's invisible warm-up draw); taken
// in vertex() because fragment's COLOR already has the texture multiplied in
varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

void fragment() {
	vec2 c = vec2(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	vec4 tex = texture(TEXTURE, UV);
	float alpha = tex.a;
	if (c.x < corner_radius && c.y < corner_radius) {
		float d = length(c - vec2(corner_radius));
		alpha *= smoothstep(corner_radius, corner_radius - 0.01, d);
	}
	COLOR = vec4(tex.rgb * brightness, alpha) * v_modulate;
}
