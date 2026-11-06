// A soft contact shadow under a part that stands on the floor (scripts/assistant/assistant_room.gd), made once when the
// room is built: a quad on the floor, black blended over it with the shadow's strength as its alpha, darkest under the
// part's middle and fading smoothly past its footprint. Free per frame next to a shadow map, and soft where a shadow
// map is not. Not blend_mul: the Mobile renderer divides every colour it writes by its luminance multiplier (2 with a
// 10-bit buffer, scene_forward_mobile.glsl), so a multiplied "white" halved the floor under the whole quad: a dark
// square under every object (the user, 2026-11-06). Black is black whatever the multiplier.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

// Half the footprint (metres) and how far the shadow reaches past it.
uniform vec2 half_size = vec2(0.5);
uniform float reach = 0.25;
uniform float strength = 0.45;

varying vec2 local;

void vertex() {
	// The quad is 2 x 2 units scaled to the footprint plus its reach: local in metres from the middle.
	local = VERTEX.xz * (half_size + vec2(reach));
}

void fragment() {
	// Distance outside a rounded box of the footprint (inside: negative).
	vec2 q = abs(local) - half_size * 0.85;
	float outside = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
	float dark = strength * (1.0 - smoothstep(-0.15 * min(half_size.x, half_size.y), reach, outside));
	ALBEDO = vec3(0.0);
	ALPHA = dark;
}
