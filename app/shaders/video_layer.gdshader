// The film for an OpenXR composition layer (scripts/play/film_layer.gd): one eye's picture drawn flat into the
// layer's SubViewport, which the runtime then samples once for the lenses. Same picture as video.gdshader: the
// uniforms of video_common.gdshaderinc, copied from the screen's material; force_eye picks the eye (0 for a layer
// both eyes see). The result stays gamma-encoded: a 2D viewport writes it unchanged, and the layer's swapchain is
// read as sRGB, so the colour matches the screen's (which writes linear light into an sRGB eye buffer).
shader_type canvas_item;
render_mode unshaded, blend_disabled;

#include "res://shaders/video_common.gdshaderinc"

void fragment() {
	vec3 rgb = clamp(video_pixel(UV, 0), 0.0, 1.0);
	// video.gdshader dims in linear light (ALBEDO times brightness); the same here.
	if (brightness != 1.0) {
		rgb = linear_to_srgb(srgb_to_linear(rgb) * brightness);
	}
	// The deband's dither (video_common.gdshaderinc), in the layer's own 8-bit values.
	if (pc_deband > 0.0 && !p010) {
		rgb = clamp(rgb + dither(FRAGCOORD.xy, TIME), 0.0, 1.0);
	}
	COLOR = vec4(rgb, 1.0);
}
