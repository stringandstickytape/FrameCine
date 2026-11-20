// Starlings (visualiser.json): a murmuration over an estuary at sunset. Thousands of starlings make one shape that
// swells, folds and pours across the sky: the flock is six bodies of birds pulled about by the music's clock (drive),
// each swelling with its own part of the spectrum; folds in it move with the middle notes; dark waves sweep through it
// (where the birds turn edge-on), sent faster by the beat; stragglers scatter with the high notes. The birds are drawn
// one per cell from three layers turning round the flock's middle at different speeds, so they stream past each
// other; where the flock is thick they merge into shade. Below: mudflats and channels holding the sky and the flock,
// a ruined pier on its stilts, reeds in front that sway with the bass; cirrus lit pink, the sun on the horizon.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float flock = 0.6;
uniform float swirl = 0.5;
uniform float waves = 0.6;
uniform vec4 high : source_color = vec4(0.22, 0.24, 0.42, 1.0);
uniform vec4 low : source_color = vec4(1.0, 0.62, 0.36, 1.0);
uniform vec4 sun : source_color = vec4(1.0, 0.92, 0.7, 1.0);
uniform vec4 land : source_color = vec4(0.08, 0.07, 0.1, 1.0);

const float HORIZON = 0.24;


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

vec3 hash3(vec2 c) {
	uint h = hash_u(uint(int(c.x) + 100000) * 73856093u ^ uint(int(c.y) + 100000) * 19349663u);
	uint h2 = hash_u(h);
	return vec3(float(h & 65535u), float(h >> 16u), float(h2 & 65535u)) / 65535.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x), mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// The flock's middle.
vec2 flock_centre(float aspect) {
	return vec2(aspect * 0.52 + 0.28 * sin(drive * 0.045), 0.6 + 0.07 * sin(drive * 0.061 + 1.0));
}

// How thick the flock is at p, 0..1: six bodies of birds (each swelling with its part of the spectrum) summed as a
// field, folded by noise.
float density(vec2 p, vec2 c, float aspect) {
	float t = drive;
	vec2 w = vec2(vnoise(p * 3.2 + vec2(t * 0.05, 0.0)), vnoise(p * 3.2 + vec2(4.0, t * 0.04))) - 0.5;
	p += w * (0.06 + 0.07 * mid);
	float f = 0.0;
	for (int i = 0; i < 6; i++) {
		float fi = float(i);
		vec2 bp = c + vec2(0.17 * sin(t * (0.09 + 0.02 * fi) + fi * 2.1), 0.075 * sin(t * (0.11 + 0.015 * fi) + fi * 1.3));
		float b = band(0.04 + fi / 5.0 * 0.86);
		float r = (0.05 + 0.045 * flock) * (0.75 + 0.7 * b);
		vec2 d = rot(p - bp, 0.5 * sin(t * 0.05 + fi * 1.7)) / vec2(1.4 + 0.8 * sin(t * 0.07 + fi), 0.55);
		f += r * r / (dot(d, d) + 0.002);
	}
	return smoothstep(0.65, 2.0, f) * (0.75 + 0.25 * vnoise(p * 9.0 + vec2(t * 0.1, 0.0)));
}

// The sky: dusk overhead to the glow at the horizon, the sun on it, cirrus lit from below.
vec3 sky_at(vec2 p, float aspect, vec2 S) {
	float y = max(p.y - HORIZON, 0.0);
	vec3 c = mix(low.rgb, mix(low.rgb, high.rgb, 0.5) * vec3(1.0, 0.85, 0.95), smoothstep(0.0, 0.25, y));
	c = mix(c, high.rgb, smoothstep(0.15, 0.7, y));
	float sl = length((p - S) * vec2(0.6, 1.0));
	c += sun.rgb * (0.5 * exp(-sl * 9.0) + 0.25 * exp(-sl * 2.5)) * (0.8 + 0.3 * level);
	float cir = vnoise(vec2(p.x * 2.2 + drive * 0.006, p.y * 14.0)) * 0.6 + vnoise(vec2(p.x * 5.0 + drive * 0.01, p.y * 30.0)) * 0.4;
	cir = smoothstep(0.55, 0.85, cir) * smoothstep(0.35, 0.55, p.y) * smoothstep(0.98, 0.75, p.y);
	vec3 lit = mix(low.rgb * 1.15, vec3(1.0, 0.75, 0.8), 0.35) * (1.0 - smoothstep(0.4, 0.9, p.y) * 0.5);
	return mix(c, lit, cir * 0.55);
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;
	vec2 S = vec2(aspect * 0.28, HORIZON + 0.012);
	vec2 c = flock_centre(aspect);
	vec3 bird = land.rgb * 0.75;
	vec3 col;

	if (p.y >= HORIZON) {
		col = sky_at(p, aspect, S);
		// The sun's disc, half set.
		col = mix(col, sun.rgb * 1.1, smoothstep(0.034 + px, 0.034 - px, length(p - S)));

		// The flock.
		float D = density(p, c, aspect);
		vec2 rel = p - c;
		float wave = 0.5 + 0.5 * sin(dot(rel, normalize(vec2(1.0, 0.45))) * 22.0 + 1.5 * sin(rel.y * 14.0 + drive * 0.3) - drive * (2.0 + 1.5 * waves) - 2.0 * beat);
		wave = mix(0.5, wave, waves);
		float shade = D * D * (0.25 + 0.7 * wave);
		col = mix(col, bird, clamp(shade, 0.0, 0.92));
		// The birds, one per cell from three layers turning round the middle at their own speeds.
		float straggle = 0.04 + 0.08 * treble;
		float reach = max(D, straggle * smoothstep(0.6, 0.0, length(rel)));
		if (reach > 0.01) {
			for (int l = 0; l < 3; l++) {
				float fl = float(l);
				float cs = 0.0062 + 0.0018 * fl;
				float spin = drive * swirl * (0.06 + 0.035 * fl) * (l == 1 ? -1.0 : 1.0);
				vec2 g = rot(rel, spin) / cs + vec2(fl * 17.3, fl * 5.1);
				vec2 cell = floor(g);
				vec3 h = hash3(cell + vec2(fl * 101.0, 7.0));
				float present = smoothstep(h.x, h.x + 0.15, reach * (1.25 - 0.2 * fl));
				if (present > 0.0) {
					vec2 bpos = cell + 0.5 + 0.3 * vec2(sin(vis_time * (0.6 + h.y) + h.z * 20.0), cos(vis_time * (0.5 + h.z) + h.y * 20.0));
					vec2 d = (g - bpos) * cs;
					// A small dash along the way the layer streams, its wings a slight V.
					vec2 dir = normalize(vec2(-rel.y, rel.x) * (l == 1 ? -1.0 : 1.0) + 0.001);
					vec2 bl = vec2(dot(d, dir), dot(d, vec2(-dir.y, dir.x)));
					float flap = 0.35 * sin(vis_time * 9.0 + h.y * 30.0);
					float wing = abs(bl.y + abs(bl.x) * flap) - 0.45 * px;
					float bd = max(wing, abs(bl.x) - (1.1 + 0.8 * h.z) * px);
					col = mix(col, bird, smoothstep(px * 0.8, -px * 0.4, bd) * present * 0.85);
				}
			}
		}

		// The pier on the horizon: a deck on stilts running out from the right, a pavilion's ribs at its end.
		if (p.y < HORIZON + 0.08 && p.x > aspect * 0.62) {
			float deck = abs(p.y - (HORIZON + 0.032)) - 0.0035;
			deck = max(deck, aspect * 0.66 - p.x);
			float stilts = max(abs(fract(p.x / 0.011) - 0.5) * 0.011 - 0.0011, p.y - HORIZON - 0.03);
			stilts = max(stilts, aspect * 0.66 - p.x);
			vec2 pc = p - vec2(aspect * 0.71, HORIZON + 0.035);
			float dome = abs(length(pc * vec2(1.0, 1.4)) - 0.032) - 0.0018;
			dome = max(dome, -pc.y);
			float ribs = max(abs(fract(atan(pc.y, pc.x) / PI * 6.0) - 0.5) * 0.02 - 0.001, length(pc * vec2(1.0, 1.4)) - 0.032);
			ribs = max(ribs, -pc.y);
			float gaps = step(0.6, hash1(vec2(floor(p.x / 0.011), 3.0)));
			float pier = min(min(deck, mix(stilts, 1.0, gaps * step(aspect * 0.85, p.x))), min(dome, ribs));
			col = mix(col, land.rgb * 1.1, smoothstep(px, -px, pier));
		}
		// The far shore: low and dark.
		float shore = HORIZON + 0.008 + 0.012 * vnoise(vec2(p.x * 5.0, 1.0)) * smoothstep(aspect * 0.6, 0.1, p.x);
		col = mix(col, land.rgb * 1.2 + low.rgb * 0.04, smoothstep(px, -px, p.y - shore));
	} else {
		// The estuary: mud and channels holding the sky (and the flock in it), rippled; reeds in front.
		float yd = HORIZON - p.y;
		float Z = 0.04 / max(yd, 0.001);
		float X = (p.x - aspect * 0.5) * Z;
		float chan = vnoise(vec2(X * 1.2, Z * 0.5)) * 0.7 + vnoise(vec2(X * 3.0, Z * 1.5)) * 0.3;
		float water = smoothstep(0.38, 0.44, chan + 0.15 * smoothstep(0.1, 0.0, yd));
		vec2 m = vec2(p.x + (vnoise(vec2(p.x * 8.0, p.y * 90.0 + vis_time * 0.6)) - 0.5) * 0.012 * smoothstep(0.0, 0.2, yd), HORIZON + yd);
		vec3 refl = sky_at(m, aspect, S) * 0.75;
		float Dm = density(m, c, aspect);
		refl = mix(refl, bird, Dm * Dm * 0.6);
		refl += sun.rgb * 0.35 * smoothstep(0.06, 0.0, abs(p.x - S.x) - yd * 0.15) * (0.5 + 0.5 * vnoise(vec2(p.x * 60.0, p.y * 200.0 + vis_time * 0.5))) * exp(-yd * 6.0);
		vec3 mud = mix(land.rgb * 1.6, low.rgb * 0.25, 0.3) * (0.7 + 0.3 * vnoise(vec2(X * 10.0, Z * 4.0)));
		mud += low.rgb * 0.12 * exp(-yd * 10.0);
		col = mix(mud, refl, water);
	}

	// Reeds along the front, their heads swaying with the bass.
	if (p.y < 0.3) {
		float rw = 0.0055;
		float cell = floor(p.x / rw);
		for (int k = -1; k <= 1; k++) {
			float ck = cell + float(k);
			float h = hash1(vec2(ck, 13.0));
			float tall = 0.09 + 0.17 * h * h;
			float x0 = (ck + 0.5) * rw;
			float t = clamp(p.y / tall, 0.0, 1.0);
			float bend = (0.012 + 0.02 * bass) * sin(vis_time * 0.8 + ck * 0.35 + h * 3.0) * t * t * (0.5 + 0.5 * h);
			float stem = abs(p.x - x0 - bend) - 0.0011 * (1.0 - 0.6 * t);
			stem = max(stem, p.y - tall);
			vec2 hq = vec2(p.x - x0 - bend * 1.1, p.y - tall - 0.012);
			float head = length(hq * vec2(1.0, 0.35)) - 0.0028;
			head = step(0.55, h) < 0.5 ? 1.0 : head;
			col = mix(col, land.rgb * 0.8, smoothstep(px, -px, min(stem, head)));
		}
	}

	col *= 1.0 - 0.28 * pow(length(UV - 0.5) * 1.25, 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
