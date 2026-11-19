// Rain (visualiser.json): a city at night seen through a wet window. Out of focus behind the glass the lights are
// discs: windows in the towers, street lamps, cars passing both ways (white headlights one way, red tail lights the
// other), a neon sign. The lights stand in for the spectrum, low notes to the left and high to the right, each
// brightening with its band; the neon follows the middle, and the cars run on the music's clock (drive). On the
// glass, which is misted, beads of water sit still and larger drops run down in wandering paths, wiping a clear
// trail and leaving beads behind. Each drop is a small lens: inside it the city is sharp, upside down. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float rain = 0.6;
uniform float mist = 0.5;
uniform float speed = 0.5;
uniform vec4 city_a : source_color = vec4(1.0, 0.63, 0.25, 1.0);
uniform vec4 city_b : source_color = vec4(0.3, 0.65, 1.0, 1.0);
uniform vec4 neon : source_color = vec4(1.0, 0.24, 0.55, 1.0);
uniform vec4 sky : source_color = vec4(0.05, 0.07, 0.13, 1.0);

const float COLUMN = 0.075;


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

vec3 hash3(vec2 cell, float salt) {
	uint h = hash_u(uint(int(cell.x) + 100000) * 73856093u ^ uint(int(cell.y) + 100000) * 19349663u
			^ uint(int(salt)) * 83492791u);
	uint h2 = hash_u(h);
	uint h3 = hash_u(h2);
	return vec3(float(h & 65535u), float(h2 & 65535u), float(h3 & 65535u)) / 65535.0;
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash3(i, 3.0).x, hash3(i + vec2(1.0, 0.0), 3.0).x, f.x),
			mix(hash3(i + vec2(0.0, 1.0), 3.0).x, hash3(i + vec2(1.0, 1.0), 3.0).x, f.x), f.y);
}

// A disc of light of radius r (a light out of focus): a flat disc with a slightly brighter rim.
float bokeh(vec2 d, float r, float aa) {
	float l = length(d);
	return smoothstep(r + aa, r - aa, l) * (0.75 + 0.35 * smoothstep(r * 0.5, r, l));
}

// The city behind the glass at p, its lights as discs blur wide (0 sharp).
vec3 city(vec2 p, float blur, float aspect) {
	float aa = blur * 0.15 + 0.0015;
	vec3 c = mix(city_a.rgb * 0.22 + sky.rgb, sky.rgb * 0.7, smoothstep(0.1, 0.85, p.y));
	// Towers, two rows, soft-edged.
	for (int l = 0; l < 2; l++) {
		float fl = float(l);
		float w = fl == 0.0 ? 0.16 : 0.1;
		float cx = floor(p.x / w + fl * 0.5);
		vec3 h = hash3(vec2(cx, fl), 51.0);
		float top = (fl == 0.0 ? 0.55 : 0.42) + 0.33 * h.x;
		float fx = fract(p.x / w + fl * 0.5);
		float edge = min(fx, 1.0 - fx) * w - 0.008;
		float body = smoothstep(-aa * 3.0, aa * 3.0, edge) * smoothstep(aa * 3.0, -aa * 3.0, p.y - top);
		vec3 tc = sky.rgb * (fl == 0.0 ? 0.55 : 0.35) + mix(city_a.rgb, city_b.rgb, h.y) * 0.035;
		c = mix(c, tc, body);
	}
	// Lit windows in the towers.
	float wc = 0.045;
	vec2 wq = p / wc;
	vec2 wi = floor(wq);
	vec3 wh = hash3(wi, 53.0);
	if (wh.x < 0.32) {
		vec2 o = (wh.yz - 0.5) * 0.4;
		float r = (0.004 + blur * (0.6 + 0.6 * wh.z)) / wc;
		float x = clamp(wi.x * wc / aspect, 0.0, 1.0);
		float b = band(0.03 + x * 0.9);
		vec3 lc = mix(city_a.rgb, city_b.rgb, step(0.6, wh.y));
		float e = 0.0005 / (0.0005 + blur * blur * 6.0);
		c += lc * bokeh(fract(wq) - 0.5 - o, min(r, 0.3), aa / wc) * (0.25 + 1.2 * b) * mix(0.35, 1.0, e) * smoothstep(0.92, 0.6, p.y) * smoothstep(0.27, 0.36, p.y);
	}
	// Street lamps.
	float lx = fract(p.x / 0.32 + 0.3) - 0.5;
	float lamp_r = 0.006 + blur * 1.6;
	c += city_a.rgb * bokeh(vec2(lx * 0.32, p.y - 0.36), lamp_r, aa) * 0.55 * (0.0012 / (0.0012 + blur * blur * 8.0) * 0.7 + 0.3);
	// Cars: headlights going right, tail lights going left.
	if (p.y > 0.14 && p.y < 0.3) {
		for (int lane = 0; lane < 2; lane++) {
			float fl = float(lane);
			float ly = fl == 0.0 ? 0.22 : 0.255;
			float dir = fl == 0.0 ? 1.0 : -1.0;
			float lr = 0.004 + blur * (fl == 0.0 ? 1.2 : 1.0);
			vec3 lc = fl == 0.0 ? vec3(1.0, 0.95, 0.85) : vec3(1.0, 0.12, 0.08);
			float span = aspect + 0.4;
			for (int k = 0; k < 6; k++) {
				vec3 h = hash3(vec2(float(k), fl), 57.0);
				float x = fract(h.x + dir * drive * speed * (0.05 + 0.03 * h.y)) * span - 0.2;
				vec2 d = p - vec2(x, ly + (h.z - 0.5) * 0.008);
				if (abs(d.x) > 0.06 + lr || abs(d.y) > lr + 0.01) {
					continue;
				}
				float pair = bokeh(d - vec2(0.018, 0.0), lr, aa) + bokeh(d + vec2(0.018, 0.0), lr, aa);
				c += lc * pair * (fl == 0.0 ? 0.55 : 0.5) * (0.0012 / (0.0012 + blur * blur * 8.0) * 0.6 + 0.4);
			}
		}
	}
	// A neon sign on the near tower: a bar and a ring, following the middle.
	vec2 nq = p - vec2(aspect * 0.78, 0.6);
	float nd = min(abs(length(nq * vec2(1.0, 1.3)) - 0.045), max(abs(nq.x - 0.11) - 0.05, abs(nq.y) - 0.004));
	float ng = exp(-max(nd, 0.0) / (0.004 + blur * 0.9)) * (0.4 + 0.9 * mid);
	c += neon.rgb * ng * 0.7;
	// The wet street, catching the lights.
	c += city_a.rgb * 0.06 * smoothstep(0.2, 0.0, p.y) * (0.6 + 0.4 * noise2(vec2(p.x * 8.0, 2.0)));
	return c;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;
	float far_blur = 0.012 + 0.03 * mist;

	vec2 look = p;
	float lens = 0.0;
	float clear = 0.0;
	float rim = 0.0;
	vec2 spec = vec2(0.0);

	// Beads that sit still: two sizes; each grows, stays and dries away on its own slow clock.
	for (int l = 0; l < 2; l++) {
		float fl = float(l);
		float cell = fl == 0.0 ? 0.03 : 0.014;
		vec2 q = p / cell;
		vec2 ci = floor(q);
		vec3 h = hash3(ci, 61.0 + fl);
		if (h.x < rain * (fl == 0.0 ? 0.55 : 0.8)) {
			float life = fract(vis_time * 0.02 * (0.5 + h.y) + h.z);
			float grow = smoothstep(0.0, 0.08, life) * smoothstep(1.0, 0.85, life);
			float r = (0.2 + 0.2 * h.y) * grow;
			vec2 o = (vec2(h.z, fract(h.y * 7.0)) - 0.5) * (0.9 - 2.0 * r);
			vec2 d = (fract(q) - 0.5 - o) / max(r, 1e-3);
			float l2 = dot(d, d);
			if (l2 < 1.0) {
				float aa = px / (cell * r);
				float m = smoothstep(1.0, 1.0 - aa * 2.0, sqrt(l2));
				look = mix(look, p - d * (0.02 + cell * r * 3.0), m);
				lens = max(lens, m);
				rim = max(rim, m * smoothstep(0.6, 1.0, sqrt(l2)));
				spec = d;
			}
		}
	}
	// Drops running down, one to a column, each with its clear trail and beads left behind.
	float colx = floor(p.x / COLUMN);
	vec3 ch = hash3(vec2(colx, 0.0), 67.0);
	if (ch.x < 0.35 + 0.6 * rain) {
		float u = fract(drive * speed * (0.05 + 0.08 * ch.y) + ch.z);
		float yd = 1.15 - 1.4 * (u + 0.025 * sin(u * 30.0 + ch.y * 9.0));
		float xc = (colx + 0.5) * COLUMN;
		float wig = 0.012;
		float xd = xc + wig * sin(yd * 11.0 + ch.y * 20.0) + 0.006 * sin(yd * 37.0 + ch.z * 9.0);
		float xp = xc + wig * sin(p.y * 11.0 + ch.y * 20.0) + 0.006 * sin(p.y * 37.0 + ch.z * 9.0);
		float r = 0.011 + 0.008 * ch.y;
		// The trail: clear glass above the drop, narrowing as it dries.
		float above = p.y - yd;
		if (above > 0.0) {
			float tw = r * 0.55 * exp(-above * 1.5);
			clear = max(clear, smoothstep(tw + px, tw - px, abs(p.x - xp)));
			// Beads left in the trail.
			float bc = 0.022;
			float bi = floor(p.y / bc);
			vec3 bh = hash3(vec2(colx, bi), 71.0);
			if (bh.x < 0.55) {
				float br = r * (0.15 + 0.25 * bh.y) * exp(-above * 0.8);
				vec2 bd = vec2(p.x - xp - (bh.z - 0.5) * r * 0.5, p.y - (bi + 0.5) * bc) / max(br, 1e-4);
				float bl = length(bd);
				if (bl < 1.0) {
					float m = smoothstep(1.0, 1.0 - px / br * 2.0, bl);
					look = mix(look, p - bd * (0.015 + br * 3.0), m);
					lens = max(lens, m);
					rim = max(rim, m * smoothstep(0.6, 1.0, bl));
					spec = bd;
				}
			}
		}
		// The drop: a little flattened on top, rounder below.
		vec2 dd = vec2(p.x - xd, p.y - yd);
		dd.y *= dd.y > 0.0 ? 0.75 : 1.0;
		vec2 d = dd / r;
		float dl = length(d);
		if (dl < 1.0) {
			float m = smoothstep(1.0, 1.0 - px / r * 2.0, dl);
			look = mix(look, p - d * (0.04 + r * 3.0) * vec2(1.0, 1.2), m);
			lens = max(lens, m);
			rim = max(rim, m * smoothstep(0.55, 1.0, dl));
			spec = d;
		}
	}

	// Through a drop the city is sharp; through the mist it is soft and pale.
	float blur = mix(far_blur, 0.0015, lens);
	vec3 col = city(look, blur, aspect);
	col *= 1.0 + 0.5 * lens;
	float fog = mist * (1.0 - clear) * (1.0 - 0.55 * lens) * (0.75 + 0.25 * noise2(p * 6.0));
	vec3 veil = mix(sky.rgb * 2.2 + city_a.rgb * 0.06, city_a.rgb * 0.12 + sky.rgb, smoothstep(0.9, 0.1, p.y));
	col = mix(col, col * 0.7 + veil, fog * 0.6);
	col += veil * 0.25 * mist * clear;
	// A drop's edge is dark, with a bright point where it catches a light.
	col *= 1.0 - 0.4 * rim;
	col += vec3(0.9, 0.95, 1.0) * 0.3 * lens * exp(-dot(spec - vec2(-0.35, 0.45), spec - vec2(-0.35, 0.45)) * 30.0);
	col += city_a.rgb * 0.15 * lens * smoothstep(0.5, 1.0, -spec.y) * (1.0 - rim);

	col *= 1.0 - 0.35 * pow(length(UV - 0.5) * 1.2, 2.0);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
