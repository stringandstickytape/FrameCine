// The bias light's picture sampler (scripts/env/bias_light.gd, ideas #29): drawn on one quad filling a tiny viewport
// (4 x 2 pixels). Each pixel is the mean linear colour of its part of the picture (6 x 6 samples through the screen's
// own uniforms), blended over what the viewport kept from the frames before (background "keep", never cleared):
// an exponential average over time, so the room's tint follows the film without flicker.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, specular_disabled;

#include "res://shaders/video_common.gdshaderinc"

// The share of this frame in the average (1: no smoothing).
uniform float blend = 1.0;
uniform vec2 cells = vec2(4.0, 2.0);

void fragment() {
	vec2 cell = floor(UV * cells);
	vec3 sum = vec3(0.0);
	for (int j = 0; j < 6; j++) {
		for (int i = 0; i < 6; i++) {
			vec2 uv = (cell + (vec2(float(i), float(j)) + 0.5) / 6.0) / cells;
			sum += srgb_to_linear(clamp(video_pixel(uv, 0), 0.0, 1.0));
		}
	}
	ALBEDO = sum / 36.0 * brightness;
	ALPHA = blend;
}
