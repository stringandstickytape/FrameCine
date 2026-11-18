// Ink (visualiser.json, "feedback": true): reads its own last frame (previous) and moves it along a slowly turning
// flow (the curl of a drifting noise, a gentle whirl about the middle, and a push outwards on each beat), so what is
// poured drifts and curls for seconds. Six pourers circle the card, each pouring its colour as loud as its sixth of
// the spectrum (low notes the first); each beat blooms a drop somewhere new. Everything fades back to the water.
// 8 bits a channel: the result is dithered by half a step, so slow motion and slow fades do not stall on the steps.
// Paused (vis_dt 0), the picture is copied exactly.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float swirl = 0.5;
uniform float fade = 0.25;
uniform float pour = 0.5;
uniform bool use_cover = true;
uniform vec4 ink_a : source_color = vec4(0.18, 0.71, 0.84, 1.0);
uniform vec4 ink_b : source_color = vec4(0.84, 0.22, 0.44, 1.0);
uniform vec4 ink_c : source_color = vec4(0.94, 0.71, 0.23, 1.0);
uniform vec4 water : source_color = vec4(0.02, 0.03, 0.05, 1.0);

uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float hash2(vec2 c, uint salt) {
	uint h = hash_u(uint(int(c.x) + 100000) * 73856093u ^ uint(int(c.y) + 100000) * 19349663u ^ salt * 83492791u);
	return float(h & 16777215u) / 16777215.0;
}

float noise(vec2 p, uint salt) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i, salt), hash2(i + vec2(1.0, 0.0), salt), u.x),
			mix(hash2(i + vec2(0.0, 1.0), salt), hash2(i + vec2(1.0, 1.0), salt), u.x), u.y);
}

// Two octaves.
float field(vec2 p) {
	return noise(p, 1u) + 0.5 * noise(p * 2.1 + 17.0, 2u);
}

// A flow with no sources or sinks: the curl of the field.
vec2 curl(vec2 p) {
	float e = 0.02;
	float dx = field(p + vec2(e, 0.0)) - field(p - vec2(e, 0.0));
	float dy = field(p + vec2(0.0, e)) - field(p - vec2(0.0, e));
	return vec2(dy, -dx) / (2.0 * e);
}

vec3 ink_colour(int i) {
	if (use_cover && has_cover > 0.5) {
		float fi = float(i);
		vec3 c = texture(cover, vec2(fract(0.17 + fi * 0.29), fract(0.31 + fi * 0.43))).rgb;
		float g = dot(c, vec3(0.333));
		c = clamp(mix(vec3(g), c, 1.7), 0.0, 1.0);
		return c / max(max(c.r, max(c.g, c.b)), 0.1) * 0.85;
	}
	int k = i - (i / 3) * 3;
	return k == 0 ? ink_a.rgb : k == 1 ? ink_b.rgb : ink_c.rgb;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 A = vec2(aspect, 1.0);
	vec2 p = UV * A;
	if (fresh > 0.5) {
		COLOR = vec4(water.rgb, 1.0);
	} else if (vis_dt <= 0.0) {
		COLOR = vec4(texture(previous, UV).rgb, 1.0);
	} else {
		// Where this pixel's water was a moment ago.
		vec2 c = p - 0.5 * A;
		float t = drive * 0.06;
		vec2 v = curl(p * 1.3 + vec2(t, -t * 0.7)) * (0.03 + 0.12 * swirl * (0.4 + bass));
		v += vec2(-c.y, c.x) * 0.1 * swirl;
		v += c * beat * 0.3;
		vec2 src = p - v * vis_dt;
		vec3 col = texture(previous, src / A).rgb;
		// Back towards the water.
		col = mix(col, water.rgb, clamp(fade * vis_dt, 0.0, 1.0));
		// The pourers.
		for (int i = 0; i < 6; i++) {
			float fi = float(i);
			float dir = mod(fi, 2.0) < 0.5 ? 1.0 : -1.0;
			float th = drive * 0.22 * (1.0 + 0.15 * fi) * dir + fi * 1.047;
			float r = 0.24 + 0.1 * sin(drive * 0.09 + fi * 1.7);
			vec2 e = 0.5 * A + r * vec2(cos(th) * 1.5, sin(th));
			float s = band_between(fi / 6.0, (fi + 1.0) / 6.0);
			s = s * s * (3.0 - 2.0 * s);
			float rad = 0.025 + 0.05 * s;
			vec2 d = p - e;
			float amount = pour * s * 10.0 * vis_dt * exp(-dot(d, d) / (rad * rad));
			col = mix(col, ink_colour(i), clamp(amount, 0.0, 1.0));
		}
		// A drop on each beat, somewhere new.
		vec2 at = 0.5 * A + (vec2(hash2(vec2(beats, 0.0), 5u), hash2(vec2(beats, 1.0), 5u)) - 0.5) * vec2(aspect * 0.7, 0.6);
		vec2 d = p - at;
		float drop = beat * pour * 7.0 * vis_dt * exp(-dot(d, d) / (0.07 * 0.07));
		col = mix(col, ink_colour(int(mod(beats, 6.0))), clamp(drop, 0.0, 1.0));
		// Dither half a step, so slow changes survive the 8 bits.
		float n = hash2(FRAGCOORD.xy, uint(int(fract(vis_time * 0.37) * 65536.0)));
		col += (n - 0.5) / 255.0;
		COLOR = vec4(col, 1.0);
	}
}
