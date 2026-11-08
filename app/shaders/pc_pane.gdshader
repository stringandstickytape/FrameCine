// A PC window's pane (app/scripts/pc/pc_pane.gd): the decoder's planes as video_common.gdshaderinc reads them (NV12:
// Y as .r, CbCr as .ra; P010: .r and .rg, scaled), BT.709 limited range as the PC's encoders write a desktop, and a
// thin outline in the accent colour while the pane has the focus. No tone mapping, no grading: it is a desktop.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_opaque, specular_disabled;

uniform sampler2D y_tex : filter_linear, repeat_disable;
uniform sampler2D uv_tex : filter_linear, repeat_disable;
uniform bool p010 = false;
uniform bool has_picture = false;
uniform vec4 visible_rect = vec4(0.0, 0.0, 1.0, 1.0);
// The pane's size in metres (for an outline of the same width on every side).
uniform vec2 size_m = vec2(1.0, 0.6);
uniform float outline_m = 0.004;
uniform float outline = 0.0;
uniform vec4 outline_colour : source_color = vec4(0.36, 0.62, 1.0, 1.0);
uniform vec4 empty_colour : source_color = vec4(0.06, 0.07, 0.08, 1.0);

const float P010_SCALE = 65535.0 / 65280.0;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec2 uv = visible_rect.xy + UV * visible_rect.zw;
	vec3 rgb = empty_colour.rgb;
	if (has_picture) {
		float y = textureLod(y_tex, uv, 0.0).r;
		vec4 c = textureLod(uv_tex, uv, 0.0);
		vec2 cbcr = p010 ? c.rg * P010_SCALE : c.ra;
		y = p010 ? y * P010_SCALE : y;
		y = (y - 16.0 / 255.0) * (255.0 / 219.0);
		cbcr = (cbcr - 128.0 / 255.0) * (255.0 / 224.0);
		rgb = clamp(vec3(y + 1.5748 * cbcr.y, y - 0.1873 * cbcr.x - 0.4681 * cbcr.y, y + 1.8556 * cbcr.x), 0.0, 1.0);
		rgb = srgb_to_linear(rgb);
	}
	vec2 m = min(UV, 1.0 - UV) * size_m;
	if (outline > 0.0 && min(m.x, m.y) < outline_m) {
		rgb = mix(rgb, outline_colour.rgb, outline);
	}
	ALBEDO = rgb;
}
