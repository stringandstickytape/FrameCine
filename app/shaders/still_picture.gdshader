shader_type canvas_item;
render_mode unshaded;

// A video's picture drawn on the music card (scripts/play/music_source.gd, a video that is a still picture): the
// decoder's planes (NV12, or P010 for 10 bits) to RGB with the file's matrix and range, dimmed so the words and the
// visualiser over it stay readable. The screen's own HDR and picture controls are not applied: this is a backdrop.

uniform sampler2D y_tex : filter_linear, repeat_disable;
uniform sampler2D uv_tex : filter_linear, repeat_disable;
uniform bool p010 = false;
// The visible part of the decoded buffer (xy offset, zw size in UV): the decoder pads the height.
uniform vec4 visible_rect = vec4(0.0, 0.0, 1.0, 1.0);
// 0 BT.709, 1 BT.601, 2 BT.2020.
uniform int yuv_matrix = 0;
uniform bool full_range = false;
uniform float dim = 0.45;

const float P010_SCALE = 65535.0 / 65280.0;

void fragment() {
	vec2 uv = visible_rect.xy + UV * visible_rect.zw;
	float y = textureLod(y_tex, uv, 0.0).r;
	vec4 c = textureLod(uv_tex, uv, 0.0);
	vec2 cbcr = p010 ? c.rg : c.ra;
	if (p010) {
		y *= P010_SCALE;
		cbcr *= P010_SCALE;
	}
	if (full_range) {
		cbcr -= 128.0 / 255.0;
	} else {
		y = (y - 16.0 / 255.0) * (255.0 / 219.0);
		cbcr = (cbcr - 128.0 / 255.0) * (255.0 / 224.0);
	}
	vec3 rgb;
	if (yuv_matrix == 2) {
		rgb = vec3(y + 1.4746 * cbcr.y, y - 0.164553 * cbcr.x - 0.571353 * cbcr.y, y + 1.8814 * cbcr.x);
	} else if (yuv_matrix == 1) {
		rgb = vec3(y + 1.402 * cbcr.y, y - 0.344136 * cbcr.x - 0.714136 * cbcr.y, y + 1.772 * cbcr.x);
	} else {
		rgb = vec3(y + 1.5748 * cbcr.y, y - 0.1873 * cbcr.x - 0.4681 * cbcr.y, y + 1.8556 * cbcr.x);
	}
	COLOR = vec4(clamp(rgb, 0.0, 1.0) * dim, 1.0);
}
