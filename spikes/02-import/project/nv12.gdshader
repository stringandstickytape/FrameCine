// Samples the two planes of an NV12 frame directly (no conversion pass) and converts Y'CbCr to RGB.
shader_type spatial;
render_mode unshaded, cull_disabled;

// Plane 0 (Y) and plane 1 (interleaved CbCr, half size), each wrapped in a Texture2DRD.
// Texture2DRD shows R8 as luminance (r = g = b = Y) and R8G8 as luminance + alpha, so Cb is in .r and Cr in .a.
uniform sampler2D y_tex : filter_linear, repeat_disable;
uniform sampler2D uv_tex : filter_linear, repeat_disable;
// Video is almost always limited range (Y 16-235, CbCr 16-240). Set for full-range (JPEG-style) sources.
uniform bool full_range = false;
// P010 planes (R16 and R16G16): Y in .r, CbCr in .rg, 10 bits in the high bits of 16.
uniform bool p010 = false;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	float y = texture(y_tex, UV).r;
	vec2 cbcr = texture(uv_tex, UV).ra;
	if (p010) {
		// To the 8-bit scale: (v << 6) / 65535 * 65535 / 65280 = v / 1020.
		cbcr = texture(uv_tex, UV).rg * (65535.0 / 65280.0);
		y *= 65535.0 / 65280.0;
	}

	if (full_range) {
		cbcr -= 128.0 / 255.0;
	} else {
		y = (y - 16.0 / 255.0) * (255.0 / 219.0);
		cbcr = (cbcr - 128.0 / 255.0) * (255.0 / 224.0);
	}

	// BT.709 (Kr = 0.2126, Kb = 0.0722).
	vec3 rgb = vec3(
			y + 1.5748 * cbcr.y,
			y - 0.1873 * cbcr.x - 0.4681 * cbcr.y,
			y + 1.8556 * cbcr.x);

	// The result is gamma-encoded; ALBEDO is linear. The sRGB curve stands in for BT.709/BT.1886 here.
	ALBEDO = srgb_to_linear(clamp(rgb, 0.0, 1.0));
}
