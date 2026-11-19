// Bubbles (visualiser.json): soap bubbles drifting on the breeze across a sunny garden, seen out of focus behind
// them. Each bubble is a thin film: its colours are interference (the film's thickness picks the colour, so bands of
// rainbow swirl over it as the film flows, thinner at the top where it drains); it reflects most at its edge, shows
// the sky's light as a bright window and a smaller one on its far side, and bends the garden seen through it. Each
// large bubble wobbles with its own part of the spectrum (its outline ringing in two and three lobes) and its colours
// brighten with it; small ones glint with the high notes. They go by on the music's clock (drive). No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float amount = 0.6;
uniform float wobble = 0.6;
uniform float speed = 0.5;
uniform vec4 sky : source_color = vec4(0.62, 0.82, 0.95, 1.0);
uniform vec4 garden : source_color = vec4(0.36, 0.62, 0.29, 1.0);
uniform vec4 blossom : source_color = vec4(0.98, 0.7, 0.8, 1.0);
uniform vec4 sunlight : source_color = vec4(1.0, 0.97, 0.88, 1.0);

const int BIG = 9;
const int SMALL = 14;


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float hash1(vec2 c) {
	uint h = hash_u(uint(int(c.x) + 100000) * 73856093u ^ uint(int(c.y) + 100000) * 19349663u);
	return float(h & 16777215u) / 16777215.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x), mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The garden out of focus: sky, a sunlit bloom, a hedge with blossom in it, a lawn.
vec3 garden_at(vec2 p, float aspect) {
	vec3 c = mix(sky.rgb * 1.05, sky.rgb * 0.8, smoothstep(0.6, 1.0, p.y));
	float hedge_top = 0.5 + 0.08 * vnoise(vec2(p.x * 2.5, 1.0)) + 0.04 * sin(p.x * 3.0);
	float in_hedge = smoothstep(hedge_top + 0.06, hedge_top - 0.06, p.y);
	float leaves = vnoise(p * 7.0) * 0.6 + vnoise(p * 2.5 + 9.0) * 0.4;
	vec3 hc = garden.rgb * (0.55 + 0.6 * leaves);
	float bloom = smoothstep(0.66, 0.88, vnoise(p * 9.0 + 31.0) * 0.6 + vnoise(p * 23.0 + 7.0) * 0.4) * smoothstep(0.15, 0.35, p.y) * leaves;
	hc = mix(hc, blossom.rgb * 0.95, bloom * 0.65);
	c = mix(c, hc, in_hedge);
	float lawn = smoothstep(0.24, 0.12, p.y);
	c = mix(c, garden.rgb * vec3(1.15, 1.2, 0.85) * (0.8 + 0.25 * vnoise(p * vec2(3.0, 9.0))), lawn);
	// Sunlight from the top left.
	c += sunlight.rgb * 0.35 * exp(-length(p - vec2(0.15, 1.05)) * 2.2);
	return c;
}

// Big bubble i: centre and radius.
vec3 bubble(int i, float aspect) {
	float fi = float(i);
	float R = 0.05 + 0.09 * fract(0.31 + fi * 0.618);
	float x = -R - 0.05 + fract(0.17 + fi * 0.382 + drive * speed * (0.035 + 0.02 * fract(fi * 0.73))) * (aspect + 2.0 * R + 0.1);
	float y = 0.2 + 0.65 * fract(0.53 + fi * 0.4142) + 0.05 * sin(vis_time * 0.35 + fi * 1.9) + 0.02 * sin(x * 3.0 + fi);
	return vec3(x, y, R);
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;

	// Find what is in front here: the big bubbles first (nearest wins), each film worked out for this pixel.
	vec2 look = p;
	vec3 film = vec3(0.0);
	float film_a = 0.0;
	vec3 glint = vec3(0.0);
	int count = int(float(BIG) * (0.35 + 0.65 * amount) + 0.5);
	for (int i = 0; i < BIG; i++) {
		if (i >= count) {
			break;
		}
		vec3 bb = bubble(i, aspect);
		vec2 q = p - bb.xy;
		float R = bb.z;
		if (dot(q, q) > R * R * 1.4) {
			continue;
		}
		float fi = float(i);
		float b = band(0.05 + fi / float(BIG - 1) * 0.85);
		float th = atan(q.y, q.x);
		float wob = (0.008 + 0.06 * wobble * b) * (sin(2.0 * th + vis_time * 2.6 + fi) * 0.6 + sin(3.0 * th - vis_time * 3.7 + fi * 2.0) * 0.4);
		float Rt = R * (1.0 + wob);
		float rr = length(q) / Rt;
		if (rr > 1.0 + px / Rt) {
			continue;
		}
		vec2 n2 = q / Rt;
		float z = sqrt(max(1.0 - min(rr * rr, 1.0), 0.0));
		float edge = smoothstep(1.0 + px / Rt, 1.0 - px / Rt, rr);
		// Film thickness: drained thin at the top, swirling.
		vec2 fq = n2 * 1.6 + vec2(fi * 7.0, 0.0);
		float sw = vnoise(fq + vec2(vis_time * 0.12, -vis_time * 0.18)) * 0.7 + vnoise(fq * 2.2 - vec2(vis_time * 0.2, 0.0)) * 0.3;
		float thick = 0.6 - 0.35 * n2.y + 0.9 * sw;
		float phase = thick / max(0.35 + 0.65 * z, 0.35);
		vec3 rainbow = 0.5 + 0.5 * cos(TAU * (phase * 2.6 + vec3(0.0, 0.33, 0.67)));
		rainbow = pow(rainbow, vec3(1.6)) * 1.35;
		rainbow = mix(vec3(0.9), rainbow, smoothstep(0.15, 0.45, thick));
		float fres = 0.06 + 0.94 * pow(1.0 - z, 4.0);
		vec3 fc = rainbow * (0.55 + 0.6 * fres) * (0.75 + 0.6 * b);
		float fa = clamp(0.3 + 0.7 * fres, 0.0, 1.0) * edge;
		// The sky as a window high on the near side, and smaller on the far side.
		vec2 w1 = (n2 - vec2(-0.42, 0.42)) / vec2(0.2, 0.15);
		float win1 = smoothstep(1.0, 0.45, length(w1 * vec2(1.0, 1.2))) * (0.75 + 0.25 * smoothstep(0.08, 0.2, min(abs(w1.x), abs(w1.y))));
		vec2 w2 = (n2 - vec2(0.45, -0.5)) / vec2(0.1, 0.07);
		float win2 = smoothstep(1.0, 0.5, length(w2));
		vec3 g = sunlight.rgb * (win1 * 0.7 + win2 * 0.4) * edge;
		// Over what was found before (nearer bubbles have higher numbers).
		film = mix(film, fc, fa);
		film_a = max(film_a, fa);
		glint = max(glint, g);
		look = mix(look, p - q * 0.18 * z, edge);
	}
	vec3 col = garden_at(look, aspect);
	col = col * (1.0 - film_a * 0.45) + film * film_a * 0.75;
	col += glint;

	// Small bubbles: a rim and a glint.
	for (int i = 0; i < SMALL; i++) {
		float fi = float(i);
		if (fi >= float(SMALL) * amount + 1.0) {
			break;
		}
		float r = 0.008 + 0.014 * fract(fi * 0.77 + 0.2);
		float x = -0.05 + fract(fi * 0.29 + drive * speed * (0.05 + 0.03 * fract(fi * 0.41))) * (aspect + 0.1);
		float y = fract(0.1 + fi * 0.618 + vis_time * 0.008 * (1.0 + fract(fi * 0.3))) * 1.1 - 0.05 + 0.02 * sin(vis_time * 0.5 + fi);
		vec2 q = p - vec2(x, y);
		float l = length(q);
		if (l > r + 2.0 * px) {
			continue;
		}
		float rim = smoothstep(r * 0.55, r, l) * smoothstep(r + px, r - px, l);
		vec3 rc = 0.5 + 0.5 * cos(TAU * (fi * 0.37 + l / r * 0.6 + vec3(0.0, 0.33, 0.67)));
		col = mix(col, col * 0.9 + rc * 0.35, rim * 0.8);
		col += sunlight.rgb * smoothstep(0.45 * r, 0.1 * r, length(q - vec2(-0.4, 0.4) * r)) * (0.6 + 0.6 * treble);
	}

	col *= 1.0 - 0.25 * pow(length(UV - 0.5) * 1.2, 2.0);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
