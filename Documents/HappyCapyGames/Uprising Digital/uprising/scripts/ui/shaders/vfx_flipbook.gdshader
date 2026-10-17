shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled;

// Camera-facing flipbook for the Blender/Mantaflow smoke sheets in
// assets/vfx (8x8 frames, channel-packed by Render/vfx/pack_fx.py):
//   R = lit smoke, G = fire/glow emission, A = coverage.
// One sheet serves every colour: smoke_color tints the smoke, glow_color
// the fiery core (added on top, so it glows through the smoke).
// Pivot is the bottom centre of the quad (QuadMesh center_offset y 0.5),
// i.e. where the effect touches the board.

uniform sampler2D sheet : filter_linear_mipmap, repeat_disable;
uniform vec2 grid = vec2(8.0, 8.0);
uniform vec4 smoke_color : source_color = vec4(0.8, 0.82, 0.85, 1.0);
uniform vec4 glow_color : source_color = vec4(0.6, 1.0, 0.2, 1.0);
uniform float glow_energy = 3.0;
uniform float opacity = 1.0;
instance uniform float progress = 0.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float frames = grid.x * grid.y;
	float f = clamp(progress, 0.0, 0.9999) * frames;
	float f0 = floor(f);
	float t = f - f0;
	float f1 = min(f0 + 1.0, frames - 1.0);
	vec2 cell = vec2(1.0) / grid;
	vec2 uv0 = (vec2(mod(f0, grid.x), floor(f0 / grid.x)) + UV) * cell;
	vec2 uv1 = (vec2(mod(f1, grid.x), floor(f1 / grid.x)) + UV) * cell;
	vec4 s = mix(texture(sheet, uv0), texture(sheet, uv1), t);
	float alpha = s.a * opacity;
	vec3 lit = smoke_color.rgb * s.r * alpha;
	vec3 glow = glow_color.rgb * s.g * glow_energy * opacity;
	ALBEDO = lit + glow;
	ALPHA = alpha;
}
