// Cymatics (visualiser.json): Chladni plates. A square metal plate and a round one, bolted at the middle and shaken
// from below, lie under a lamp on dark cloth; sand on them gathers on the lines that stand still (the nodes of the
// plate's vibration) in ridges of single grains. The plates step through their modes on the music's clock (drive):
// as one gives way to the next the lines slide and blur and settle into the new figure, sharper the louder it is.
// The bass shakes the plates: the lamp's reflection ripples in the shape of the mode, and sand hangs as a haze over
// the parts that move most. The round plate goes with the high notes. A signal generator shows each mode's tone.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float speed = 0.5;
uniform float shake = 0.6;
uniform float grain_size = 0.5;
uniform vec4 plate : source_color = vec4(0.11, 0.115, 0.13, 1.0);
uniform vec4 sand_colour : source_color = vec4(0.91, 0.86, 0.75, 1.0);
uniform vec4 cloth : source_color = vec4(0.09, 0.05, 0.06, 1.0);
uniform vec4 display : source_color = vec4(1.0, 0.65, 0.2, 1.0);

const vec2 LIGHT2 = vec2(-0.55, 0.83);
const vec3 LIGHT3 = vec3(-0.45, 0.55, 0.7);


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

float box(vec2 p, vec2 half_size, float r) {
	vec2 d = abs(p) - half_size + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

// Mode k of the square plate: n, m and the sign that joins the two halves.
vec3 square_kind(float k) {
	vec3 h = hash3(vec2(k, 17.0), 9.0);
	float n = 1.0 + floor(h.x * 4.0);
	float m = n + 1.0 + floor(h.y * 4.0);
	return vec3(n, m, h.z < 0.5 ? -1.0 : 1.0);
}

// The field of a square plate with free edges, at w (-1..1 over the plate): value and gradient (per unit of w).
vec3 square_mode(vec2 w, vec3 kind) {
	vec2 x = w * 0.5 + 0.5;
	float a = PI * kind.x;
	float b = PI * kind.y;
	float sg = kind.z;
	float f = cos(a * x.x) * cos(b * x.y) + sg * cos(b * x.x) * cos(a * x.y);
	float fx = -a * sin(a * x.x) * cos(b * x.y) - sg * b * sin(b * x.x) * cos(a * x.y);
	float fy = -b * cos(a * x.x) * sin(b * x.y) - sg * a * cos(b * x.x) * sin(a * x.y);
	return vec3(f, fx * 0.5, fy * 0.5);
}

vec3 round_kind(float k) {
	vec3 h = hash3(vec2(k, 29.0), 9.0);
	return vec3(1.0 + floor(h.x * 4.0), 1.5 + floor(h.y * 3.0), h.z * TAU);
}

// A round plate: diameters and circles that stand still.
vec3 round_mode(vec2 w, vec3 kind) {
	float r = max(length(w), 1e-3);
	float th = atan(w.y, w.x);
	float A = cos(kind.x * (th - kind.z));
	float B = cos(PI * kind.y * r);
	float dr = -A * PI * kind.y * sin(PI * kind.y * r);
	float dt = -kind.x * sin(kind.x * (th - kind.z)) * B / max(r, 0.08);
	vec2 rh = w / r;
	vec2 th_hat = vec2(-rh.y, rh.x);
	return vec3(A * B, dr * rh + dt * th_hat);
}

// Sand and plate at plate point w. fg: the field and its gradient; spread 0 settled .. 1 in between modes.
vec3 shade_plate(vec2 w, vec3 fg, float spread, float ppx, float salt, float vib, float fmax) {
	// The metal: brushed, with the lamp's reflection rippling as the plate moves.
	float brush = noise2(vec2(w.x * 6.0, w.y * 260.0 + salt)) * 0.5 + noise2(vec2(w.x * 2.0, w.y * 40.0)) * 0.5;
	vec3 col = plate.rgb * (0.75 + 0.4 * brush);
	vec2 rw = w + fg.yz * vib;
	float hl = exp(-pow((dot(rw, normalize(vec2(1.0, -0.8))) + 0.25) / 0.32, 2.0));
	hl *= smoothstep(1.3, 0.2, abs(dot(rw, normalize(vec2(0.8, 1.0))) - 0.1));
	col += vec3(1.0, 0.95, 0.85) * hl * (0.18 + 0.12 * brush);
	// Sand.
	float gl = length(fg.yz) + 0.6;
	float dn = abs(fg.x) / gl;
	float crisp = clamp(level * 1.3, 0.0, 1.0);
	float width = mix(0.022, 0.06, spread) * (1.2 - 0.35 * crisp);
	float u = dn / width;
	float dens = exp(-u * u) * (1.0 - 0.6 * spread) + 0.035;
	float H = exp(-u * u * 1.6) * (1.0 - 0.5 * spread);
	vec2 dH = H * (-3.2 * fg.x / (gl * gl * width * width)) * fg.yz;
	float ridge = clamp(1.0 + 0.01 * dot(dH, LIGHT2), 0.45, 1.5);
	col = mix(col, sand_colour.rgb * 0.62 * ridge, H * 0.75);
	// Single grains, each a small lit ball with a shadow.
	float G = mix(0.01, 0.019, grain_size);
	vec2 gc = w / G;
	gc.x += 0.5 * mod(floor(gc.y), 2.0);
	vec2 ci = floor(gc);
	vec3 h = hash3(ci, salt);
	if (h.x < dens * 1.1) {
		float r = 0.22 + 0.14 * fract(h.y * 7.0);
		vec2 o = (h.yz - 0.5) * 2.0 * (0.44 - r);
		vec2 d = fract(gc) - 0.5 - o;
		float dd = length(d);
		float aa = ppx / G;
		float cov = smoothstep(r + aa, r - aa, dd);
		float shadow = smoothstep(r + aa, r - aa * 2.0, length(d - vec2(0.18, -0.2)));
		col *= 1.0 - 0.45 * shadow * (1.0 - cov);
		vec3 n = vec3(d / r, sqrt(max(1.0 - dd * dd / (r * r), 0.0)));
		float lit = 0.4 + 0.75 * max(dot(n, normalize(LIGHT3)), 0.0) + 0.6 * pow(max(dot(n, normalize(LIGHT3 + vec3(0.0, 0.0, 1.0))), 0.0), 30.0);
		col = mix(col, sand_colour.rgb * lit * mix(0.75, 1.05, h.z) * ridge, cov);
	}
	// Sand thrown up where the plate moves most.
	col += sand_colour.rgb * 0.07 * shake * bass * smoothstep(0.3, 1.0, abs(fg.x) / fmax);
	return col;
}

// Seven segments: bit 0 a (top), 1 b, 2 c, 3 d, 4 e, 5 f, 6 g (middle). q 0..1 over a digit 0.6 wide.
float seven(vec2 q, int digit) {
	int bits = 0;
	if (digit == 0) bits = 63;
	else if (digit == 1) bits = 6;
	else if (digit == 2) bits = 91;
	else if (digit == 3) bits = 79;
	else if (digit == 4) bits = 102;
	else if (digit == 5) bits = 109;
	else if (digit == 6) bits = 125;
	else if (digit == 7) bits = 7;
	else if (digit == 8) bits = 127;
	else if (digit == 9) bits = 111;
	q.x -= (q.y - 0.5) * 0.12;
	float lit = 0.0;
	float off = 0.0;
	for (int s = 0; s < 7; s++) {
		vec2 a;
		vec2 b;
		if (s == 0) { a = vec2(0.1, 1.0); b = vec2(0.5, 1.0); }
		else if (s == 1) { a = vec2(0.6, 0.92); b = vec2(0.6, 0.58); }
		else if (s == 2) { a = vec2(0.6, 0.42); b = vec2(0.6, 0.08); }
		else if (s == 3) { a = vec2(0.1, 0.0); b = vec2(0.5, 0.0); }
		else if (s == 4) { a = vec2(0.0, 0.42); b = vec2(0.0, 0.08); }
		else if (s == 5) { a = vec2(0.0, 0.92); b = vec2(0.0, 0.58); }
		else { a = vec2(0.1, 0.5); b = vec2(0.5, 0.5); }
		vec2 pa = q - a;
		vec2 ba = b - a;
		float d = length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
		float on = smoothstep(0.075, 0.045, d);
		if (((bits >> s) & 1) == 1) {
			lit = max(lit, on);
		} else {
			off = max(off, on);
		}
	}
	return lit + off * 0.08;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;

	// Cloth: soft folds, lit from the lamp above.
	float folds = noise2(vec2(p.x * 2.5 + p.y * 0.8, p.y * 1.2)) * 0.6 + noise2(p * vec2(7.0, 3.0)) * 0.25;
	vec3 col = cloth.rgb * (0.55 + 0.8 * folds) * (0.5 + 0.8 * exp(-pow(length(p - vec2(aspect * 0.55, 0.65)) * 1.1, 2.0)));
	col += cloth.rgb * 0.3 * noise2(p * 300.0);

	// Modes: the square plate on the beat of the clock, the round one a little out of step.
	float mt = drive * speed * 0.09;
	float k = floor(mt);
	float blend = smoothstep(0.62, 1.0, fract(mt));
	float spread = 4.0 * blend * (1.0 - blend) * 0.9 + 0.1 * (1.0 - clamp(level * 2.0, 0.0, 1.0));
	vec3 kind_a = square_kind(k);
	vec3 kind_b = square_kind(k + 1.0);
	float rt = drive * speed * 0.07 + 0.45;
	float rk = floor(rt);
	float rblend = smoothstep(0.62, 1.0, fract(rt));
	float rspread = 4.0 * rblend * (1.0 - rblend) * 0.9 + 0.1 * (1.0 - clamp(treble * 3.0, 0.0, 1.0));
	vec3 rkind_a = round_kind(rk);
	vec3 rkind_b = round_kind(rk + 1.0);

	// The square plate, seen from above and in front.
	vec2 sc = vec2(aspect * 0.57, 0.53);
	float S = 0.33;
	float persp = 0.15;
	float squash = 0.8;
	{
		// Its shadow on the cloth.
		vec2 sp = p - vec2(0.025, -0.035);
		float sa = (sp.x - sc.x) / S;
		float sb = (sp.y - sc.y) / (S * squash);
		float sv = sb / (1.0 - persp * sb);
		float su = sa * (1.0 + persp * sv);
		float sd = box(vec2(su, sv), vec2(1.0), 0.04);
		col *= 1.0 - 0.7 * smoothstep(0.12, -0.08, sd);
	}
	float a = (p.x - sc.x) / S;
	float b = (p.y - sc.y) / (S * squash);
	float v = b / (1.0 - persp * b);
	float u = a * (1.0 + persp * v);
	vec2 w = vec2(u, v);
	float ppx = px / S * (1.0 + persp * v);
	float sd = box(w, vec2(1.0), 0.04);
	// The front edge of the plate (its thickness).
	float front_y = sc.y - S * squash / (1.0 + persp);
	float fu = (p.x - sc.x) / S * (1.0 - persp);
	if (p.y < front_y && p.y > front_y - 0.012 && abs(fu) < 0.97) {
		col = plate.rgb * 0.55 + vec3(0.25) * smoothstep(0.004, 0.0, front_y - p.y);
	}
	if (sd < ppx * 2.0) {
		vec3 fa = square_mode(w, kind_a);
		vec3 fb = square_mode(w, kind_b);
		vec3 fg = mix(fa, fb, blend);
		float vib = sin(vis_time * 7.0) * bass * shake * 0.012;
		vec3 pc = shade_plate(w, fg, spread, ppx, 1.0, vib, 2.0);
		// Rim and the bolt at the middle.
		pc += vec3(0.35) * smoothstep(ppx * 3.0, 0.0, abs(sd + ppx * 2.0)) * (0.5 + 0.5 * dot(normalize(w + 1e-4), LIGHT2));
		float bolt = length(w);
		float hexd = max(abs(w.x) * 0.866 + abs(w.y) * 0.5, abs(w.y)) - 0.07;
		if (hexd < 0.0) {
			float facet = 0.6 + 0.35 * dot(normalize(w + 1e-4), LIGHT2);
			pc = mix(pc, vec3(0.62, 0.6, 0.56) * facet, smoothstep(ppx, -ppx, hexd));
			pc = mix(pc, vec3(0.3), smoothstep(0.04 + ppx, 0.04 - ppx, bolt));
			pc += vec3(0.6) * smoothstep(0.012, 0.0, abs(bolt - 0.03)) * 0.3;
		}
		col = mix(col, pc, smoothstep(ppx, -ppx, sd));
	}

	// The round plate, to the left.
	vec2 rc = vec2(aspect * 0.2, 0.42);
	float R = 0.25;
	{
		vec2 sp = p - vec2(0.02, -0.03);
		vec2 sq = vec2((sp.x - rc.x) / R, (sp.y - rc.y) / (R * squash));
		col *= 1.0 - 0.65 * smoothstep(1.12, 0.92, length(sq));
	}
	vec2 rq = vec2((p.x - rc.x) / R, (p.y - rc.y) / (R * squash));
	float rl = length(rq);
	float rpx = px / R;
	if (p.y < rc.y && rl > 1.0 && length(vec2(rq.x, rq.y + 0.03 / squash / R * 0.3)) < 1.0 + rpx) {
		col = plate.rgb * 0.5;
	}
	if (rl < 1.0 + rpx * 2.0) {
		vec3 fa = round_mode(rq, rkind_a);
		vec3 fb = round_mode(rq, rkind_b);
		vec3 fg = mix(fa, fb, rblend);
		float vib = sin(vis_time * 9.0) * treble * shake * 0.02;
		vec3 pc = shade_plate(rq, fg, rspread, rpx, 2.0, vib, 1.0);
		pc += vec3(0.35) * smoothstep(rpx * 3.0, 0.0, abs(rl - 1.0 + rpx * 2.0)) * (0.5 + 0.5 * dot(rq / max(rl, 1e-3), LIGHT2));
		float hexd = max(abs(rq.x) * 0.866 + abs(rq.y) * 0.5, abs(rq.y)) - 0.08;
		if (hexd < 0.0) {
			pc = mix(pc, vec3(0.62, 0.6, 0.56) * (0.6 + 0.35 * dot(normalize(rq + 1e-4), LIGHT2)), smoothstep(rpx, -rpx, hexd));
			pc = mix(pc, vec3(0.3), smoothstep(0.045 + rpx, 0.045 - rpx, length(rq)));
		}
		col = mix(col, pc, smoothstep(1.0 + rpx, 1.0 - rpx, rl));
	}

	// The signal generator, bottom right: a dark box, four amber digits (the tone in Hz), a knob.
	vec2 gc = vec2(aspect - 0.2, 0.26);
	vec2 gq = p - gc;
	float gbox = box(gq, vec2(0.17, 0.065), 0.01);
	col *= 1.0 - 0.6 * smoothstep(0.04, -0.01, box(gq - vec2(0.012, -0.015), vec2(0.17, 0.065), 0.01));
	if (gbox < px) {
		vec3 bc = vec3(0.13, 0.13, 0.14) * (0.8 + 0.3 * smoothstep(-0.065, 0.065, gq.y));
		bc += vec3(0.25) * smoothstep(px * 2.0, 0.0, abs(gbox + px * 2.0));
		vec2 wq = gq - vec2(-0.045, 0.0);
		float win = box(wq, vec2(0.105, 0.042), 0.006);
		vec3 kind = blend < 0.5 ? kind_a : kind_b;
		int hz = int(floor(27.5 * (kind.x * kind.x + kind.y * kind.y) + (kind.z > 0.0 ? 0.0 : 11.0)));
		if (win < 0.0) {
			bc = vec3(0.04, 0.03, 0.025);
			float dw = 0.044;
			float slot = floor((wq.x + 0.1) / dw);
			if (slot >= 0.0 && slot < 4.0) {
				int place = 3 - int(slot);
				int pw = place == 0 ? 1 : place == 1 ? 10 : place == 2 ? 100 : 1000;
				int digit = (hz / pw) % 10;
				vec2 dq = vec2((wq.x + 0.1 - slot * dw) / 0.03 - 0.12, (wq.y + 0.026) / 0.052);
				float seg = (hz >= pw || place == 0) ? seven(dq, digit) : seven(dq, 8) * 0.0;
				if (hz < pw && place > 0) {
					seg = seven(dq, 8) * 0.08;
				}
				bc += display.rgb * seg * 0.95;
				bc += display.rgb * 0.06 * exp(-abs(wq.y) * 30.0);
			}
		}
		bc *= 1.0 - 0.5 * smoothstep(0.004, -0.002, win) * step(0.0, win);
		// The knob.
		vec2 kq = gq - vec2(0.115, 0.0);
		float kl = length(kq);
		if (kl < 0.042) {
			float ang = atan(kq.y, kq.x);
			vec3 kc = vec3(0.32, 0.32, 0.34) * (0.7 + 0.4 * dot(kq / max(kl, 1e-4), LIGHT2) * smoothstep(0.03, 0.042, kl));
			kc *= 0.85 + 0.15 * step(0.5, fract(ang / TAU * 40.0)) * smoothstep(0.03, 0.034, kl);
			float pointer = blend < 0.5 ? kind_a.x + kind_a.y : kind_b.x + kind_b.y;
			float pa = 3.9 - pointer * 0.45;
			vec2 pd = vec2(cos(pa), sin(pa));
			float pl = length(kq - pd * clamp(dot(kq, pd), 0.0, 0.028));
			kc = mix(kc, vec3(0.9), smoothstep(0.004, 0.002, pl));
			bc = mix(bc, kc, smoothstep(0.042, 0.04, kl));
		}
		col = mix(col, bc, smoothstep(px, -px, gbox));
	}

	col *= 1.0 - 0.3 * pow(length(UV - 0.5) * 1.2, 2.0);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
