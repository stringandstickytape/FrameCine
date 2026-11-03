// Debug overlay: shows a SubViewport whose top band holds two labels side by side ("LEFT EYE" | "RIGHT EYE").
// Each eye sees only its own label (VIEW_INDEX), stretched over the band, so a glance in the headset tells which
// view index reaches which eye. The rest of the texture (statistics) is shown as is. Drawn on top of everything.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, shadows_disabled, specular_disabled;

uniform sampler2D overlay : source_color, filter_linear, repeat_disable;
// Height of the eye-label band, as a fraction of the texture.
uniform float band = 0.25;
// -1: VIEW_INDEX; 0 / 1: force an eye (desktop screenshots).
uniform int force_eye = -1;
uniform float opacity = 1.0;

void fragment() {
	int eye = force_eye >= 0 ? force_eye : int(VIEW_INDEX);
	vec2 uv = UV;
	if (uv.y < band) {
		uv.x = (uv.x + float(eye)) * 0.5;
	}
	vec4 c = texture(overlay, uv);
	ALBEDO = c.rgb;
	ALPHA = c.a * opacity;
}
