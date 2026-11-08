// A plane mirror (scripts/env/mirror_view.gd): each eye sees its own reflection, rendered that frame by a camera at
// the eye's mirror image whose frustum is the mirror's rectangle. So the reflection's texel under a fragment is the
// one the fragment's UV names, turned left to right: the reflected camera's right is the viewer's left.
// Unshaded and without fog: the reflection is already lit and fogged along its whole path (the reflected eye to the
// mirror is as long as the eye to the mirror). The viewports' colour is sRGB-encoded (source_color decodes it), so
// the main pass's tonemap (linear, main.tscn) gives it back unchanged.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, depth_draw_opaque, specular_disabled, fog_disabled;

uniform sampler2D left_view : source_color, filter_linear, repeat_disable;
uniform sampler2D right_view : source_color, filter_linear, repeat_disable;
// Old silvering on glass, its reflectance (linear): a little dimmer than a new mirror and slightly warm.
uniform vec3 tint = vec3(0.82, 0.78, 0.68);
// The mirror's half width and half height (metres), and how far in from its edge the tarnish fades (metres) and how
// dark it is at the very edge.
uniform vec2 half_size = vec2(0.4, 0.3);
uniform float tarnish_width = 0.03;
uniform float tarnish = 0.22;

void fragment() {
	vec2 uv = vec2(1.0 - UV.x, UV.y);
	vec3 c = VIEW_INDEX == VIEW_RIGHT ? texture(right_view, uv).rgb : texture(left_view, uv).rgb;
	vec2 from_edge = (0.5 - abs(UV - 0.5)) * 2.0 * half_size;
	float edge = smoothstep(0.0, tarnish_width, min(from_edge.x, from_edge.y));
	ALBEDO = c * tint * mix(1.0 - tarnish, 1.0, edge);
}
