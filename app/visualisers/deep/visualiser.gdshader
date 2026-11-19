// Deep sea (visualiser.json): jellyfish drifting through dark water, lit by their own light. Each bell is a thin glassy
// shell (brighter where you look through more of it, at the edge), with its canals running down like meridians, four
// horseshoe gonads and a ring of lights round the margin; tentacles trail and sway below, frilled mouth arms hang in
// the middle. Each jellyfish pulls in its bell with its own part of the spectrum (a fast stroke on a hit, a slow
// relaxing after, as they swim), and each light on its margin glows with a band of its own. Marine snow sinks past in
// three depths; small plankton glints with the high notes. The current carries them on the music's clock (drive),
// the near ones faster. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float pulse = 0.6;
uniform float speed = 0.5;
uniform float snow = 0.5;
uniform float reach = 0.6;
uniform vec4 glow_a : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform vec4 glow_b : source_color = vec4(1.0, 0.35, 0.8, 1.0);
uniform vec4 water : source_color = vec4(0.02, 0.09, 0.17, 1.0);

const int JELLIES = 8;
const int TENTACLES = 10;


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

// The water: lighter towards the far surface, faint moving light from above, marine snow, plankton.
vec3 water_at(vec2 p, float aspect) {
	vec3 c = water.rgb * (0.3 + 0.95 * p.y * p.y);
	float shafts = noise2(vec2(p.x * 3.0 + p.y * 0.9, vis_time * 0.05));
	c += water.rgb * 1.2 * shafts * shafts * smoothstep(0.35, 1.0, p.y);
	for (int l = 0; l < 3; l++) {
		float fl = float(l);
		float cell = mix(0.03, 0.1, fl * 0.5);
		vec2 sp = p + vec2(0.0, vis_time * (0.006 + 0.006 * fl) * (0.6 + speed));
		sp.x += 0.012 * sin(sp.y * 6.0 + fl * 2.0 + vis_time * 0.2);
		vec2 ci = floor(sp / cell);
		vec2 f = fract(sp / cell) - 0.5;
		vec3 h = hash3(ci, 11.0 + fl);
		if (h.x < snow * (0.75 - fl * 0.15)) {
			vec2 o = (h.yz - 0.5) * 0.3;
			float r = mix(0.04, 0.12, fl * 0.5) * (0.5 + h.y);
			float blur = mix(0.03, 0.14, fl * 0.5);
			float dd = length(f - o);
			float a = smoothstep(r + blur, r - blur * 0.3, dd);
			c += vec3(0.55, 0.65, 0.7) * a * mix(0.1, 0.06, fl * 0.5) * (0.4 + 0.6 * p.y);
		}
	}
	// Plankton near the bottom, glinting with the high notes.
	vec2 pc = p / 0.022;
	vec2 pi = floor(pc);
	vec3 ph = hash3(pi, 21.0);
	if (ph.x < 0.25) {
		vec2 o = (ph.yz - 0.5) * 0.7;
		float tw = smoothstep(0.55, 1.0, sin(vis_time * (0.8 + ph.y) + ph.z * TAU));
		float g = exp(-dot(fract(pc) - 0.5 - o, fract(pc) - 0.5 - o) * 120.0);
		c += mix(glow_a.rgb, vec3(0.6, 1.0, 0.8), 0.5) * g * tw * treble * 0.9 * smoothstep(0.55, 0.05, p.y);
	}
	return c;
}

void jelly(inout vec3 col, vec2 p, int i, float aspect) {
	float fi = float(i);
	float z = 1.0 - fi / float(JELLIES - 1);
	float s = mix(0.16, 0.055, z);
	float tl = 2.0 + 4.0 * reach;
	vec3 h = vec3(fract(0.17 + fi * 0.382), fract(0.31 + fi * 0.618), fract(0.6 + fi * 0.45));
	// Carried across by the current (the near ones faster), each at its own depth, bobbing slowly.
	float pad = 2.2 * s + 0.05;
	float cx = -pad + fract(h.y + drive * speed * mix(0.03, 0.012, z)) * (aspect + 2.0 * pad);
	float cy = mix(0.4, 0.86, h.x) + 0.07 * sin(vis_time * 0.11 + fi * 2.3);
	float tilt = -0.18 + 0.2 * sin(vis_time * 0.13 + fi * 1.7);
	vec2 d = p - vec2(cx, cy);
	float ca = cos(tilt);
	float sa = sin(tilt);
	vec2 q = vec2(ca * d.x + sa * d.y, -sa * d.x + ca * d.y) / s;

	float bx = 0.05 + fi * 0.14;
	float my = clamp(band(bx) * 1.25 - 0.1, 0.0, 1.0);
	float c = clamp(pulse * my + 0.12 * (0.5 + 0.5 * sin(vis_time * 1.2 + fi * 2.1)), 0.0, 1.0);
	float w = 1.0 - 0.24 * c;
	float hh = 0.8 + 0.22 * c;
	vec3 jc = mix(glow_a.rgb, glow_b.rgb, h.z);
	vec3 gc = mix(glow_b.rgb, glow_a.rgb, h.z * 0.7);
	float fogk = mix(1.0, 0.3, z);
	float lift = 0.75 + 0.5 * my;

	// The glow it throws into the water round it.
	float hd = length(q - vec2(0.0, 0.3));
	col += jc * 0.06 * fogk * lift * exp(-hd * 0.8);
	if (q.y > 1.4 || q.y < -tl - 0.8 || abs(q.x) > 2.0) {
		return;
	}
	float lpx = (1.0 + 2.5 * z) / (s * size.y);
	float spin = vis_time * 0.12 + fi;
	vec3 e = vec3(0.0);
	float a = 0.0;

	// Bell.
	float u = q.x / w;
	float uc = clamp(u, -1.0, 1.0);
	float front = sqrt(max(1.0 - uc * uc, 0.0));
	float rimy = -0.12 * hh * front - 0.035 * abs(sin(uc * PI * 4.0));
	float ev = length(vec2(u, q.y / hh));
	float sd = max((ev - 1.0) * min(w, hh), rimy - q.y);
	float inb = smoothstep(lpx, -lpx, sd);
	if (inb > 0.0) {
		float cosv = sqrt(max(1.0 - ev * ev, 0.0));
		float shell = 0.14 / max(cosv, 0.14);
		float cap = smoothstep(0.35, 0.95, q.y / hh) * 0.35;
		e += jc * (0.13 + 0.75 * shell + cap) * inb;
		e += mix(jc, vec3(1.0), 0.3) * 0.5 * smoothstep(0.05, 0.0, abs(q.y - rimy - 0.02)) * inb;
		// Under the bell, the inner surface.
		float inner = length(vec2(u / 0.82, (q.y + 0.05) / (hh * 0.72)));
		e += jc * 0.18 * smoothstep(0.08, 0.0, abs(inner - 1.0)) * step(q.y, 0.55 * hh) * inb;
		// Canals: meridians on the front and, dimmer, on the back.
		float yy = clamp(q.y / hh, -1.0, 0.98);
		float rr = sqrt(max(1.0 - yy * yy, 1e-3)) * w;
		float phi = asin(clamp(q.x / rr, -1.0, 1.0));
		float step_m = PI / 4.0;
		for (int side = 0; side < 2; side++) {
			float ph = side == 0 ? phi : PI - phi;
			float m = (ph - spin) / step_m;
			float dm = abs(fract(m + 0.5) - 0.5) * step_m;
			float xd = dm * rr * abs(cos(phi));
			float ln = exp(-pow(xd / (1.6 * lpx + 0.012), 2.0));
			e += jc * ln * (side == 0 ? 0.5 : 0.2) * smoothstep(0.92, 0.6, yy) * inb;
		}
		// Four horseshoe gonads round the top.
		float ry = sqrt(1.0 - 0.45 * 0.45) * w;
		for (int k = 0; k < 4; k++) {
			float gp = PI * 0.25 + float(k) * PI * 0.5 + spin;
			float cg = cos(gp);
			vec2 gcen = vec2(sin(gp) * ry * 0.9, 0.45 * hh);
			vec2 gq = (q - gcen) / vec2(max(abs(cg), 0.12) * 0.24, 0.2 * hh);
			float gr = length(gq);
			float horse = smoothstep(0.32, 0.0, abs(gr - 1.0)) * smoothstep(-0.7, -0.2, gq.y);
			e += gc * horse * (cg > 0.0 ? 0.9 : 0.35) * inb;
		}
		a = max(a, inb * 0.5);
	}
	// Lights round the margin, each with its own band.
	float mstep = TAU / 16.0;
	for (int side = 0; side < 2; side++) {
		if (abs(q.y + 0.06) > 0.3 || abs(q.x) > 1.3) {
			break;
		}
		float ph = asin(uc);
		ph = side == 0 ? ph : PI - ph;
		float j = floor((ph - spin) / mstep + 0.5);
		float pj = j * mstep + spin;
		vec2 mp = vec2(w * sin(pj), -0.12 * hh * cos(pj) - 0.02);
		float dl = length(q - mp);
		float lb = band(0.25 + 0.7 * fract(j / 16.0 + fi * 0.3));
		e += mix(gc, vec3(1.0), 0.3) * exp(-dl * dl / (0.0025 + lpx * lpx)) * (0.3 + 1.6 * lb) * (cos(pj) > 0.0 ? 1.0 : 0.45);
	}
	// Tentacles.
	float tlen = tl * (1.0 - 0.2 * c);
	// Each tentacle's place round the margin, turned on from the last (no sin and cos per tentacle).
	float tstep = TAU / float(TENTACLES);
	vec2 tcs = vec2(cos(0.5 * tstep + spin), sin(0.5 * tstep + spin));
	vec2 trot = vec2(cos(tstep), sin(tstep));
	float sway_t = vis_time * 1.4 * (0.5 + speed);
	float tilt_x = 0.3 * sin(tilt);
	for (int t = 0; t < TENTACLES; t++) {
		float pt = (float(t) + 0.5) * tstep + spin;
		vec2 cs = tcs;
		tcs = vec2(cs.x * trot.x - cs.y * trot.y, cs.y * trot.x + cs.x * trot.y);
		float x0 = w * 0.95 * cs.y;
		float ty = -0.12 * hh * cs.x - 0.03;
		float tt = (ty - q.y) / tlen;
		if (tt < 0.0 || tt > 1.0 || abs(q.x - x0) > 1.1) {
			continue;
		}
		float sway = (0.2 + 0.7 * tt) * tt * sin(tt * 7.0 - sway_t + pt * 2.0) * 0.55;
		float x = x0 * (1.0 + 0.25 * tt) + sway + tilt_x * tt * tt;
		float wd = 0.012 * (1.0 - 0.6 * tt) + lpx * 0.8;
		float dx = abs(q.x - x);
		float ln = smoothstep(wd + lpx, wd - lpx, dx) + 0.25 * exp(-dx / (wd * 3.0));
		e += jc * ln * pow(1.0 - tt, 1.3) * (cs.x > 0.0 ? 1.0 : 0.45);
	}
	// Frilled mouth arms.
	float alen = tlen * 0.55;
	for (int k = 0; k < 4; k++) {
		float fk = float(k);
		float tt = (-0.05 * hh - q.y) / alen;
		if (tt < 0.0 || tt > 1.0) {
			continue;
		}
		float x = (fk - 1.5) * 0.16 * w * (1.0 - 0.4 * tt) + 0.25 * tt * sin(tt * 4.0 - vis_time * 0.7 + fk * 1.7);
		float wd = (0.09 - 0.05 * tt) * (1.0 + 0.4 * sin(tt * 60.0 + fk * 3.0 + vis_time));
		float dx = abs(q.x - x);
		float arm = smoothstep(wd + lpx, wd - lpx, dx);
		float edge = pow(clamp(dx / max(wd, 1e-3), 0.0, 1.0), 3.0);
		float lace = 0.3 + 0.7 * edge + 0.2 * sin(q.y * 23.0 + q.x * 31.0 + fk * 2.0) * sin(q.y * 9.0 - fk);
		e += mix(jc, vec3(1.0), 0.25) * arm * lace * 0.4 * (1.0 - tt);
		a = max(a, arm * 0.3);
	}
	col = col * (1.0 - a * 0.4) + e * fogk * lift + water.rgb * a * (1.0 - fogk) * 0.6;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	vec3 col = water_at(p, aspect);
	for (int i = 0; i < JELLIES; i++) {
		jelly(col, p, i, aspect);
	}
	col *= 1.0 - 0.35 * pow(length(UV - 0.5) * 1.3, 2.0);
	col = col / (1.0 + col * 0.35);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
