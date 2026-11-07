// The film on the screen's mesh through a room's presentation chain (scripts/env/systems/presentation.gd): the
// screen's own picture (video_common.gdshaderinc, its uniforms copied from the screen's material each frame) with
// the stages of env_presentation.gdshaderinc. The presentation system puts this material on the screen's flat mesh
// while the room has a picture stage, and the film layer steps aside for it (scripts/play/film_layer.gd,
// request_scene()): a composition layer would skip the scene's shaders.
// Same render modes and output as video.gdshader; flat screens only (the sphere keeps the screen's material).
// The set's window (its tube or panel, `tube`) can be taller than the film's quad (a wide film in a 4:3 tube): the
// quad grows to the window in the vertex stage (pr_expand(): only its height, so a curved screen keeps its curve),
// and what lies outside the window is discarded (the set's bezel shows there).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_opaque, specular_disabled;

#include "res://shaders/video_common.gdshaderinc"
#include "res://shaders/env_presentation.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	vec2 e = pr_expand();
	VERTEX.xy *= e;
	UV = (UV - 0.5) * e + 0.5;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	int view = int(VIEW_INDEX);
	float time = TIME;
	vec2 p = pr_geometry(UV, time);
	// The footprint of the sample position, in uniform control flow (video_common.gdshaderinc, footprint_taps).
	vec2 dx = dFdx(p);
	vec2 dy = dFdy(p);
	if (pr_display == 4) {
		// A rear projection's soft focus: the footprint widened by a few texels.
		dx += vec2(pr_soft * 0.0018, 0.0);
		dy += vec2(0.0, pr_soft * 0.0018 * pr_aspect);
	}
	vec2 q = p;
	if (pr_display == 1) {
		// A mechanical-scan set: the picture at each line's middle.
		p.x = (floor(p.x * pr_mech_lines) + 0.5) / pr_mech_lines;
	}
	vec3 rgb = clamp(video_pixel_filtered(p, dx, dy, view), 0.0, 1.0);
	if (pr_display == 4 && pr_convergence > 0.0) {
		rgb = pr_converged(rgb, p, view);
	}
	if (pr_source == 2 && pr_bleed > 0.0) {
		rgb = pr_bleed_colour(rgb, p, view);
	}
	if (pr_ghost > 0.0) {
		rgb = pr_ghosted(rgb, p, view);
	}
	rgb = pr_source_marks(rgb, p, time);
	rgb = pr_transmission(rgb, p, time);
	rgb = pr_colour_of(rgb);
	vec2 c0 = (UV - 0.5) * vec2(pr_aspect, 1.0);
	if (pr_switching) {
		rgb = pr_power_of(rgb, pr_bulged(c0));
	}
	vec3 ax = normalize(MODEL_MATRIX[0].xyz);
	vec3 ay = normalize(MODEL_MATRIX[1].xyz);
	vec3 az = normalize(MODEL_MATRIX[2].xyz);
	rgb = pr_display_of(rgb, UV, q, normalize(CAMERA_POSITION_WORLD - world_pos), ax, ay, az, world_pos,
			CAMERA_POSITION_WORLD, MODEL_MATRIX[3].xyz);
	if (pc_deband > 0.0 && !p010) {
		rgb += dither(FRAGCOORD.xy, TIME);
	}
	ALBEDO = srgb_to_linear(clamp(rgb, 0.0, 1.0)) * brightness;
	if (pr_tube > 0.0) {
		// Outside the set's window: the bezel (or the mirror's dark) shows.
		vec2 w = pr_tube_half();
		if (abs(c0.x) > w.x || abs(c0.y) > w.y) {
			discard;
		}
	}
}
