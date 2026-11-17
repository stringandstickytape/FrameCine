// The visualisers' flash limit, measuring half (scripts/visualisers/visualiser_host.gd, docs/visualisers.md,
// "The flash limit"): drawn over a 2 x 2 viewport (the engine's smallest; every pixel the same) each frame, after the
// visualiser and before the card. It averages the visualiser's relative luminance (32 x 32 samples, linear light,
// see-through parts counted as the card behind), keeps a floor that follows the picture down at once and up at most
// `rise` a second, and lets the picture be at most `margin` over the floor. Out: r, g the floor (two bytes), b the
// measured average (square root), a the gain the card applies (1: untouched). `previous` is last frame's output (the
// copy viewport).
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D picture : filter_linear, repeat_disable;
uniform sampler2D previous : filter_nearest, repeat_disable;
uniform float dt = 0.0167;
uniform float margin = 0.08;
uniform float rise = 0.2;
uniform float behind = 0.004;
uniform bool reset = true;

float lum(vec3 c) {
	vec3 lin = mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
	return dot(lin, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	float sum = 0.0;
	for (int y = 0; y < 32; y++) {
		for (int x = 0; x < 32; x++) {
			vec4 c = texture(picture, (vec2(float(x), float(y)) + 0.5) / 32.0);
			sum += lum(clamp(c.rgb, 0.0, 1.0)) + behind * (1.0 - c.a);
		}
	}
	float raw = sum / 1024.0;
	vec4 p = texture(previous, vec2(0.5));
	float floor_was = reset ? raw : p.r + p.g / 255.0;
	float shown = min(raw, floor_was + margin);
	float gain = raw > 0.0001 ? shown / raw : 1.0;
	float floor_now = clamp(min(shown, floor_was + rise * dt), 0.0, 1.0);
	float hi = floor(floor_now * 255.0) / 255.0;
	COLOR = vec4(hi, fract(floor_now * 255.0), sqrt(raw), gain);
}
