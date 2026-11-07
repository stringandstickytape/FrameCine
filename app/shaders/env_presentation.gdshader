// The film on the screen's mesh through a room's presentation chain (scripts/env/systems/presentation.gd): the
// screen's own picture (video_common.gdshaderinc, its uniforms copied from the screen's material each frame) with
// the stages of env_presentation.gdshaderinc. The presentation system puts this material on the screen's flat mesh
// while the room has a picture stage, and the film layer steps aside for it (scripts/play/film_layer.gd,
// request_scene()): a composition layer would skip the scene's shaders.
// Same render modes and output as video.gdshader; flat screens only (the sphere keeps the screen's material).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_opaque, specular_disabled;

#include "res://shaders/video_common.gdshaderinc"
#include "res://shaders/env_presentation.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	int view = int(VIEW_INDEX);
	float time = TIME;
	vec2 p = pr_geometry(UV, time);
	// The footprint of the sample position, in uniform control flow (video_common.gdshaderinc, footprint_taps).
	vec2 dx = dFdx(p);
	vec2 dy = dFdy(p);
	vec2 q = p;
	if (pr_display == 1) {
		// A mechanical-scan set: the picture at each line's middle.
		p.x = (floor(p.x * pr_mech_lines) + 0.5) / pr_mech_lines;
	}
	vec3 rgb = clamp(video_pixel_filtered(p, dx, dy, view), 0.0, 1.0);
	if (pr_source == 2 && pr_bleed > 0.0) {
		rgb = pr_bleed_colour(rgb, p, view);
	}
	if (pr_ghost > 0.0) {
		rgb = pr_ghosted(rgb, p, view);
	}
	rgb = pr_source_marks(rgb, p, time);
	rgb = pr_transmission(rgb, p, time);
	rgb = pr_colour_of(rgb);
	vec3 ax = normalize(MODEL_MATRIX[0].xyz);
	vec3 ay = normalize(MODEL_MATRIX[1].xyz);
	vec3 az = normalize(MODEL_MATRIX[2].xyz);
	rgb = pr_display_of(rgb, UV, q, normalize(CAMERA_POSITION_WORLD - world_pos), ax, ay, az);
	if (pc_deband > 0.0 && !p010) {
		rgb += dither(FRAGCOORD.xy, TIME);
	}
	ALBEDO = srgb_to_linear(clamp(rgb, 0.0, 1.0)) * brightness;
}
