// Floodlit (visualiser.json): a football match under floodlights, seen from high in the main stand, every surface
// found exactly (planes, capsules, a sphere; no marching). The pitch is mown in stripes and marked out in full
// (touchlines, halfway line, centre circle, both penalty areas with their arcs and spots, six-yard boxes, corner
// arcs), with goals and nets. Three stands are full: every seat is a dot in the home or the away colours, and the
// crowd is the spectrum going round the ground (the low notes at the left end, the high at the right): each block
// stands up and lifts its colours with its part; a wave also runs round on the music's clock (drive), and cameras
// flash here and there with the high notes. LED boards along the far touchline show the spectrum as bars. Two teams
// of eleven hold their shapes and drift towards the ball, each with the four shadows floodlights give; the ball is
// passed about in arcs on the music's clock. Floodlight towers glare through the haze beyond the stands. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float crowd = 0.7;
uniform float tempo = 0.5;
uniform float haze = 0.5;
uniform vec4 home : source_color = vec4(0.8, 0.1, 0.12, 1.0);
uniform vec4 away : source_color = vec4(0.95, 0.85, 0.2, 1.0);
uniform vec4 grass : source_color = vec4(0.16, 0.45, 0.14, 1.0);
uniform vec4 night : source_color = vec4(0.03, 0.04, 0.1, 1.0);

const float HALF_L = 52.5;
const float HALF_W = 34.0;
const int PLAYERS = 22;


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

vec3 hash3(vec2 c) {
	uint h = hash_u(uint(int(c.x) + 100000) * 73856093u ^ uint(int(c.y) + 100000) * 19349663u);
	uint h2 = h * 2654435761u + 12345u;
	h2 ^= h2 >> 15u;
	return vec3(float(h & 65535u), float(h >> 16u), float(h2 & 65535u)) / 65535.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash3(i).x, hash3(i + vec2(1.0, 0.0)).x, f.x), mix(hash3(i + vec2(0.0, 1.0)).x, hash3(i + vec2(1.0, 1.0)).x, f.x), f.y);
}

float sd_box(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// The distance from q (on the pitch, metres from the centre spot) to the nearest white line.
float markings(vec2 q) {
	vec2 a = abs(q);
	float d = abs(sd_box(q, vec2(0.0), vec2(HALF_L, HALF_W)));
	d = min(d, max(a.x, a.y - HALF_W));
	d = min(d, abs(length(q) - 9.15));
	d = min(d, length(q) - 0.12);
	d = min(d, abs(sd_box(a, vec2(HALF_L - 8.25, 0.0), vec2(8.25, 20.16))));
	d = min(d, abs(sd_box(a, vec2(HALF_L - 2.75, 0.0), vec2(2.75, 9.16))));
	vec2 spot = a - vec2(HALF_L - 11.0, 0.0);
	d = min(d, length(spot) - 0.12);
	d = min(d, max(abs(length(spot) - 9.15), a.x - (HALF_L - 16.5)));
	d = min(d, max(abs(length(a - vec2(HALF_L, HALF_W)) - 1.0), max(a.x - HALF_L, a.y - HALF_W)));
	return d;
}

// The ball: passed from place to place in arcs on the music's clock.
vec3 ball_at(float t) {
	float k = floor(t);
	float f = fract(t);
	f = f * f * (3.0 - 2.0 * f);
	vec3 h0 = hash3(vec2(k, 3.0));
	vec3 h1 = hash3(vec2(k + 1.0, 3.0));
	vec2 a = (h0.xy - 0.5) * vec2(84.0, 52.0);
	vec2 b = (h1.xy - 0.5) * vec2(84.0, 52.0);
	vec2 p = mix(a, b, f);
	float lofted = step(0.5, h0.z);
	return vec3(p.x, 0.22 + 4.0 * f * (1.0 - f) * length(b - a) * 0.16 * lofted, p.y);
}

// Player i's place on the pitch: a 4-4-2 each, drifting, drawn a little towards the ball.
vec2 player_at(int i, vec2 ball) {
	int k = i % 11;
	float side = i < 11 ? -1.0 : 1.0;
	float fi = float(i);
	vec2 base;
	if (k == 0) {
		base = vec2(48.0, 0.0);
	} else if (k < 5) {
		base = vec2(33.0, (float(k) - 2.5) * 13.0);
	} else if (k < 9) {
		base = vec2(17.0, (float(k) - 6.5) * 14.0);
	} else {
		base = vec2(4.0, (float(k) - 9.5) * 16.0);
	}
	base.x *= side;
	float pull = k == 0 ? 0.03 : 0.22;
	base += (ball - base) * pull;
	return base + (k == 0 ? 1.0 : 4.0) * vec2(sin(drive * 0.13 + fi * 1.7), sin(drive * 0.11 + fi * 2.9));
}

// A stand's crowd at (u along the rows, v up the slope), ang: where it is round the ground (0 left end .. 1 right).
vec3 stand(float u, float v, float ang, float away_end, float px_m) {
	vec2 g = vec2(u / 0.55, v / 0.85);
	vec2 seat = floor(g);
	vec2 f = fract(g);
	vec3 h = hash3(seat + vec2(away_end * 500.0, 0.0));
	// Each block of the ground is a part of the spectrum; a wave runs round as well.
	float block = floor(ang * 24.0);
	float b = band(0.04 + block / 23.0 * 0.86);
	float wave = pow(0.5 + 0.5 * sin(ang * TAU * 2.0 - drive * 0.45), 6.0);
	float up = clamp((0.4 + 0.3 * b * (0.4 + 0.6 * h.y) + 0.6 * wave) * crowd, 0.0, 1.0);
	vec3 shirt = h.x < 0.6 ? mix(home.rgb, away.rgb, away_end) : (h.x < 0.72 ? vec3(0.55, 0.55, 0.6) : vec3(0.14, 0.16, 0.22) + 0.2 * h.zxy);
	vec3 c = vec3(0.09, 0.1, 0.14);
	// The person: a dot that grows taller and brighter as they stand and lift their colours.
	vec2 d = (f - vec2(0.5, 0.36 + 0.14 * up)) / vec2(0.34, 0.3 + 0.2 * up);
	float body = smoothstep(1.0, 0.7, length(d)) * step(0.05, h.z);
	c = mix(c, shirt * (0.6 + 0.45 * up), body);
	c = mix(c, vec3(0.75, 0.6, 0.5) * (0.5 + 0.5 * up), smoothstep(0.2, 0.1, length(f - vec2(0.5, 0.74 + 0.1 * up))) * step(0.05, h.z) * 0.8);
	// Far off the seats run together.
	c = mix(c, mix(vec3(0.05, 0.06, 0.1), shirt * (0.7 + 0.5 * up), 0.6), smoothstep(0.25, 0.7, px_m));
	// Stairs between the blocks, and a camera's flash now and then.
	float stair = smoothstep(0.9, 0.6, abs(fract(u / 0.55 / 16.0) - 0.5) * 16.0);
	c = mix(c, vec3(0.16, 0.15, 0.1), stair * 0.8);
	float fl = hash3(seat + floor(vis_time * 1.5 + h.x * 9.0) * vec2(7.0, 3.0)).x;
	c += vec3(1.0) * step(0.9992 - 0.001 * treble, fl) * smoothstep(0.35, 0.0, length(f - 0.5)) * (0.5 + 0.5 * treble);
	return c;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 uv = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float bt = drive * tempo * 0.4;
	vec3 ball = ball_at(bt);
	float pan = 7.0 * sin(drive * 0.012);
	vec3 ro = vec3(pan * 0.4, 21.0, -66.0);
	vec3 ta = vec3(pan, 8.0, 6.0);
	vec3 cw = normalize(ta - ro);
	vec3 cu = normalize(cross(cw, vec3(0.0, 1.0, 0.0)));
	vec3 cv = cross(cu, cw);
	float focal = 1.3;
	vec3 rd = normalize(uv.x * cu + uv.y * cv + focal * cw);
	float lights_k = 0.9 + 0.15 * level;

	// The night sky over the ground, glowing with the lights.
	vec3 col = night.rgb * (0.6 + 1.2 * smoothstep(0.35, 0.0, rd.y)) + vec3(0.1, 0.11, 0.13) * haze * smoothstep(0.3, 0.02, rd.y);
	float depth = 1e9;

	// The ground: pitch and surround.
	float tg = -ro.y / rd.y;
	vec2 q = (ro + rd * tg).xz;
	float fw = length(fwidth(q)) * 0.6;
	if (rd.y < 0.0 && abs(q.x) < 59.0 && q.y < 40.0) {
		depth = tg;
		vec3 gc = grass.rgb;
		if (abs(q.x) < HALF_L + 3.0 && abs(q.y) < HALF_W + 3.0) {
			float stripe = mod(floor((q.x + HALF_L) / 5.25), 2.0);
			gc *= 0.95 + 0.22 * stripe + 0.05 * mod(floor((q.y + HALF_W) / 5.6), 2.0);
			gc *= 0.92 + 0.16 * vnoise(q * 1.5);
			float md = markings(q);
			gc = mix(gc, vec3(0.92), smoothstep(0.07 + fw, 0.07 - fw, md) * clamp(0.14 / (fw + 0.07), 0.25, 0.9));
		} else {
			gc = mix(grass.rgb * 0.6, vec3(0.2, 0.2, 0.22), smoothstep(HALF_W + 3.5, HALF_W + 4.0, abs(q.y)) + smoothstep(HALF_L + 3.5, HALF_L + 4.0, abs(q.x)));
		}
		// The players' shadows: four each, one from each floodlight.
		float sh = 0.0;
		vec2 sball = q - ball.xz;
		for (int i = 0; i < PLAYERS; i++) {
			vec2 d = q - player_at(i, ball.xz);
			if (abs(d.x) + abs(d.y) < 5.0) {
				vec2 r = vec2(d.x + d.y, d.x - d.y) * 0.707;
				sh += smoothstep(0.38, 0.1, abs(r.y)) * smoothstep(2.4, 0.2, abs(r.x)) + smoothstep(0.38, 0.1, abs(r.x)) * smoothstep(2.4, 0.2, abs(r.y));
			}
		}
		sh += smoothstep(0.5 + ball.y * 0.4, 0.1, length(sball)) * 1.2 / (1.0 + ball.y * 0.3);
		gc *= 1.0 - 0.2 * clamp(sh, 0.0, 1.5);
		col = gc * (0.75 + 0.5 * exp(-dot(q, q) / 5000.0)) * lights_k * vec3(1.02, 1.0, 0.95);
	}

	// The far stand: two tiers of crowd, a fascia between them.
	{
		float tt = (1.2 - 0.5 * 39.0 - ro.y + 0.5 * ro.z) / (rd.y - 0.5 * rd.z);
		vec3 p = ro + rd * tt;
		if (tt > 0.0 && tt < depth && p.z > 39.0 && p.z < 80.0 && abs(p.x) < 62.0) {
			depth = tt;
			float v = (p.z - 39.0) * 1.118;
			float ang = 0.2 + 0.6 * (p.x + 62.0) / 124.0;
			vec3 c = stand(p.x, v, ang, 0.0, tt / (size.y * focal) / 0.55);
			if (v > 19.0 && v < 21.5) {
				float bar = band(0.04 + 0.9 * fract(p.x / 31.0 + drive * 0.01));
				c = mix(vec3(0.03), mix(home.rgb, vec3(1.0), 0.3) * (0.3 + 0.9 * bar), step(abs(v - 20.25), 0.8) * step(0.15, fract(p.x / 0.7)));
			}
			col = c * lights_k;
		}
	}
	// The stands behind each goal (the away end on the right).
	for (int s = -1; s <= 1; s += 2) {
		float fs = float(s);
		float tt = (1.2 - 0.5 * 58.0 - ro.y + 0.5 * fs * ro.x) / (rd.y - 0.5 * fs * rd.x);
		vec3 p = ro + rd * tt;
		if (tt > 0.0 && tt < depth && p.x * fs > 58.0 && p.x * fs < 92.0 && p.z > -42.0 && p.z < 42.0) {
			depth = tt;
			float v = (p.x * fs - 58.0) * 1.118;
			float ang = s < 0 ? 0.2 * (p.z + 42.0) / 84.0 : 0.8 + 0.2 * (42.0 - p.z) / 84.0;
			col = stand(p.z, v, ang, s > 0 ? 1.0 : 0.0, tt / (size.y * focal) / 0.55) * lights_k * 0.9;
		}
	}
	// The far stand's roof: a pale edge over the upper tier.
	{
		float tt = (52.0 - ro.z) / rd.z;
		vec3 p = ro + rd * tt;
		if (tt < depth && abs(p.x) < 64.0 && p.y > 24.5 && p.y < 26.6) {
			depth = tt;
			col = vec3(0.5, 0.52, 0.56) * (0.5 + 0.3 * step(0.08, fract(p.x / 4.0))) * lights_k;
			col += vec3(1.0, 0.97, 0.9) * smoothstep(0.35, 0.1, length(vec2((fract(p.x / 4.0) - 0.5) * 4.0, p.y - 24.9)));
		}
	}

	// The roof's underside, dark over the upper tier.
	{
		float tt = (26.6 - ro.y) / rd.y;
		vec3 p = ro + rd * tt;
		if (tt > 0.0 && tt < depth && abs(p.x) < 64.0 && p.z > 52.0 && p.z < 86.0) {
			depth = tt;
			col = vec3(0.05, 0.055, 0.07) * (0.6 + 0.4 * step(0.1, fract(p.x / 8.0))) * (0.7 + 0.3 * step(0.08, fract(p.z / 6.0)));
		}
	}

	// LED boards along the far touchline: the spectrum as bars.
	{
		float tt = (37.2 - ro.z) / rd.z;
		vec3 p = ro + rd * tt;
		if (tt < depth && abs(p.x) < 56.0 && p.y > 0.0 && p.y < 0.95) {
			depth = tt;
			float cell = (floor(p.x / 0.8) + 0.5) * 0.8;
			float b = band(0.03 + 0.92 * abs(cell) / 56.0);
			vec3 c = mix(home.rgb, vec3(1.0), 0.15) * step(p.y / 0.95, 0.12 + 0.85 * b) * step(0.12, fract(p.x / 0.8));
			col = c * 0.6 + vec3(0.02);
		}
	}

	// The goals: posts, bar and net.
	for (int s = -1; s <= 1; s += 2) {
		float fs = float(s);
		float tt = (fs * HALF_L - ro.x) / rd.x;
		vec3 p = ro + rd * tt;
		if (tt > 0.0 && tt < depth + 0.5 && abs(p.z) < 4.0 && p.y < 2.7 && p.y > 0.0) {
			float frame = min(abs(abs(p.z) - 3.66), abs(p.y - 2.44) + step(3.66, abs(p.z)) * 9.0) - 0.07;
			float wpx = tt / (size.y * focal);
			col = mix(col, vec3(0.95), smoothstep(wpx, -wpx, frame) * step(p.y, 2.52));
		}
		float tn = (fs * (HALF_L + 2.0) - ro.x) / rd.x;
		vec3 pn = ro + rd * tn;
		if (tn > 0.0 && tn < depth + 3.0 && abs(pn.z) < 3.66 && pn.y < 2.44 && pn.y > 0.0) {
			float net = min(abs(fract(pn.z / 0.3) - 0.5), abs(fract(pn.y / 0.3) - 0.5));
			col = mix(col, vec3(0.9), smoothstep(0.08, 0.02, net) * 0.3);
		}
	}

	// The players: a capsule each in its team's shirt, pale shorts, a head.
	for (int i = 0; i < PLAYERS; i++) {
		vec2 pp = player_at(i, ball.xz);
		vec3 a = vec3(pp.x, 0.35, pp.y);
		vec3 oa = a - ro;
		float along = dot(oa, rd);
		if (along > depth || along < 0.0) {
			continue;
		}
		vec3 w = ro + rd * along - a;
		if (dot(w.xz, w.xz) > 4.0) {
			continue;
		}
		// The nearest point of the ray to the upright segment a .. a + 1.15 up.
		float b = rd.y;
		float e = dot(vec3(0.0, 1.0, 0.0), -oa);
		float den = max(1.0 - b * b, 0.001);
		float hgt = clamp((e - b * dot(rd, -oa)) / den, 0.0, 1.5);
		vec3 c = a + vec3(0.0, hgt, 0.0);
		float s = dot(c - ro, rd);
		float dist = length(ro + rd * s - c);
		float wpx = s / (size.y * focal);
		int k = i % 11;
		vec3 kit = i < 11 ? home.rgb : away.rgb;
		if (k == 0) {
			kit = i < 11 ? vec3(0.1, 0.8, 0.4) : vec3(0.95, 0.5, 0.1);
		}
		vec3 pc = hgt > 0.75 ? kit : (hgt > 0.4 ? vec3(0.9) : kit * 0.6);
		pc *= 0.8 + 0.25 * hgt;
		col = mix(col, pc * lights_k, smoothstep(0.4 + wpx, 0.4 - wpx, dist));
		vec3 hd = a + vec3(0.0, 1.95, 0.0);
		float hdist = length(cross(rd, hd - ro));
		col = mix(col, vec3(0.8, 0.62, 0.5) * lights_k, smoothstep(0.24 + wpx, 0.24 - wpx, hdist));
	}

	// The ball.
	{
		vec3 ob = ball - ro;
		float along = dot(ob, rd);
		if (along < depth + 1.0) {
			float d = length(ob - rd * along);
			float wpx = along / (size.y * focal);
			float r = 0.38;
			col = mix(col, vec3(1.0) * (0.7 + 0.3 * smoothstep(r, 0.0, d)), smoothstep(r + wpx, r - wpx, d));
			col += vec3(1.0, 1.0, 0.95) * exp(-d * d / 0.5) * 0.12;
		}
	}

	// Floodlight towers beyond the far corners: racks of lamps, their glare in the haze.
	for (int s = -1; s <= 1; s += 2) {
		vec3 lp = vec3(float(s) * 74.0, 44.0, 90.0);
		float tt = (lp.z - ro.z) / rd.z;
		vec3 p = ro + rd * tt;
		vec2 d = p.xy - lp.xy;
		if (depth > tt || p.y > 22.0) {
			float mast = max(abs(d.x) - 0.5, d.y);
			col = mix(col, vec3(0.03, 0.03, 0.05), smoothstep(0.3, 0.0, mast) * step(1e8, depth));
			if (abs(d.x) < 4.2 && abs(d.y) < 3.2) {
				vec2 lf = fract(d / 1.4 + 0.5) - 0.5;
				col = mix(col, vec3(0.05), 0.8);
				col += vec3(1.0, 0.98, 0.9) * smoothstep(0.38, 0.2, length(lf)) * 1.2 * lights_k;
			}
			float l = length(d * vec2(1.0, 1.25));
			col += vec3(1.0, 0.97, 0.88) * (exp(-l * 0.22) * 0.5 + exp(-l * 0.05) * 0.12 * (0.4 + haze)) * lights_k;
			col += vec3(1.0, 0.97, 0.88) * exp(-abs(d.y) * 0.9) * exp(-abs(d.x) * 0.05) * 0.12 * lights_k;
		}
	}
	// Haze over the pitch, lit.
	col += vec3(0.08, 0.085, 0.09) * haze * smoothstep(0.0, 140.0, min(depth, 200.0)) * lights_k;

	col *= 1.0 - 0.3 * pow(length(UV - 0.5) * 1.25, 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
