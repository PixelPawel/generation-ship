shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// Ground shockwave: a bright ring racing outward over the hex and fading,
// drawn on a flat PlaneMesh lying on the board. `progress` 0..1 per
// instance, driven by vfx_effect.gd.

uniform vec4 ring_color : source_color = vec4(1.0, 0.3, 0.8, 1.0);
uniform float energy = 3.0;
instance uniform float progress = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float radius = mix(0.08, 0.96, sqrt(progress));
	float width = mix(0.2, 0.035, progress);
	float ring = 1.0 - smoothstep(0.0, width, abs(r - radius));
	float inner = (1.0 - smoothstep(0.0, radius, r)) * 0.22 * (1.0 - progress);
	float fade = (1.0 - progress) * (1.0 - progress);
	float v = (ring + inner) * fade;
	ALBEDO = ring_color.rgb * energy * v;
	ALPHA = clamp(v, 0.0, 1.0);
}
