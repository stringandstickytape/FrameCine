// The legends printed in our controller model's texture (white on the dark plastic, tools/controller_model/bake.py),
// drawn over the controllers' look (scripts/xr/controller_look.gd) in a contrasting ink, on a soft backing where the
// look is busy or mid-toned. Used by controller_model.gdshader and, compiled with FX_PRINT, by the effect library's
// shaders (fx_common.gdshaderinc), so a look keeps the print in its one pass.
//
// The ink is the texture's own coverage of the legends (a ramp over its antialiased edges). The backing is the same
// coverage read PRINT_SPREAD mip levels coarser: it reaches a few texels past each stroke and fades out, a halo behind
// the letters at the cost of one more texture read.
uniform sampler2D print_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_print = false;
uniform vec3 print_ink : source_color = vec3(1.0);
uniform vec3 print_backing : source_color = vec3(0.0);
// 1: the backing shows (controller_look.gd print_style()), 0: the ink alone.
uniform float print_backing_on = 0.0;
// Linear light: the plastic is under 0.04, the legends 1.
const float PRINT_FROM = 0.06;
const float PRINT_TO = 0.5;
const float PRINT_SPREAD = 2.5;
const float PRINT_HALO_GAIN = 8.0;

float controller_print_cover(vec3 c) {
	return clamp((dot(c, vec3(0.2126, 0.7152, 0.0722)) - PRINT_FROM) / (PRINT_TO - PRINT_FROM), 0.0, 1.0);
}

vec3 controller_print(vec3 col, vec2 uv) {
	if (!use_print) {
		return col;
	}
	float ink = controller_print_cover(texture(print_texture, uv).rgb);
	float near = clamp(controller_print_cover(texture(print_texture, uv, PRINT_SPREAD).rgb) * PRINT_HALO_GAIN, 0.0,
			1.0);
	col = mix(col, print_backing, near * clamp(print_backing_on, 0.0, 1.0));
	return mix(col, print_ink, ink);
}
