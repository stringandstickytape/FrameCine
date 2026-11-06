// The video, in every projection: samples the decoder's NV12 planes in place (no conversion pass) and converts
// Y'CbCr (BT.709, BT.601 or BT.2020) to RGB, tone mapping HDR (PQ, HLG) to the display. Same plane conventions and
// conversion as spikes/03-player/project/video.gdshader.
//
// The mesh carries the projection: its UV is the position inside ONE EYE's picture (0..1), computed per vertex by
// ProjectionMeshes (quad for flat, latitude/longitude grid for equirect, polar grid for fisheye). This shader only
// picks the eye's rectangle in the frame (stereo layout, VIEW_INDEX), crops to the visible rectangle and converts.
// No trigonometry per fragment: the panels are 2 x 2160 x 2160 at 72-120 Hz on a battery.
//
// Dual fisheye 360 (ProjectionMeshes.dual_fisheye): UV is the front lens's place in the frame, UV2 the back lens's,
// and COLOR.r the front lens's weight (1 ahead, 0 behind, a smoothstep across the seam band). Outside the band one
// lens is sampled, as for every other projection; inside it (a few degrees wide) both are, and mixed.
//
// The picture itself (uniforms, sampling, colour) is in video_common.gdshaderinc, shared with the floor reflection.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_opaque, specular_disabled;

#include "res://shaders/video_common.gdshaderinc"

uniform bool dual_fisheye = false;

void fragment() {
	int view = int(VIEW_INDEX);
	float front = dual_fisheye ? COLOR.r : 1.0;
	// The footprints (video_common.gdshaderinc, footprint_taps), taken here in uniform control flow.
	vec2 dx = dFdx(UV);
	vec2 dy = dFdy(UV);
	vec2 dx2 = dFdx(UV2);
	vec2 dy2 = dFdy(UV2);
	vec3 rgb = front > 0.001 ? video_pixel_filtered(UV, dx, dy, view) : video_pixel_filtered(UV2, dx2, dy2, view);
	if (front > 0.001 && front < 0.999) {
		rgb = mix(video_pixel_filtered(UV2, dx2, dy2, view), rgb, front);
	}
	// The result is gamma-encoded; ALBEDO is linear. The sRGB curve stands in for BT.709/BT.1886 here.
	ALBEDO = srgb_to_linear(clamp(rgb, 0.0, 1.0)) * brightness;
}
