// Fireworks (visualiser.json): a display over a harbour at night. Shells rise from the water with a spark and a tail
// and burst into peonies (round, short trails), chrysanthemums (long trails that crackle with the high notes at the
// end), gold willows (heavy, drooping, slow to fade) and tilted rings. Each burst is a sphere of stars seen as three
// rings, drifting down as it fades; each shell belongs to a part of the spectrum and swells and brightens with it.
// The bursts light the smoke that hangs over the town and stretch down the rippled water as long reflections. Shells
// go up on the music's clock (drive), so loud music fills the sky. Worked out per pixel from the clocks: no memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float launches = 0.5;
uniform float burst_size = 0.6;
uniform float smoke = 0.5;
uniform vec4 colour_a : source_color = vec4(1.0, 0.24, 0.35, 1.0);
uniform vec4 colour_b : source_color = vec4(0.24, 0.78, 1.0, 1.0);
uniform vec4 colour_c : source_color = vec4(0.7, 1.0, 0.3, 1.0);
uniform vec4 gold : source_color = vec4(1.0, 0.77, 0.34, 1.0);
uniform vec4 night : source_color = vec4(0.04, 0.07, 0.19, 1.0);

const int SHELLS = 12;
const float RISE = 0.55;
const float LIFE = 2.4;
const float HORIZON = 0.27;


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

// Distance to the segment a-b, and in y how far along it (0 at a, 1 at b).
vec2 seg_t(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float t = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-8), 0.0, 1.0);
	return vec2(length(pa - ba * t), t);
}

float clock_now() {
	return drive * mix(0.5, 1.4, launches);
}

float spacing() {
	return 0.33;
}

// Shell k: x 0..1 of the width, burst height, kind (0 peony, 1 chrysanthemum, 2 willow, 3 ring), band.
vec4 shell_of(float k) {
	vec3 h = hash3(vec2(k, 5.0), 13.0);
	float kind = floor(h.z * 4.0);
	return vec4(0.12 + 0.82 * h.x, 0.46 + 0.28 * h.y, kind, fract(k * 0.618 + h.x * 0.13));
}

vec3 shell_colour(float k, float kind) {
	if (kind == 2.0) {
		return gold.rgb;
	}
	float h = fract(k * 0.382 + 0.1);
	return h < 0.34 ? colour_a.rgb : (h < 0.67 ? colour_b.rgb : colour_c.rgb);
}

// How far the stars have flown (0..1 of the burst's size) and how far it has sunk, at burst age t.
float flown(float t, float kind) {
	return 1.0 - exp(-t * (kind == 2.0 ? 2.6 : 3.6));
}

float sunk(float t, float kind) {
	return (kind == 2.0 ? 0.05 : 0.025) * t * t;
}

float fade(float t, float kind) {
	float life = kind == 2.0 ? LIFE : LIFE * 0.75;
	return smoothstep(0.0, 0.05, t) * exp(-t * (kind == 2.0 ? 0.7 : 1.3)) * smoothstep(life, life * 0.55, t);
}

// The town on the far shore: building tops and lit windows.
vec2 town(float x) {
	float cell = floor(x / 0.045);
	vec3 h = hash3(vec2(cell, 1.0), 23.0);
	float hgt = 0.015 + 0.07 * h.x * h.x + (h.y > 0.9 ? 0.07 : 0.0);
	return vec2(hgt, h.z);
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;
	float c = clock_now();
	float dt = spacing();
	float kc = floor(c / dt);
	float sz = mix(0.75, 1.4, burst_size);

	// The sky and the water's base colour.
	float above = p.y - HORIZON;
	vec3 sky = mix(night.rgb * 1.7 + vec3(0.07, 0.035, 0.05), night.rgb * 0.45, smoothstep(0.0, 0.7, above));
	vec3 col = sky;
	if (above > 0.0) {
		vec2 sc = floor(p / 0.012);
		vec3 sh = hash3(sc, 31.0);
		if (sh.x < 0.05) {
			float tw = 0.6 + 0.4 * sin(vis_time * (0.5 + sh.y) + sh.z * 30.0);
			col += vec3(0.8, 0.85, 1.0) * smoothstep(0.25, 0.0, length(fract(p / 0.012) - 0.5 - (sh.yz - 0.5) * 0.4)) * 0.35 * tw * smoothstep(0.05, 0.4, above);
		}
	}

	// One pass over the shells in the air: the light they throw (on the smoke, and as long streaks on the water)
	// and, kept apart to go over the town, the rockets and the stars.
	vec3 glow = vec3(0.0);
	vec3 wglow = vec3(0.0);
	vec3 fx = vec3(0.0);
	float ripple = 0.5;
	vec2 wp = vec2(p.x, 2.0 * HORIZON - p.y);
	if (above < 0.0) {
		ripple = noise2(vec2(p.x * 25.0, p.y * 220.0 + vis_time * 1.2)) * 0.6 + noise2(vec2(p.x * 6.0, p.y * 60.0 - vis_time * 0.6)) * 0.4;
		wp.x += (ripple - 0.5) * 0.03;
	}
	for (int i = 0; i < SHELLS; i++) {
		float k = kc - float(i);
		float age = c - k * dt;
		if (age < 0.0 || age > RISE + LIFE) {
			continue;
		}
		vec4 sh = shell_of(k);
		vec2 bc = vec2(sh.x * aspect, sh.y);
		float kind = sh.z;
		if (age < RISE) {
			float f = age / RISE;
			float ry = mix(HORIZON - 0.01, bc.y, 1.0 - pow(1.0 - f, 2.0));
			vec2 rp = vec2(bc.x, ry);
			if (above < 0.0) {
				wglow += vec3(1.0, 0.8, 0.5) * 0.05 * exp(-length((wp - rp) * vec2(1.0, 0.25)) / 0.02);
				continue;
			}
			glow += vec3(1.0, 0.8, 0.5) * 0.02 * exp(-length(p - rp) / 0.03);
			float ry0 = mix(HORIZON - 0.01, bc.y, 1.0 - pow(1.0 - max(f - 0.12, 0.0), 2.0));
			vec2 tt = seg_t(p, vec2(bc.x + 0.002 * sin(ry * 200.0), ry0), rp);
			fx += vec3(1.0, 0.75, 0.45) * exp(-pow(tt.x / (1.2 * px), 2.0)) * tt.y * 0.6;
			fx += vec3(1.0, 0.9, 0.7) * exp(-pow(length(p - rp) / (2.2 * px), 2.0)) * 1.2;
			continue;
		}
		float tb = age - RISE;
		float b = band(0.04 + sh.w * 0.85);
		vec3 sc = shell_colour(k, kind);
		float I = fade(tb, kind) * (0.6 + 0.9 * b);
		float R = 0.17 * sz * (0.8 + 0.35 * b);
		float f1 = flown(tb, kind);
		vec2 cc = bc - vec2(0.0, sunk(tb, kind));
		if (above < 0.0) {
			vec2 rd = (wp - cc) * vec2(1.0, 0.22);
			wglow += sc * I * exp(-length(rd) / (R * f1 * 0.6 + 0.03)) * 0.35;
			continue;
		}
		vec2 v = p - cc;
		float lv = length(v);
		glow += sc * I * exp(-lv / (R * f1 * 1.4 + 0.05)) * 0.2;
		if (lv > R * 1.2 + 0.03) {
			continue;
		}
		float tau = kind == 0.0 ? 0.12 : (kind == 1.0 ? 0.45 : (kind == 2.0 ? 0.9 : 0.15));
		float t0 = max(tb - tau, 0.0);
		float f0 = flown(t0, kind);
		float drop = sunk(tb, kind) - sunk(t0, kind);
		// White hot at first, its colour after; a flash at the heart as it bursts.
		vec3 hot = mix(vec3(1.0, 0.95, 0.85), sc, smoothstep(0.0, 0.35, tb));
		fx += vec3(1.0, 0.95, 0.85) * exp(-lv / (0.01 + 0.05 * tb)) * exp(-tb * 10.0) * 0.3;
		int rings = kind == 3.0 ? 1 : 3;
		vec2 vv = v;
		if (kind == 3.0) {
			float ta = sh.w * 2.0 - 1.0;
			vv = vec2(cos(ta) * v.x + sin(ta) * v.y, (-sin(ta) * v.x + cos(ta) * v.y) / 0.45);
		}
		for (int j = 0; j < 3; j++) {
			if (j >= rings) {
				break;
			}
			float rf = j == 0 ? 1.0 : (j == 1 ? 0.72 : 0.4);
			float n = j == 0 ? 40.0 : (j == 1 ? 28.0 : 14.0);
			float ph = float(j) * 0.37 + sh.w * 3.0;
			float ang = atan(vv.y, vv.x) / TAU * n - ph;
			float idx = floor(ang + 0.5);
			vec3 sh2 = hash3(vec2(k * 7.0 + float(j), idx), 43.0);
			float th = (idx + ph + (sh2.x - 0.5) * 0.3) * TAU / n;
			vec2 dir = vec2(cos(th), sin(th));
			float rr = R * rf * (0.92 + 0.16 * sh2.y);
			vec2 head = dir * rr * f1;
			vec2 tail = dir * rr * f0 + vec2(0.0, drop);
			vec2 tt = seg_t(vv, tail, head);
			float wpx = kind == 3.0 ? 2.6 * px : 1.5 * px;
			float line = exp(-pow(tt.x / wpx, 2.0)) * mix(0.15, 1.0, pow(tt.y, 1.5));
			float hd = length(vv - head);
			float headg = exp(-pow(hd / (2.4 * px), 2.0)) + 0.25 * exp(-hd / (6.0 * px));
			float crackle = 1.0;
			if (kind == 1.0 && tb > 0.9) {
				crackle = 0.5 + 0.9 * treble * (0.5 + 0.5 * sin(vis_time * 21.0 + idx * 5.3 + float(j) * 2.0));
			}
			fx += hot * (line * 0.8 + headg * 1.2) * I * crackle * (j == 0 ? 1.0 : 0.85);
		}
	}
	if (above > 0.0) {
		vec2 sp = p * vec2(2.2, 4.0) + vec2(vis_time * 0.02, 0.0);
		float sm = noise2(sp) * 0.6 + noise2(sp * 2.3 + 4.0) * 0.4;
		sm = smoothstep(0.3, 0.85, sm) * smoke * smoothstep(0.98, 0.4, p.y);
		col += glow * (0.5 + 2.6 * sm) + vec3(0.05, 0.05, 0.07) * sm * 0.7;
	} else {
		// Water: the sky darker, reflections broken by the ripples.
		col = mix(sky, night.rgb * 0.3, smoothstep(0.0, -0.2, above)) * 0.8;
		col += wglow * (0.4 + 1.2 * ripple) * smoothstep(-0.27, 0.0, above);
		// Lights of the town and the quay, stretched down the water in broken streaks.
		float qx = p.x + (ripple - 0.5) * 0.01;
		vec2 tw = town(qx);
		float lights = smoothstep(0.4, 0.9, tw.y) * smoothstep(0.35, 0.0, abs(fract(qx / 0.045 * 6.0) - 0.5));
		float quay = exp(-pow((fract(qx / 0.06) - 0.5) / 0.08, 2.0));
		float broken = smoothstep(0.45, 0.75, ripple);
		col += vec3(1.0, 0.75, 0.45) * (lights * 0.12 + quay * 0.3) * broken * exp(above * 12.0);
	}

	// The town: far hills, then buildings with lit windows, lights along the quay.
	if (above > 0.0 && above < 0.25) {
		float hill = 0.035 + 0.025 * noise2(vec2(p.x * 3.0, 1.0));
		if (above < hill) {
			col = mix(col, night.rgb * 0.7 + glow * 0.15, 0.85);
		}
		vec2 tw = town(p.x);
		float bx = fract(p.x / 0.045);
		float roof = tw.x * (tw.y > 0.85 ? smoothstep(0.5, 0.35, abs(bx - 0.5)) * 0.4 + 0.6 : 1.0);
		if (above < roof) {
			vec3 bcol = night.rgb * 0.22 + glow * 0.1;
			vec2 win = vec2(bx * 6.0, above / 0.009);
			vec3 wh = hash3(floor(vec2(p.x / 0.045 * 6.0, win.y)), 37.0);
			float in_win = step(0.25, fract(win.x)) * step(fract(win.x), 0.75) * step(0.3, fract(win.y)) * step(fract(win.y), 0.75);
			bcol += mix(vec3(1.0, 0.78, 0.45), vec3(0.75, 0.85, 1.0), step(0.8, wh.z)) * in_win * step(wh.x, 0.35 * tw.y + 0.08) * (0.35 + 0.3 * wh.y);
			col = bcol;
		}
		// The quay and its lamps.
		if (above < 0.006) {
			col = night.rgb * 0.15 + glow * 0.05;
		}
		float lamp = fract(p.x / 0.06);
		col += vec3(1.0, 0.8, 0.5) * exp(-pow((lamp - 0.5) / 0.04, 2.0) - pow((above - 0.008) / 0.003, 2.0)) * 0.6;
	}
	col += fx;

	col *= 1.0 - 0.3 * pow(length(UV - 0.5) * 1.2, 2.0);
	col = col / (1.0 + col * 0.2);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
