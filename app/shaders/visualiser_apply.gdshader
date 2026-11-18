// The visualiser on the music card (scripts/visualisers/visualiser_host.gd): its picture (premultiplied: drawn into a
// see-through viewport) scaled in linear light by the flash limit (visualiser_limit.gdshader): the whole picture's
// gain, and where a cell's flicker C is over the cap k, k / C (the cells' flicker read smoothly between cells).
shader_type canvas_item;
render_mode blend_premul_alpha;

uniform sampler2D state : filter_nearest, repeat_disable;
uniform sampler2D cells : filter_linear, repeat_disable;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float gain = texture(state, vec2(0.25, 0.25)).a;
	vec4 k4 = texture(state, vec2(0.75, 0.25));
	float k = k4.r + k4.g / 255.0;
	vec4 f4 = texture(cells, UV);
	float flicker = f4.r + f4.g / 255.0;
	if (flicker > k && flicker > 0.0001) {
		gain *= k / flicker;
	}
	COLOR = vec4(to_srgb(to_linear(clamp(c.rgb, 0.0, 1.0)) * gain), c.a);
}
