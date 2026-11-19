// Koi pond (visualiser.json): a garden pond seen from above in daylight. Koi of five kinds (red and white, red white
// and black, gold, black red and white, blue-grey with an orange belly) swim slow loops over a bed of pebbles, their
// bodies bending along the curve they swim and their tails beating, each as hard as its own part of the spectrum;
// they cast soft shadows on the stones. Light through the surface draws moving caustics on the bottom, brighter with
// the middle notes. Drops land on the music's clock (drive) and send out rings that bend the view below and catch
// the sun; lily pads float on top, their flowers opening with the high notes. Worked out per pixel: no memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float swim = 0.5;
uniform float ripples = 0.5;
uniform float lilies = 0.6;
uniform vec4 water : source_color = vec4(0.12, 0.3, 0.28, 1.0);
uniform vec4 stones : source_color = vec4(0.45, 0.42, 0.36, 1.0);
uniform vec4 koi_red : source_color = vec4(0.9, 0.3, 0.1, 1.0);
uniform vec4 flower : source_color = vec4(0.98, 0.6, 0.75, 1.0);
uniform vec4 leaf : source_color = vec4(0.25, 0.5, 0.2, 1.0);

const int KOI = 5;
const int DROPS = 6;
const int PADS = 6;
const vec2 SHADOW = vec2(-0.03, 0.04);


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

float cross2(vec2 a, vec2 b) {
	return a.x * b.y - a.y * b.x;
}

vec2 koi_path(int i, float s, float aspect) {
	float fi = float(i);
	vec2 c = vec2((0.28 + 0.48 * fract(0.3 + fi * 0.618)) * aspect, 0.5 + 0.1 * sin(fi * 2.0));
	vec2 a = vec2(0.3 * aspect * (0.6 + 0.4 * fract(fi * 0.37 + 0.5)), 0.27);
	return c + vec2(a.x * sin(s + fi), a.y * (0.8 * sin(2.0 * s + fi * 1.7) + 0.2 * sin(3.0 * s + fi)));
}

// Koi i near p: its frame along its body. Returns (u along the body 0 nose .. 1 tail root, v across from the spine,
// the body's half width there, its length).
vec4 koi_frame(int i, vec2 p, float aspect) {
	float fi = float(i);
	float s = drive * swim * 0.22 * (0.75 + 0.3 * fract(fi * 0.71)) + fi * 1.3;
	float h = 0.012;
	vec2 p0 = koi_path(i, s - h, aspect);
	vec2 p1 = koi_path(i, s, aspect);
	vec2 p2 = koi_path(i, s + h, aspect);
	vec2 d1 = (p2 - p0) / (2.0 * h);
	vec2 d2 = (p2 - 2.0 * p1 + p0) / (h * h);
	float sp = max(length(d1), 1e-4);
	float kappa = cross2(d1, d2) / (sp * sp * sp);
	vec2 dir = d1 / sp;
	vec2 nrm = vec2(-dir.y, dir.x);
	float L = 0.17 + 0.07 * fract(fi * 0.53 + 0.1);
	vec2 q = p - p1;
	float u = dot(q, -dir) / L;
	float v = dot(q, nrm);
	float b = band(0.05 + fi / float(KOI - 1) * 0.8);
	float uc = clamp(u, 0.0, 1.4);
	float spine = 0.5 * clamp(kappa, -6.0, 6.0) * (uc * L) * (uc * L);
	spine += L * (0.04 + 0.13 * b) * uc * uc * sin(uc * 5.5 - vis_time * 4.0 * (0.5 + swim) - fi * 2.0);
	v -= spine;
	float W = 0.13 * L;
	float hw = W * sqrt(clamp(u / 0.13, 0.0, 1.0)) * mix(1.0, 0.18, smoothstep(0.3, 1.0, u));
	return vec4(u, v, hw, L);
}

// How much of koi i covers p (body, and fins at half), and its colour.
vec4 koi_at(int i, vec2 p, float aspect, float px, bool colour) {
	// Far from the head (one point on the path): nothing to do.
	float fi0 = float(i);
	float s0 = drive * swim * 0.22 * (0.75 + 0.3 * fract(fi0 * 0.71)) + fi0 * 1.3;
	float L0 = 0.17 + 0.07 * fract(fi0 * 0.53 + 0.1);
	if (length(p - koi_path(i, s0, aspect)) > L0 * 1.5) {
		return vec4(0.0);
	}
	vec4 f = koi_frame(i, p, aspect);
	float u = f.x;
	float v = f.y;
	float hw = f.z;
	float L = f.w;
	if (u < -0.05 || u > 1.45 || abs(v) > L * 0.45) {
		return vec4(0.0);
	}
	float aa = px * 1.2;
	float body = (u > 0.0 && u < 1.0) ? smoothstep(aa, -aa, abs(v) - hw) : 0.0;
	// Tail: a forked fan.
	float tw = L * 0.13 * smoothstep(0.9, 1.28, u);
	float tend = 1.2 + 0.16 * clamp(abs(v) / (L * 0.13), 0.0, 1.0);
	float tail = (u > 0.9) ? smoothstep(aa, -aa, abs(v) - tw) * smoothstep(tend + 0.01, tend - 0.01, u) : 0.0;
	// Pectoral fins behind the head, and small pelvic fins, flapping.
	float flap = 0.85 + 0.15 * sin(vis_time * 3.0 + float(i));
	float fins = 0.0;
	for (int side = -1; side <= 1; side += 2) {
		if (!colour) {
			break;
		}
		float sd = float(side);
		vec2 fc = vec2(0.27 * L, sd * (0.13 * L * 0.95 + 0.04 * L * flap));
		vec2 fq = vec2(u * L, v) - fc;
		float ang = sd * 0.6;
		fq = vec2(cos(ang) * fq.x - sin(ang) * fq.y, sin(ang) * fq.x + cos(ang) * fq.y);
		float e = length(fq / vec2(0.075 * L, 0.035 * L * flap)) - 1.0;
		fins = max(fins, smoothstep(0.08, -0.08, e));
		vec2 pc = vec2(0.58 * L, sd * 0.09 * L);
		vec2 pq = vec2(u * L, v) - pc;
		float e2 = length(pq / vec2(0.04 * L, 0.02 * L)) - 1.0;
		fins = max(fins, smoothstep(0.1, -0.1, e2) * 0.8);
	}
	float a = max(body, max(tail, fins) * 0.6);
	if (!colour || a <= 0.0) {
		return vec4(0.0, 0.0, 0.0, a);
	}
	// Markings by kind.
	vec3 white = vec3(0.96, 0.94, 0.9);
	vec3 red = koi_red.rgb;
	vec3 black = vec3(0.07, 0.07, 0.08);
	vec3 gold = vec3(0.98, 0.76, 0.32);
	float fi = float(i);
	vec2 mq = vec2(u * 6.0, v / (0.13 * L) * 1.4) + vec2(fi * 17.0, fi * 5.0);
	float n1 = vnoise(mq) * 0.65 + vnoise(mq * 2.3) * 0.35;
	float n2 = vnoise(mq * 1.7 + 40.0);
	int kind = i % 5;
	vec3 c = white;
	if (kind == 0) {
		c = mix(white, red, smoothstep(0.48, 0.53, n1 + 0.25 * (1.0 - smoothstep(0.0, 0.25, u))));
	} else if (kind == 1) {
		c = mix(white, red, smoothstep(0.52, 0.57, n1));
		c = mix(c, black, smoothstep(0.7, 0.74, n2));
	} else if (kind == 2) {
		c = gold;
	} else if (kind == 3) {
		c = mix(black, red, smoothstep(0.52, 0.56, n1));
		c = mix(c, white, smoothstep(0.62, 0.66, n2) * (1.0 - smoothstep(0.52, 0.56, n1)));
	} else {
		c = mix(vec3(0.42, 0.52, 0.6), red * 0.95, smoothstep(0.55, 0.85, abs(v) / max(hw, 1e-4)));
	}
	// Round body, a bright line down the back, scales.
	float sidev = clamp(abs(v) / max(hw, 1e-4), 0.0, 1.0);
	float rnd = sqrt(max(1.0 - sidev * sidev, 0.0));
	c *= (0.62 + 0.38 * rnd) * mix(1.0, 0.9, body * 0.0);
	vec2 sc = vec2(u * L / 0.0075, v / 0.0075);
	sc.y += 0.5 * mod(floor(sc.x), 2.0);
	float scale = smoothstep(0.42, 0.5, length(fract(sc) - vec2(0.0, 0.5)));
	c *= 1.0 - 0.1 * scale * body;
	c += vec3(1.0) * pow(rnd, 10.0) * body * (kind == 2 ? 0.45 : 0.18) * smoothstep(0.1, 0.3, u);
	// Eyes.
	float ey = 0.65 * 0.13 * L * sqrt(0.06 / 0.13);
	float eye = min(length(vec2(u * L - 0.06 * L, abs(v) - ey)), 1.0) - 0.006;
	c = mix(c, vec3(0.03), smoothstep(px, -px, eye) * body);
	// Fins are thin: the colour paled and striped with rays.
	float rays = 0.85 + 0.15 * sin(atan(v, u * L - 0.9 * L) * 30.0);
	vec3 fc = mix(c, white, 0.35) * rays;
	c = mix(fc, c, body);
	return vec4(c, a);
}

// Height of the surface, as its slope: drops' rings and a light breeze.
vec2 surface_slope(vec2 p, float aspect) {
	vec2 g = 0.02 * vec2(sin(p.y * 38.0 + vis_time * 1.1 + sin(p.x * 9.0)), cos(p.x * 33.0 - vis_time * 0.9 + sin(p.y * 7.0)));
	float c = drive * 0.6;
	float dt = 0.55;
	float kc = floor(c / dt);
	for (int k = 0; k < DROPS; k++) {
		float kd = kc - float(k);
		float age = c - kd * dt;
		float hd = hash1(vec2(kd, 1.0));
		vec2 dp = vec2(hd * aspect, 0.1 + 0.8 * fract(hd * 97.31));
		vec2 d = p - dp;
		float r = length(d);
		float R = age * 0.14;
		float x = r - R;
		if (abs(x) > 0.06) {
			continue;
		}
		float A = ripples * 0.6 * exp(-age * 0.8) * (0.4 + 0.8 * band(fract(hd * 31.7)));
		float env = exp(-x * x / 0.0006);
		g += d / max(r, 1e-4) * A * cos(x * 140.0) * env * smoothstep(0.0, 0.05, R);
	}
	return g;
}

vec4 pad_at(int j, vec2 p, float aspect) {
	float fj = float(j);
	vec2 c = vec2((0.06 + 0.88 * fract(0.15 + fj * 0.618)) * aspect, 0.18 + 0.66 * fract(0.42 + fj * 0.382));
	c += 0.015 * vec2(sin(drive * 0.05 + fj), cos(drive * 0.04 + fj * 2.0));
	float r = 0.045 + 0.03 * fract(fj * 0.77 + 0.3);
	return vec4(c, r, fract(fj * 0.29 + 0.6) * TAU);
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;

	vec2 slope = surface_slope(p, aspect);
	vec2 look = p - slope * 0.035;

	// The bottom: pebbles, nearest and second nearest of nine.
	vec2 sq = look / 0.042;
	vec2 si = floor(sq);
	float d1 = 9.0;
	float d2 = 9.0;
	vec2 best = vec2(0.0);
	vec2 bestc = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 cell = si + vec2(float(x), float(y));
			float hc = hash1(cell);
			vec2 o = vec2(hc, fract(hc * 37.13)) * 0.8 + 0.1;
			vec2 dd = cell + o - sq;
			float l = dot(dd, dd);
			if (l < d1) {
				d2 = d1;
				d1 = l;
				best = cell;
				bestc = dd;
			} else if (l < d2) {
				d2 = l;
			}
		}
	}
	float gap = sqrt(d2) - sqrt(d1);
	float hb = fract(hash1(best) * 91.7);
	vec3 stone = stones.rgb * (0.65 + 0.6 * hb) * mix(vec3(1.0), vec3(1.05, 0.95, 0.85), fract(hb * 13.3));
	float bump = smoothstep(0.0, 0.35, gap);
	stone *= 0.55 + 0.45 * bump + 0.25 * dot(normalize(-bestc + 1e-4), vec2(-0.6, 0.8)) * bump * (1.0 - bump);
	vec3 col = stone;
	// Caustics.
	vec2 cq = look * 9.0;
	float n1 = vnoise(cq + vec2(vis_time * 0.35, -vis_time * 0.2) + 0.3 * vec2(sin(cq.y * 0.7 + vis_time * 0.5), cos(cq.x * 0.6 - vis_time * 0.4)));
	float caus = pow(1.0 - abs(2.0 * n1 - 1.0), 12.0);
	col += vec3(1.0, 0.98, 0.85) * caus * (0.25 + 0.5 * mid);
	// Shadows of the fish and the pads on the bottom.
	float sh = 0.0;
	for (int i = 0; i < KOI; i++) {
		sh = max(sh, koi_at(i, look + SHADOW, aspect, px * 6.0, false).a);
	}
	if (lilies > 0.0) {
		for (int j = 0; j < PADS; j++) {
			if (float(j) >= lilies * float(PADS) + 0.5) {
				break;
			}
			vec4 pd = pad_at(j, p + SHADOW * 1.6, aspect);
			sh = max(sh, smoothstep(pd.z + 0.012, pd.z - 0.012, length(p + SHADOW * 1.6 - pd.xy)));
		}
	}
	col *= 1.0 - 0.45 * sh;
	// The water between: deeper towards the middle.
	float deep = 0.62 + 0.15 * smoothstep(0.0, 0.6, 1.0 - length((UV - 0.5) * vec2(1.2, 1.6)));
	col = mix(col, water.rgb, deep);

	// The koi, a little below the surface.
	for (int i = 0; i < KOI; i++) {
		vec4 k = koi_at(i, look, aspect, px, true);
		if (k.a > 0.0) {
			col = mix(col, mix(k.rgb, water.rgb, 0.2), k.a);
		}
	}

	// The surface: sky in it at a slant, and the sun caught on the ripples.
	vec3 n = normalize(vec3(-slope, 1.0));
	vec3 H = normalize(normalize(vec3(-0.35, 0.45, 1.0)) + vec3(0.0, 0.0, 1.0));
	float spec = pow(max(dot(n, H), 0.0), 300.0);
	col += vec3(0.75, 0.85, 0.95) * 0.06 + vec3(1.0, 0.97, 0.9) * spec * 1.4;
	col += vec3(0.6, 0.75, 0.85) * 0.25 * clamp(length(slope) * 2.0, 0.0, 1.0);

	// Lily pads and their flowers.
	if (lilies > 0.0) {
		for (int j = 0; j < PADS; j++) {
			if (float(j) >= lilies * float(PADS) + 0.5) {
				break;
			}
			vec4 pd = pad_at(j, p, aspect);
			vec2 q = p - pd.xy;
			float r = length(q);
			if (r > pd.z * 1.05) {
				continue;
			}
			float ang = atan(q.y, q.x);
			float notch = abs(atan(sin(ang - pd.w), cos(ang - pd.w)));
			float cut = smoothstep(0.18, 0.24, notch + (1.0 - r / pd.z) * 0.3) ;
			float in_pad = smoothstep(pd.z + px, pd.z - px, r) * cut;
			vec3 lc = leaf.rgb * (0.85 + 0.3 * vnoise(q * 80.0 + float(j) * 9.0));
			lc *= 0.85 + 0.15 * smoothstep(0.0, 0.5, abs(fract(ang / TAU * 14.0) - 0.5) * 2.0 + 0.3);
			lc = mix(lc, lc * 0.6 + vec3(0.25, 0.08, 0.05), smoothstep(pd.z * 0.88, pd.z, r));
			lc += vec3(0.9) * 0.12 * smoothstep(0.6, 0.0, length(q / pd.z - vec2(-0.3, 0.35)));
			col = mix(col, lc, in_pad);
			if (j % 2 == 0) {
				vec2 fq = q - vec2(cos(pd.w + PI), sin(pd.w + PI)) * pd.z * 0.35;
				float fr = length(fq);
				float open = 0.75 + 0.35 * clamp(treble * 2.0, 0.0, 1.0);
				float fl = pd.z * 0.55 * open;
				float fa = atan(fq.y, fq.x);
				// A ring of eight petals and an inner ring turned half a petal, paler.
				for (int ring = 0; ring < 2; ring++) {
					float rf = ring == 0 ? 1.0 : 0.68;
					float tf = fract(fa / TAU * 8.0 + (ring == 0 ? 0.0 : 0.5)) - 0.5;
					float petal = fl * rf * (1.0 - 1.6 * tf * tf * 4.0 * 0.5);
					float in_p = smoothstep(px * 1.5, -px * 1.5, fr - petal * (1.0 - 0.9 * abs(tf) * 2.0 * abs(tf) * 2.0));
					vec3 pc = mix(flower.rgb, vec3(1.0), ring == 0 ? 0.15 : 0.5) * (0.75 + 0.35 * (1.0 - abs(tf) * 2.0)) * (0.8 + 0.2 * fr / (fl * rf));
					col = mix(col, pc, in_p);
				}
				float centre = smoothstep(fl * 0.22 + px, fl * 0.22 - px, fr);
				vec3 yc = vec3(1.0, 0.82, 0.25) * (0.8 + 0.3 * step(0.5, fract(fa / TAU * 20.0)));
				col = mix(col, yc, centre);
			}
		}
	}

	col *= 1.0 - 0.3 * pow(length(UV - 0.5) * 1.2, 2.0);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
