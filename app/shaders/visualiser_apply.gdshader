// The visualiser on the music card (scripts/visualisers/visualiser_host.gd): its picture (premultiplied: drawn into a
// see-through viewport) scaled in linear light by the flash limit's gain (visualiser_limit.gdshader's alpha).
shader_type canvas_item;
render_mode blend_premul_alpha;

uniform sampler2D state : filter_nearest, repeat_disable;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float gain = texture(state, vec2(0.5)).a;
	COLOR = vec4(to_srgb(to_linear(clamp(c.rgb, 0.0, 1.0)) * gain), c.a);
}
