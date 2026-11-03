// The selection_outline effect's second pass (scripts/effects/catalogue/transitions.gd): a soft glow around the
// part's silhouette, as room_outline.gdshader's line: the part's back faces pushed out from its centre on the
// screen, in pixels (the same width near and far), drawn behind the part, here added as light. On curved parts the
// glow fades towards its outer edge (where the pushed back faces turn edge-on), so it reads as a glow, not a band;
// on flat faces it is even.
//
// It may breathe: its brightness 1 +- swing on a slow sine (at most 1 Hz, swing at most FX_MAX_SWING), on the
// engine's clock (FX_TIME: this pass is compiled as it is, never with FX_TEST_CLOCK), so the photosensitivity clip
// does not see it move; its declared bounds (1 Hz x 0.4) are well under the ceiling.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, specular_disabled, blend_add, depth_draw_never;

#include "res://shaders/fx/fx_common.gdshaderinc"

uniform vec3 glow_color : source_color = vec3(0.45, 0.8, 1.0);
uniform float glow_strength = 1.0;
// Pixels.
uniform float width = 4.0;
// Hz (at most 1) and how far the brightness swings (0: still).
uniform float breath_rate = 0.5;
uniform float breath_swing = 0.2;

void vertex() {
	vec3 dir = length(VERTEX) > 1e-5 ? normalize(VERTEX) : NORMAL;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec2 on_screen = (PROJECTION_MATRIX * vec4(mat3(MODELVIEW_MATRIX) * dir, 0.0)).xy;
	// 1.4: a corner moves diagonally, so a straight edge moves out by about 0.7 of the push.
	if (length(on_screen) > 1e-6) {
		clip.xy += normalize(on_screen) * clamp(width, 0.0, 16.0) * 1.4 * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	// VERTEX and NORMAL are the back face's own (in view space, before the push): edge-on at the glow's outer edge.
	float facing = abs(dot(normalize(NORMAL), normalize(-VERTEX)));
	float soft = smoothstep(0.0, 0.3, facing);
	float breath = fx_swing(sin(FX_TAU * clamp(breath_rate, 0.0, 1.0) * FX_TIME), breath_swing);
	ALBEDO = glow_color * clamp(glow_strength, 0.0, 3.0) * soft * breath;
}
