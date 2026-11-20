// Pipe organ (visualiser.json): the front of a church organ in a dim stone hall. Thirty-three pipes of spotted
// metal stand in five fields: a tall tower in the middle, one at each end, a flat of small pipes between. Each pipe
// is a part of the spectrum, the longest the lowest (the middle tower the bass, the flats the high notes): when its
// part sounds, its mouth glows and the standing wave inside shows up its length (as many nodes as its rank). Above
// the pipes, gilt carving fills each field up to its cornice; a gilt sun over the middle tower spreads its rays with
// the bass. Below, the console: two keyboards whose keys go down with their notes, stop knobs drawn as their parts
// sound, music on the desk, a candle each side. A shaft of light from a high window crosses the hall, dust in it
// glinting with the high notes. Flat, drawn field by field; no memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float voice = 0.7;
uniform float candle = 0.6;
uniform vec4 metal : source_color = vec4(0.72, 0.72, 0.68, 1.0);
uniform vec4 wood : source_color = vec4(0.3, 0.17, 0.08, 1.0);
uniform vec4 gilt : source_color = vec4(0.95, 0.72, 0.28, 1.0);
uniform vec4 tone : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform vec4 stone : source_color = vec4(0.2, 0.19, 0.2, 1.0);


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

vec3 wood_at(vec2 p) {
	float grain = vnoise(vec2(p.x * 40.0, p.y * 4.0)) * 0.6 + vnoise(vec2(p.x * 130.0, p.y * 9.0)) * 0.4;
	return wood.rgb * (0.6 + 0.7 * grain);
}

// One field of n pipes between x0 and x1 (from the middle), their feet at base: a tower (longest in the middle) or
// a flat (longest at the ends); the parts of the spectrum from p_long (the longest pipe) to p_short.
void field(vec2 p, float x0, float x1, float n, float base, float lmax, float lmin, bool is_tower, float p_long, float p_short, float px, inout vec3 col) {
	if (p.x < x0 || p.x > x1 || p.y < base - 0.005) {
		return;
	}
	float cornice = base + lmax + (is_tower ? 0.05 : 0.035);
	if (p.y > cornice) {
		return;
	}
	float w = (x1 - x0) / n;
	float k = floor((p.x - x0) / w);
	float u = ((p.x - x0) / w - k - 0.5) * 2.0 / 0.88;
	float t = (k + 0.5) / n;
	float s = is_tower ? 1.0 - abs(2.0 * t - 1.0) : pow(abs(2.0 * t - 1.0), 1.3);
	float len = mix(lmin, lmax, s);
	float pitch = mix(p_short, p_long, s) + 0.02 * t;
	float b = band(pitch) * voice;
	float top = base + len;
	float mouth = base + 0.045 + 0.2 * w;
	// Behind the pipes: the dark of the case, lit a little by the pipes that speak.
	vec3 c = wood.rgb * 0.12 + tone.rgb * 0.06 * b;
	if (p.y > top + 0.004) {
		// The pipe shade: pierced gilt carving from the pipes' tops to the cornice.
		vec2 q = vec2((p.x - x0) * 95.0, (p.y - top) * 95.0);
		float scroll = sin(q.x + 1.5 * sin(q.y * 0.9 + k)) * sin(q.y * 1.3 + 0.8 * sin(q.x * 0.7));
		float solid = smoothstep(-0.15, 0.1, scroll) * smoothstep(0.004, 0.012, p.y - top) + smoothstep(0.012, 0.004, cornice - p.y);
		c = mix(c, gilt.rgb * (0.45 + 0.4 * scroll + 0.25 * b), clamp(solid, 0.0, 1.0));
	} else if (abs(u) < 1.0) {
		float foot = clamp((p.y - base) / 0.04, 0.0, 1.0);
		float half_w = 0.35 + 0.65 * foot;
		if (abs(u) < half_w) {
			float uu = u / half_w;
			float cyl = sqrt(max(1.0 - uu * uu, 0.0));
			vec3 m = metal.rgb * (0.2 + 0.55 * pow(cyl, 0.7));
			m += metal.rgb * exp(-(uu + 0.4) * (uu + 0.4) * 18.0) * 0.55 + tone.rgb * exp(-(uu - 0.62) * (uu - 0.62) * 40.0) * 0.1;
			m *= 0.88 + 0.2 * vnoise(vec2(k * 7.0 + uu * 3.0, p.y * 55.0));
			// The mouth: a slit between two flattened lips.
			float dy = p.y - mouth;
			float lip = 1.0 - abs(dy) / (dy > 0.0 ? 0.038 : 0.02);
			if (lip > 0.0 && abs(uu) < 0.6 * lip + 0.05) {
				m = metal.rgb * (0.5 + 0.25 * lip) * (0.9 + 0.1 * cyl);
			}
			float slit = smoothstep(0.0045, 0.002, abs(dy)) * step(abs(uu), 0.55);
			m = mix(m, vec3(0.02), slit);
			// When it speaks: the mouth glows and the wave stands in the pipe.
			float v = clamp((p.y - mouth) / (top - mouth), 0.0, 1.0);
			float nodes = 1.0 + floor(fract(k * 0.37 + pitch * 3.0) * 3.0);
			float wave = 0.5 + 0.5 * cos(PI * (2.0 * nodes - 1.0) * v);
			m += tone.rgb * b * (0.25 + 0.75 * b) * (exp(-abs(dy) * 70.0) * 1.0 + step(0.0, dy) * wave * 0.3 * cyl);
			m = mix(m, vec3(0.03), smoothstep(0.007, 0.002, top - p.y) * 0.8);
			c = mix(c, m, smoothstep(half_w, half_w - px / w * 2.5, abs(u)));
		}
	}
	col = c;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;
	float x = p.x - aspect * 0.5;
	float lum = 0.8 + 0.25 * level;

	// The hall: a wall of dressed stone, a pointed arch round the organ, a tiled floor.
	vec2 blk = vec2(p.x * 9.0 + floor(p.y * 16.0) * 0.5, p.y * 16.0);
	vec3 col = stone.rgb * (0.55 + 0.25 * hash1(floor(blk)) + 0.15 * vnoise(p * 90.0));
	col *= 0.6 + 0.4 * smoothstep(0.0, 0.03, min(fract(blk.x), fract(blk.y)));
	float arch = length(vec2(abs(x) + 0.45, p.y - 0.35)) - 1.34;
	col *= 0.55 + 0.45 * smoothstep(-0.02, 0.02, arch);
	col = mix(col, stone.rgb * 1.2, smoothstep(0.012, 0.004, abs(arch - 0.02)) * 0.6);
	col *= 0.5 + 0.6 * p.y;
	if (p.y < 0.055) {
		vec2 tl = vec2(x * 14.0 / (0.4 + p.y * 6.0), 1.0 / (0.06 - p.y + 0.02));
		col = stone.rgb * (0.3 + 0.25 * mod(floor(tl.x) + floor(tl.y * 0.5), 2.0));
	}

	// The case: the lower part panelled, posts between the fields.
	if (abs(x) < 0.78 && p.y > 0.05 && p.y < 0.93) {
		float top_line = abs(x) < 0.15 ? 0.925 : (abs(x) > 0.51 ? 0.83 : 0.72);
		if (p.y < top_line) {
			vec3 wc = wood_at(p);
			if (p.y < 0.31) {
				vec2 pan = vec2(fract((x + 0.78) / 0.195), (p.y - 0.06) / 0.25);
				float inset = min(min(pan.x, 1.0 - pan.x) * 0.195, min(pan.y, 1.0 - pan.y) * 0.25);
				wc *= 0.75 + 0.25 * smoothstep(0.012, 0.02, inset);
				wc = mix(wc, gilt.rgb * 0.6, smoothstep(0.003, 0.001, abs(inset - 0.016)) * 0.7);
			}
			wc = mix(wc, gilt.rgb * 0.7, smoothstep(0.004, 0.002, abs(p.y - 0.315)));
			col = wc * (0.55 + 0.25 * p.y);
		}
	}
	field(p, aspect * 0.5 - 0.74, aspect * 0.5 - 0.52, 5.0, 0.35, 0.42, 0.35, true, 0.16, 0.27, px, col);
	field(p, aspect * 0.5 - 0.5, aspect * 0.5 - 0.16, 9.0, 0.42, 0.26, 0.16, false, 0.42, 0.68, px, col);
	field(p, aspect * 0.5 - 0.14, aspect * 0.5 + 0.14, 5.0, 0.33, 0.54, 0.45, true, 0.02, 0.13, px, col);
	field(p, aspect * 0.5 + 0.16, aspect * 0.5 + 0.5, 9.0, 0.42, 0.26, 0.16, false, 0.7, 0.95, px, col);
	field(p, aspect * 0.5 + 0.52, aspect * 0.5 + 0.74, 5.0, 0.35, 0.42, 0.35, true, 0.28, 0.4, px, col);

	// The towers' caps and finials; the gilt sun over the middle one, its rays out with the bass.
	for (int i = -1; i <= 1; i++) {
		float tx = float(i) * 0.63;
		float half_w = i == 0 ? 0.15 : 0.12;
		float cy = i == 0 ? 0.92 : 0.82;
		float cap = max(abs(x - tx) - half_w - 0.012 * smoothstep(cy, cy + 0.02, p.y), abs(p.y - cy - 0.012) - 0.012);
		col = mix(col, wood_at(p * 1.3) * (0.7 + 0.5 * smoothstep(cy, cy + 0.024, p.y)) + gilt.rgb * 0.25 * smoothstep(0.004, 0.0, abs(p.y - cy - 0.012)), smoothstep(px, -px, cap));
		float ball = length(vec2(x - tx, p.y - cy - 0.038)) - 0.013;
		if (i != 0) {
			col = mix(col, gilt.rgb * (0.5 + 0.6 * smoothstep(0.013, -0.01, length(vec2(x - tx + 0.004, p.y - cy - 0.042)))), smoothstep(px, -px, ball));
		}
	}
	vec2 sq = vec2(x, p.y - 0.965);
	float sl = length(sq);
	float rays = 0.016 + (0.012 + 0.012 * bass) * pow(abs(cos(atan(sq.y, sq.x) * 8.0)), 3.0);
	col = mix(col, gilt.rgb * (0.6 + 0.5 * smoothstep(0.03, 0.0, sl) + 0.3 * bass), smoothstep(px, -px, sl - rays));

	// The console: two keyboards, stop knobs, the music desk, a bench.
	if (abs(x) < 0.2 && p.y > 0.1 && p.y < 0.3) {
		col = wood.rgb * 0.18;
		for (int m = 0; m < 2; m++) {
			float ky = 0.175 + float(m) * 0.024;
			if (abs(x) < 0.15 && p.y > ky && p.y < ky + 0.018) {
				float kx = (x + 0.15) / 0.3 * 36.0;
				float ki = floor(kx);
				float kb = band(0.03 + 0.9 * (ki + float(m) * 0.5) / 36.0);
				float down = smoothstep(0.35, 0.75, kb * voice * 1.3);
				vec3 kc = vec3(0.86, 0.84, 0.76) * (1.0 - 0.45 * down) * smoothstep(0.0, 0.08, min(fract(kx), 1.0 - fract(kx)));
				// Black keys between the whites, but not after the third and the seventh of each seven.
				float oct = mod(floor(kx + 0.5), 7.0);
				bool has_black = oct != 0.0 && oct != 3.0;
				if (has_black && abs(fract(kx + 0.5) - 0.5) < 0.28 && p.y > ky + 0.007) {
					kc = vec3(0.05) + 0.08 * down;
				}
				col = kc * (0.7 + 0.2 * float(m));
			}
		}
		for (int sd = -1; sd <= 1; sd += 2) {
			vec2 kq = vec2((x * float(sd) - 0.165) / 0.022, (p.y - 0.165) / 0.022);
			if (kq.x > 0.0 && kq.x < 1.5 && kq.y > 0.0 && kq.y < 5.0) {
				vec2 kc = floor(kq);
				float out_k = smoothstep(0.35, 0.6, band(hash1(kc + float(sd) * 9.0)));
				float kl = length(fract(kq) - 0.5);
				col = mix(col, mix(vec3(0.5, 0.42, 0.3), vec3(0.95, 0.92, 0.8), out_k), smoothstep(0.36, 0.3, kl));
			}
		}
		if (abs(x) < 0.09 && p.y > 0.235 && p.y < 0.29) {
			col = vec3(0.8, 0.76, 0.64) * (0.8 + 0.2 * step(0.004, abs(x)));
			float staff = abs(fract((p.y - 0.235) / 0.0045) - 0.5);
			col *= 1.0 - 0.45 * smoothstep(0.2, 0.05, staff) * step(mod(floor((p.y - 0.235) / 0.0045), 6.0), 4.5);
			col *= 1.0 - 0.6 * step(0.86, hash1(floor(vec2(x * 380.0, (p.y - 0.235) / 0.0045))));
		}
		col *= lum;
	}
	float bench = max(abs(x) - 0.12, abs(p.y - 0.085) - 0.035);
	col = mix(col, wood.rgb * 0.22 * (0.7 + 0.5 * vnoise(vec2(x * 60.0, p.y * 8.0))), smoothstep(px, -px, bench));

	// A candle each side of the console.
	for (int sd = -1; sd <= 1; sd += 2) {
		vec2 cp = vec2(x - float(sd) * 0.235, p.y - 0.255);
		float waver = 0.004 * sin(vis_time * 5.0 + float(sd) * 2.0) * cp.y / 0.03;
		float flame = length(vec2((cp.x - waver) / 0.5, cp.y - 0.014 - 0.01 * smoothstep(0.0, 0.03, cp.y))) - 0.012;
		col = mix(col, vec3(0.85, 0.82, 0.7) * 0.6, smoothstep(px, -px, max(abs(cp.x) - 0.004, abs(cp.y + 0.03) - 0.03)));
		col += vec3(1.0, 0.75, 0.35) * (smoothstep(px * 2.0, -px * 2.0, flame) * 1.2 + exp(-length(cp - vec2(0.0, 0.012)) * 9.0) * 0.3) * candle;
	}

	// The window's shaft of light across the hall, dust in it.
	float beam = smoothstep(0.16, 0.0, abs((p.y - 1.05) + (p.x - 0.1) * 0.62)) * smoothstep(1.5, 0.1, p.x);
	vec2 dq = p * 150.0 + vec2(vis_time * 0.25, -vis_time * 0.18);
	float dust = step(0.97, hash1(floor(dq))) * smoothstep(0.35, 0.1, length(fract(dq) - 0.5)) * (0.5 + 0.5 * treble);
	col += vec3(1.0, 0.93, 0.8) * beam * (0.07 + 0.25 * dust);

	col *= lum;
	col *= 1.0 - 0.4 * pow(length(UV - 0.5) * 1.3, 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
