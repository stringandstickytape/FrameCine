// The picture of another item fading in over the screen (scripts/play/crossfade.gd, ideas #94): the screen's own
// conversion (video_common.gdshaderinc) with an alpha. Drawn on a quad just in front of the flat screen.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, specular_disabled;

#include "res://shaders/video_common.gdshaderinc"

// 0: not seen; 1: covers the screen.
uniform float fade = 1.0;

void fragment() {
	ALBEDO = srgb_to_linear(clamp(video_pixel(UV, int(VIEW_INDEX)), 0.0, 1.0)) * brightness;
	ALPHA = clamp(fade, 0.0, 1.0);
}
