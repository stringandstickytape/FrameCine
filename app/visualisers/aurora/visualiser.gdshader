// Aurora (visualiser.json): curtains of colour across the whole card, behind the words. Each curtain is a band of
// soft vertical streaks along a slowly waving line; the bass lifts them, the treble makes the streaks shimmer, and
// with use_cover the colours come from the cover (its left and right halves).
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float speed = 0.5;
uniform float brightness = 0.6;
uniform vec4 colour_a : source_color = vec4(0.18, 0.84, 0.63, 1.0);
uniform vec4 colour_b : source_color = vec4(0.42, 0.36, 1.0, 1.0);
uniform bool use_cover = true;

float hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

// The cover's colour down the column at x, made brighter and more saturated than its average so it glows.
vec3 cover_colour(float x) {
	vec3 s = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		for (int j = 0; j < 4; j++) {
			s += texture(cover, vec2(x + (float(j) - 1.5) * 0.06, (float(i) + 0.5) / 4.0)).rgb;
		}
	}
	vec3 c = s / 16.0;
	vec3 grey = vec3(dot(c, vec3(0.333)));
	c = clamp(mix(grey, c, 1.6), 0.0, 1.0);
	return c / max(max(c.r, max(c.g, c.b)), 0.05) * 0.9;
}

void fragment() {
	float t = vis_time * speed;
	float px = UV.x * size.x / size.y;
	vec3 ca = colour_a.rgb;
	vec3 cb = colour_b.rgb;
	if (use_cover && has_cover > 0.5) {
		ca = cover_colour(0.25);
		cb = cover_colour(0.75);
	}
	vec3 sum = vec3(0.0);
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		// The curtain's line: waving along x, lifted by the bass.
		float y = 0.62 - 0.12 * fk - 0.18 * bass + 0.08 * sin(px * (1.3 + fk * 0.4) + t * (0.7 + fk * 0.3))
				+ 0.05 * noise(px * 3.0 + t + fk * 10.0);
		float dy = UV.y - y;
		// Bright at the line, fading far upward and fast downward.
		float body = dy < 0.0 ? exp(dy * (6.0 - 2.0 * mid)) : exp(-dy * 30.0);
		// Vertical streaks, shimmering faster with the treble.
		float streak = 0.55 + 0.45 * noise(px * 40.0 + fk * 7.0 + t * (1.0 + 4.0 * treble));
		float here = band(fract(UV.x * 0.5 + fk * 0.33));
		vec3 c = mix(ca, cb, 0.5 + 0.5 * sin(px * 1.7 + fk * 2.1 + t * 0.4));
		sum += c * body * streak * (0.35 + 0.65 * here);
	}
	COLOR = vec4(vec3(0.02, 0.02, 0.04) + sum * brightness * (0.6 + 0.4 * level), 1.0);
}
