// The visualisers' flash limit, first pass (scripts/visualisers/visualiser_host.gd, docs/visualisers.md, "The flash
// limit"): one pixel per sample point, TAPS (128 x 72) over the visualiser's picture. Each point's relative luminance
// (linear light; four samples over its patch; see-through parts count as the card behind), its own slow average
// (time constant `tau`), and how far it stands from that average now: the flicker at that point. A pattern that swaps
// (a checkerboard, stripes) moves every point though the picture's average stays put.
// Out: r, g the point's average (two bytes); b the flicker (square root); a the luminance now.
// `previous` is last frame's output (the copy of this pass).
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D picture : filter_linear, repeat_disable;
uniform sampler2D previous : filter_nearest, repeat_disable;
uniform vec2 taps = vec2(128.0, 72.0);
uniform float dt = 0.0167;
uniform float tau = 0.25;
uniform float behind = 0.004;
uniform bool reset = true;

float lum(vec4 c) {
	vec3 s = clamp(c.rgb, 0.0, 1.0);
	vec3 lin = mix(s / 12.92, pow((s + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), s));
	return dot(lin, vec3(0.2126, 0.7152, 0.0722)) + behind * (1.0 - c.a);
}

void fragment() {
	vec2 step_uv = 0.25 / taps;
	float l = 0.25 * (lum(texture(picture, UV + vec2(-step_uv.x, -step_uv.y)))
			+ lum(texture(picture, UV + vec2(step_uv.x, -step_uv.y)))
			+ lum(texture(picture, UV + vec2(-step_uv.x, step_uv.y)))
			+ lum(texture(picture, UV + vec2(step_uv.x, step_uv.y))));
	vec4 p = texture(previous, UV);
	float avg_was = reset ? l : p.r + p.g / 255.0;
	float flicker = reset ? 0.0 : abs(l - avg_was);
	float avg = clamp(mix(avg_was, l, 1.0 - exp(-dt / tau)), 0.0, 1.0);
	COLOR = vec4(floor(avg * 255.0) / 255.0, fract(avg * 255.0), sqrt(clamp(flicker, 0.0, 1.0)), l);
}
