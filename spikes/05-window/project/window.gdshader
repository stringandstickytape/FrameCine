shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// The captured window. X11WindowSource gives sRGB-encoded values in a UNORM texture (no sRGB view on the dmabuf), so
// decode here; alpha is 1 for ordinary (depth 24) windows.
uniform sampler2D window_tex : filter_linear, repeat_disable;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	ALBEDO = srgb_to_linear(texture(window_tex, UV).rgb);
}
