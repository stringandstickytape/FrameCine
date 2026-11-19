// Clockwork (visualiser.json): a watch movement seen from the back. A gear train (barrel, centre, third and fourth
// wheels, each turning the next one's pinion, teeth properly meshed) ends in the escape wheel; a pallet lever rocks on
// every beat and lets the escape wheel tick on half a tooth, so the whole train steps with the music, while the music's
// clock (drive) turns it between beats. The balance wheel swings with its hairspring breathing, wider when it is loud.
// Bridges with striped finish and polished bevels hold the arbors in ruby jewels, which glow each with its own part of
// the spectrum; blued screws hold the bridges. Gears are drawn with a sunray brushing that turns with them, while the
// sheen stays where the light is. Everything is worked out from the clocks: the shader needs no memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float speed = 0.5;
uniform float swing = 0.6;
uniform float shine = 0.6;
uniform vec4 gold : source_color = vec4(0.85, 0.64, 0.25, 1.0);
uniform vec4 plate : source_color = vec4(0.55, 0.56, 0.59, 1.0);
uniform vec4 steel : source_color = vec4(0.77, 0.79, 0.82, 1.0);
uniform vec4 jewel : source_color = vec4(0.77, 0.09, 0.19, 1.0);
uniform vec4 blued : source_color = vec4(0.15, 0.28, 0.66, 1.0);

const float M = 0.0075;
const vec2 SO = vec2(0.006, 0.011);


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float hash1(vec2 cell) {
	return float(hash_u(uint(int(cell.x) + 100000) * 73856093u ^ uint(int(cell.y) + 100000) * 19349663u) & 65535u)
			/ 65535.0;
}

float fill(float d) {
	return fill_px(d * size.y);
}

vec2 dir(float a) {
	return vec2(cos(a), sin(a));
}

float capsule(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t) - mix(ra, rb, t);
}

// Where the light comes from, as an angle on the card: it wanders slowly.
float light_angle() {
	return -2.2 + 0.5 * sin(drive * 0.05);
}

// Brushed metal at q from a centre, turned by th: fine sunray lines that turn with the part, a sheen across it that
// stays with the light, a polished bevel at the edge (d: the signed distance to the edge).
vec3 metal(vec3 base, vec2 q, float th, float d) {
	float a = atan(q.y, q.x);
	float len = length(q) * size.y;
	float brush = (0.06 * sin((a - th) * 300.0) + 0.05 * sin((a - th) * 131.0 + len * 0.05))
			* smoothstep(60.0, 120.0, len);
	float sheen = pow(abs(cos(a - light_angle())), 6.0);
	vec3 c = base * (0.62 + brush + shine * 0.6 * sheen);
	float edge = smoothstep(-3.0, -0.5, d * size.y);
	return mix(c, base * 1.35 + 0.12, edge * 0.6);
}

// Soft shadow of a disc of radius r at c, cast down and right onto what is below.
float disc_shadow(vec2 p, vec2 c, float r) {
	float d = length(p - SO - c) - r;
	return 1.0 - 0.5 * (1.0 - smoothstep(-0.008, 0.01, d));
}

// The outline of a toothed wheel: n teeth on pitch radius r, turned by th (signed distance, heights).
float teeth(vec2 q, float th, float n, float r) {
	float a = atan(q.y, q.x);
	float f = fract((a - th) * n / TAU + 0.5) - 0.5;
	float prof = clamp((0.3 - abs(f)) * 6.0, 0.0, 1.0);
	return length(q) - (r - 1.15 * M + 2.25 * M * prof);
}

// Holes between curved spokes, from the hub out to the rim (negative inside a hole).
float spoke_holes(vec2 q, float th, float hub, float rim, float count) {
	float len = length(q);
	float a = atan(q.y, q.x) - th - (len - hub) * 2.2;
	float st = TAU / count;
	float sa = mod(a, st) - st * 0.5;
	float spoke = abs(sin(sa)) * len - 0.007;
	return max(max(hub - len, len - rim), -spoke) + 0.004;
}

// A wheel over col: kind 0 a gold wheel with spokes, 1 a steel pinion, 2 the escape wheel, 3 the ratchet wheel.
void gear(inout vec3 col, vec2 p, vec2 c, float th, float n, float r, int kind) {
	vec2 q = p - c;
	float len = length(q);
	col *= disc_shadow(p, c, r);
	if (len > r + 2.0 * M) {
		return;
	}
	float d = 0.0;
	vec3 base = kind == 1 || kind == 3 ? steel.rgb : gold.rgb;
	if (kind == 2) {
		// Club teeth, raked: thin points leaning forward.
		float a = atan(q.y, q.x);
		float f = fract((a - th) * n / TAU + (len - r) * 18.0);
		float prof = smoothstep(0.0, 0.06, f) * (1.0 - smoothstep(0.06, 0.32, f));
		d = len - (r - 0.032 + 0.034 * prof);
		d = max(d, -spoke_holes(q, th, 0.022, r - 0.045, 4.0));
	} else if (kind == 3) {
		float a = atan(q.y, q.x);
		float f = fract((a - th) * n / TAU);
		d = len - (r - 0.012 + 0.012 * f);
	} else {
		d = teeth(q, th, n, r);
		if (kind == 0) {
			d = max(d, -spoke_holes(q, th, 0.045, r - 1.15 * M - 0.018, 5.0));
		}
	}
	vec3 m = metal(base, q, th, d);
	// The arbor through the middle.
	m = mix(m, steel.rgb * 0.9, fill(len - 0.011));
	m = mix(m, vec3(0.08), fill(len - 0.004));
	col = mix(col, m, fill(d));
}

vec3 plate_colour(vec2 p) {
	// Perlage: overlapping circles of graining, each with its bright side to the light and fine rings.
	float cs = 0.03;
	float best = -1.0;
	float shade = 0.8;
	for (int j = 0; j < 2; j++) {
		for (int i = 0; i < 2; i++) {
			vec2 g = floor(p / cs) + vec2(float(i), float(j));
			vec2 q = p - g * cs;
			float d = length(q) / cs;
			float order = hash1(g);
			if (d < 0.78 && order > best) {
				best = order;
				shade = 0.86 + 0.12 * cos(atan(q.y, q.x) - light_angle()) * smoothstep(0.0, 0.5, d)
						+ 0.03 * sin(d * 60.0 + order * 6.0);
			}
		}
	}
	return plate.rgb * 0.42 * shade;
}

// The bridges: a signed distance (heights) to all of them.
float bridges(vec2 p, vec2 a0, vec2 a1, vec2 a2, vec2 a3, vec2 a4, vec2 piv, vec2 bal) {
	float d = capsule(p, vec2(-0.08, 0.5), a0, 0.07, 0.085);
	d = min(d, capsule(p, a0, vec2(0.62, 1.1), 0.085, 0.06));
	d = min(d, capsule(p, a1, a2, 0.042, 0.038));
	d = min(d, capsule(p, a2, a3, 0.038, 0.036));
	d = min(d, capsule(p, a2, vec2(0.6, -0.08), 0.038, 0.05));
	d = min(d, capsule(p, a4, vec2(1.16, -0.08), 0.032, 0.045));
	d = min(d, capsule(p, piv, vec2(1.62, 0.2), 0.022, 0.03));
	d = min(d, capsule(p, bal, vec2(1.88, 0.92), 0.034, 0.06));
	return d;
}

void jewel_at(inout vec3 col, vec2 p, vec2 c, float glowv) {
	float d = length(p - c);
	if (d > 0.06) {
		return;
	}
	col += jewel.rgb * exp(-d * 70.0) * glowv * 0.35;
	col = mix(col, gold.rgb * (0.75 + 0.35 * cos(atan(p.y - c.y, p.x - c.x) - light_angle())), fill(d - 0.023));
	vec3 ruby = jewel.rgb * (0.45 + 1.2 * glowv) * (0.7 + 0.6 * smoothstep(0.016, 0.0, d));
	col = mix(col, ruby, fill(d - 0.015));
	col += vec3(1.0, 0.9, 0.9) * 0.55 * exp(-length(p - c - 0.006 * dir(light_angle())) * size.y * 0.6);
	col = mix(col, vec3(0.06, 0.02, 0.02), fill(d - 0.0035));
}

void screw_at(inout vec3 col, vec2 p, vec2 c, float ang, float r) {
	vec2 q = p - c;
	float d = length(q);
	if (d > r + 0.02) {
		return;
	}
	col *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.006, length(q - SO * 0.5) - r));
	vec3 head = blued.rgb * (0.65 + 0.7 * pow(abs(cos(atan(q.y, q.x) - light_angle())), 4.0) * shine);
	head = mix(head, blued.rgb * 1.6 + 0.1, smoothstep(-2.5, -0.5, (d - r) * size.y) * 0.6);
	col = mix(col, head, fill(d - r));
	vec2 s = vec2(dot(q, dir(ang)), dot(q, dir(ang + PI * 0.5)));
	col = mix(col, vec3(0.03, 0.04, 0.08), fill(max(abs(s.y) - r * 0.14, abs(s.x) - r * 0.92)) * fill(d - r));
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = UV * vec2(aspect, 1.0);
	// The train: each arbor where its pinion meets the wheel before it.
	float r0 = M * 36.0;
	float r1p = M * 9.0;
	float r1 = M * 30.0;
	float r2p = M * 10.0;
	float r2 = M * 27.0;
	float r3p = M * 9.0;
	float r3 = M * 22.5;
	float r4p = M * 7.5;
	float f01 = -0.35;
	float f12 = -1.31;
	float f23 = 0.26;
	float f34 = -0.44;
	vec2 a0 = vec2(0.36, 0.74);
	vec2 a1 = a0 + (r0 + r1p) * dir(f01);
	vec2 a2 = a1 + (r1 + r2p) * dir(f12);
	vec2 a3 = a2 + (r2 + r3p) * dir(f23);
	vec2 a4 = a3 + (r3 + r4p) * dir(f34);
	vec2 bal = vec2(1.48, 0.6);
	// The escape wheel's turn: the music's clock, and half a tooth on every beat (a quick step as the beat fades).
	float tick = beats - pow(beat, 3.0);
	float e = drive * speed * 1.2 + tick * PI / 15.0;
	// Back along the train (each wheel drives the next one's pinion; the teeth meet at the line between centres).
	float t0 = e / 108.0;
	float t1 = f01 + PI + ((f01 - t0) * 72.0 / TAU - 0.5) * TAU / 18.0;
	float t2 = f12 + PI + ((f12 - t1) * 60.0 / TAU - 0.5) * TAU / 20.0;
	float t3 = f23 + PI + ((f23 - t2) * 54.0 / TAU - 0.5) * TAU / 18.0;
	float t4 = f34 + PI + ((f34 - t3) * 45.0 / TAU - 0.5) * TAU / 15.0;

	vec3 col = plate_colour(p);
	gear(col, p, a0, t0, 72.0, r0, 0);
	gear(col, p, a1, t1, 18.0, r1p, 1);
	gear(col, p, a1, t1, 60.0, r1, 0);
	gear(col, p, a2, t2, 20.0, r2p, 1);
	gear(col, p, a2, t2, 54.0, r2, 0);
	gear(col, p, a3, t3, 18.0, r3p, 1);
	gear(col, p, a3, t3, 45.0, r3, 0);
	gear(col, p, a4, t4, 15.0, r4p, 1);
	gear(col, p, a4, t4, 15.0, 0.1, 2);

	// The pallet lever: it rocks to the other side on each beat.
	vec2 to_bal = normalize(bal - a4);
	vec2 piv = a4 + to_bal * 0.15;
	float side = mod(beats, 2.0) < 1.0 ? 1.0 : -1.0;
	float lam = side * 0.09 * (1.0 - 2.0 * pow(beat, 3.0));
	float la = atan(to_bal.y, to_bal.x) + lam;
	vec2 fork = piv + dir(la) * (length(bal - piv) - 0.04);
	vec2 arm1 = piv + dir(la + PI - 0.62) * 0.095;
	vec2 arm2 = piv + dir(la + PI + 0.62) * 0.095;
	if (length(p - piv) < 0.34) {
		float lev = capsule(p, piv, fork, 0.008, 0.005);
		lev = min(lev, capsule(p, piv, arm1, 0.008, 0.006));
		lev = min(lev, capsule(p, piv, arm2, 0.008, 0.006));
		lev = min(lev, capsule(p, fork, fork + dir(la + 0.5) * 0.02, 0.004, 0.003));
		lev = min(lev, capsule(p, fork, fork + dir(la - 0.5) * 0.02, 0.004, 0.003));
		lev = min(lev, length(p - piv) - 0.016);
		col *= 1.0 - 0.45 * (1.0 - smoothstep(-0.004, 0.008, capsule(p - SO, piv, fork, 0.008, 0.005)));
		col = mix(col, metal(steel.rgb, p - piv, la, lev), fill(lev));
		float pal = min(capsule(p, arm1, arm1 + dir(la + PI - 0.3) * 0.022, 0.005, 0.005),
				capsule(p, arm2, arm2 + dir(la + PI + 0.3) * 0.022, 0.005, 0.005));
		col = mix(col, jewel.rgb * (0.8 + 0.5 * beat), fill(pal));
	}

	// The balance: a gold rim with timing screws, three arms, swinging; the hairspring breathing in the middle.
	vec2 qb = p - bal;
	float lb = length(qb);
	col *= disc_shadow(p, bal, 0.185);
	if (lb < 0.2) {
		float amp = (0.5 + 2.2 * swing * (0.25 + level)) * 0.6;
		float beta = amp * sin(vis_time * TAU * 0.9);
		float rim = abs(lb - 0.165) - 0.009;
		float ab = atan(qb.y, qb.x) - beta;
		float st = TAU / 3.0;
		float arms = max(abs(sin(mod(ab, st) - st * 0.5)) * lb - 0.006, lb - 0.165);
		float roller = lb - 0.03;
		float bd = min(min(rim, arms), roller);
		col = mix(col, metal(gold.rgb, qb, beta, bd), fill(bd));
		if (abs(lb - 0.178) < 0.012) {
			// The nearest of twelve timing screws, gold and steel in turn.
			float si = floor((ab - 0.26) / (TAU / 12.0) + 0.5);
			vec2 sc = bal + dir(si * TAU / 12.0 + beta + 0.26) * 0.178;
			float sd = length(p - sc) - 0.0085;
			col = mix(col, metal(mod(si, 2.0) < 1.0 ? gold.rgb * 1.1 : steel.rgb, p - sc, 0.0, sd), fill(sd));
		}
		// Hairspring: an Archimedean spiral that winds and unwinds with the swing.
		float hs0 = 0.034;
		float hs1 = 0.118;
		if (lb > hs0 && lb < hs1) {
			float b = (hs1 - hs0) / (8.0 * TAU);
			float phi = atan(qb.y, qb.x) - beta * (1.0 - (lb - hs0) / (hs1 - hs0));
			float k = (lb - hs0) / (TAU * b) - phi / TAU;
			float hd = abs(fract(k) - 0.5) * TAU * b;
			vec3 hc = blued.rgb * (0.8 + 0.8 * pow(abs(cos(atan(qb.y, qb.x) - light_angle())), 8.0));
			col = mix(col, hc, fill_px(hd * size.y - 0.7));
		}
	}

	// Bridges over it all: a striped finish, polished bevels to the light, their shadows on the train.
	float bd0 = bridges(p, a0, a1, a2, a3, a4, piv, bal);
	float bs = bridges(p - SO * 1.4, a0, a1, a2, a3, a4, piv, bal);
	vec2 g = vec2(dFdx(bd0), dFdy(bd0));
	col *= 1.0 - 0.55 * (1.0 - smoothstep(-0.006, 0.012, bs));
	if (bd0 < 0.004) {
		vec2 nrm = normalize(g + 1e-7);
		vec2 sv = vec2(cos(-0.55), sin(-0.55));
		float v = dot(p, sv) / 0.05;
		float f = fract(v);
		float stripe = 0.72 + 0.3 * smoothstep(0.0, 0.85, f) * (1.0 - smoothstep(0.85, 1.0, f))
				+ 0.05 * sin(length(p - (floor(v) + 0.5) * 0.05 * sv - vec2(0.0, 0.4)) * 600.0);
		vec3 bc = plate.rgb * stripe;
		float bevel = smoothstep(-0.007 * size.y, -0.003 * size.y, bd0 * size.y);
		float facing = dot(nrm, dir(light_angle()));
		bc = mix(bc, plate.rgb * (0.55 + 0.9 * max(facing, 0.0)) + 0.08 * shine, bevel);
		col = mix(col, bc, fill(bd0));
		// Jewels, each glowing with its part of the spectrum, and the screws.
		jewel_at(col, p, a1, band(0.1));
		jewel_at(col, p, a2, band(0.3));
		jewel_at(col, p, a3, band(0.5));
		jewel_at(col, p, a4, band(0.7));
		jewel_at(col, p, piv, band(0.85));
		jewel_at(col, p, bal, band(0.95));
		screw_at(col, p, a2 + vec2(-0.063, -0.169), 0.4, 0.016);
		screw_at(col, p, a4 + vec2(-0.01, -0.13), 2.0, 0.016);
		screw_at(col, p, bal + vec2(0.17, 0.13), 2.6, 0.016);
		screw_at(col, p, vec2(0.08, 0.6), 0.2, 0.016);
		screw_at(col, p, piv + vec2(0.1, -0.07), 1.7, 0.014);
	}
	// The ratchet wheel on the barrel bridge, turning with the barrel, and its big screw.
	gear(col, p, a0, t0, 40.0, 0.135, 3);
	screw_at(col, p, a0, t0 + 0.5, 0.034);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
