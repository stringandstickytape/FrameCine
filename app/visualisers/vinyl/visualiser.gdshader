// Record deck (visualiser.json): a turntable seen from above. The record turns at 33 1/3 on an aluminium platter, the
// track's cover on its label; the grooves catch the lamp in the two bright wedges a real record shows, broken by the
// smooth gaps between tracks. Under the strobe lamp one row of dots on the platter's rim stands still, as it does when
// the speed is right. The tone arm tracks inwards over twenty minutes. A magnifier at the side shows the groove under
// the needle: its walls wiggle with the sound itself (the waveform), the needle riding the middle one, louder sound
// cutting wider. Worked out per pixel from the clocks: no memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float zoom = 0.6;
uniform float sheen = 0.6;
uniform bool show_loupe = true;
uniform vec4 wood : source_color = vec4(0.36, 0.22, 0.13, 1.0);
uniform vec4 record : source_color = vec4(0.03, 0.03, 0.035, 1.0);
uniform vec4 label : source_color = vec4(0.85, 0.2, 0.15, 1.0);
uniform vec4 metal : source_color = vec4(0.78, 0.79, 0.8, 1.0);

const vec2 LIGHT2 = vec2(-0.6, 0.8);


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

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash3(vec2(i, 0.0), 7.0).x, hash3(vec2(i + 1.0, 0.0), 7.0).x, f);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t);
}

float box(vec2 p, vec2 half_size, float r) {
	vec2 d = abs(p) - half_size + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// The sound as the groove carries it, lifted so quiet passages still show.
float groove_wave(float x) {
	return clamp(wave_at(x) * 2.5, -1.0, 1.0);
}

// A metal cylinder seen from the side, x -1..1 across it: shading with a bright line.
vec3 tube(float x, vec3 c) {
	float n = sqrt(max(1.0 - x * x, 0.0));
	return c * (0.35 + 0.55 * n + 0.3 * x * -0.6) + vec3(1.0) * pow(max(1.0 - abs(x + 0.35) * 4.0, 0.0), 2.0) * 0.6;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;
	float spin = vis_time * (100.0 / 3.0) / 60.0 * TAU;

	// The plinth: wood veneer, lit from the top left.
	float warp = noise2(p * vec2(1.5, 6.0)) * 4.0 + noise2(p * vec2(0.6, 2.0)) * 6.0;
	float grain = 0.5 + 0.5 * sin(p.y * 160.0 + warp * 3.0);
	grain = mix(grain, noise2(vec2(p.x * 3.0, p.y * 400.0 + warp * 20.0)), 0.4);
	vec3 col = wood.rgb * (0.65 + 0.4 * grain) * (0.75 + 0.35 * smoothstep(0.0, 1.0, p.y - p.x * 0.2 + 0.4));
	col += vec3(1.0, 0.95, 0.85) * 0.05 * exp(-pow((p.x * 0.6 + p.y - 1.1) * 3.0, 2.0));

	vec2 C = vec2(aspect * 0.565, 0.47);
	float RP = 0.395 * (0.85 + 0.25 * zoom);
	float RR = RP * 0.94;
	float RL = RP * 0.33;
	vec2 d = p - C;
	float r = length(d);
	vec2 n = d / max(r, 1e-5);

	// Platter shadow and the platter: brushed aluminium, rows of strobe dots on the rim.
	col *= 1.0 - 0.55 * smoothstep(RP + 0.05, RP - 0.01, length(d - vec2(0.018, -0.025)));
	if (r < RP + px) {
		float ring = noise1(r * 900.0) * 0.5 + noise1(r * 230.0) * 0.5;
		vec3 pl = metal.rgb * (0.55 + 0.25 * ring);
		pl += vec3(1.0) * 0.35 * pow(abs(dot(n, LIGHT2)), 10.0) * (0.6 + 0.4 * ring);
		pl *= 0.75 + 0.25 * dot(n, LIGHT2) * smoothstep(RP - 0.006, RP, r);
		// Three rows of dots. Under the lamp (front right) the middle row stands still; the others blur.
		float lamp_a = -0.6;
		float near_lamp = exp(-pow(atan(sin(atan(d.y, d.x) - lamp_a), cos(atan(d.y, d.x) - lamp_a)) / 0.35, 2.0));
		for (int row = 0; row < 3; row++) {
			float rr = mix(RR + (RP - RR) * 0.2, RP - (RP - RR) * 0.2, float(row) * 0.5);
			float count = 180.0 + float(row) * 4.0 - 4.0;
			float on_row = smoothstep(0.0028, 0.0012, abs(r - rr));
			float ang = atan(d.y, d.x) + (row == 1 ? 0.0 : spin);
			float cell = fract(ang / TAU * count) - 0.5;
			float dotm = smoothstep(0.32, 0.18, abs(cell));
			float still = row == 1 ? near_lamp : 0.0;
			float lit = mix(0.45, dotm, still);
			pl = mix(pl, mix(pl * 0.5, vec3(1.0, 0.55, 0.2) * 0.25 + pl * 0.6, lit * near_lamp) + pl * 0.2 * dotm * still, on_row);
		}
		col = mix(col, pl, smoothstep(RP + px, RP - px, r));
	}

	// The record.
	if (r < RR + px) {
		vec3 rec = record.rgb;
		// Tracks: grooved bands with smooth gaps between them, a lead-in and a run-out.
		float tr = (r - RL * 1.12) / (RR * 0.96 - RL * 1.12);
		float track_n = 6.0;
		float tx = tr * track_n + noise1(floor(tr * track_n) * 3.0) * 0.3;
		float gap = smoothstep(0.03, 0.0, abs(fract(tx) - 0.02)) * step(0.0, tr) * step(tr, 1.0);
		float grooved = step(0.0, tr) * step(tr, 1.0) * (1.0 - gap);
		float loud = 0.55 + 0.45 * noise1(r * 300.0) * noise1(r * 70.0 + 5.0) * 1.6;
		float wedge = pow(abs(dot(n, LIGHT2)), 18.0) * 0.9 + pow(abs(dot(n, LIGHT2)), 3.0) * 0.12;
		float fine = 0.75 + 0.25 * noise1(r * 2400.0);
		rec += vec3(0.92, 0.95, 1.0) * sheen * wedge * grooved * loud * fine;
		rec += vec3(1.0) * sheen * 0.25 * pow(abs(dot(n, LIGHT2)), 60.0) * (1.0 - grooved);
		// A soft gloss across the whole disc and a little dust turning with it.
		rec += vec3(0.04) * exp(-pow(length(d - rot(vec2(-0.12, 0.16), 0.0)) * 3.0, 2.0));
		vec2 dr = rot(d, -spin);
		vec2 dc = floor(dr / 0.012);
		vec3 dh = hash3(dc, 41.0);
		if (dh.x < 0.04) {
			vec2 o = (dh.yz - 0.5) * 0.6;
			float dd = length(fract(dr / 0.012) - 0.5 - o);
			rec += vec3(0.35) * smoothstep(0.12, 0.0, dd) * dh.y;
		}
		rec *= 1.0 - 0.6 * smoothstep(RR - 0.002, RR, r);
		col = mix(col, rec, smoothstep(RR + px, RR - px, r));
	}
	// The label: the cover, turning; without one a printed label.
	if (r < RL + px) {
		vec2 lq = rot(d, -spin) / RL;
		vec3 lc;
		if (has_cover > 0.5) {
			lc = texture(cover, lq * vec2(0.5, -0.5) * 0.98 + 0.5).rgb;
		} else {
			float lr = length(lq);
			lc = label.rgb * (0.85 + 0.15 * noise2(lq * 30.0));
			lc = mix(lc, vec3(0.95, 0.92, 0.85), smoothstep(0.012, 0.0, abs(lr - 0.86)) * 0.8);
			lc = mix(lc, vec3(0.95, 0.92, 0.85), smoothstep(0.08, 0.0, abs(lq.y - 0.45)) * step(abs(lq.x), 0.42) * 0.85);
			float la = atan(lq.y, lq.x);
			float words = step(abs(lr - 0.66), 0.035) * step(0.35, fract(la * 9.0)) * step(0.15, fract(la * 2.3)) * step(la, -0.4) * step(-2.7, la);
			lc = mix(lc, vec3(0.95, 0.92, 0.85), words * 0.7);
		}
		lc *= 0.85 + 0.2 * dot(n, LIGHT2) * smoothstep(0.7, 1.0, r / RL);
		col = mix(col, lc, smoothstep(RL + px, RL - px, r));
	}
	// Spindle.
	float sp_d = r - 0.011;
	if (sp_d < px) {
		vec3 sc = metal.rgb * (0.5 + 0.5 * dot(n, LIGHT2)) + vec3(0.6) * smoothstep(0.006, 0.0, length(d - vec2(-0.003, 0.004)));
		col = mix(col, sc, smoothstep(px, -px, sp_d));
	}

	// The strobe lamp at the front right of the platter.
	vec2 lampc = C + vec2(cos(-0.6), sin(-0.6)) * (RP + 0.045);
	float lamp_d = box(rot(p - lampc, 0.6), vec2(0.022, 0.014), 0.004);
	col += vec3(1.0, 0.5, 0.15) * 0.18 * exp(-max(lamp_d, 0.0) * 45.0);
	if (lamp_d < px) {
		col = mix(col, vec3(1.0, 0.62, 0.3) * (0.8 + 0.2 * smoothstep(0.014, 0.0, abs(rot(p - lampc, 0.6).y))), smoothstep(px, -px, lamp_d));
	}

	// The tone arm: pivot at the top right; the needle at radius rs, moving inwards over twenty minutes.
	vec2 P = C + vec2(RP + 0.13, RP * 0.5);
	float rs = mix(RR * 0.955, RL * 1.2, fract(vis_time / 1200.0));
	float dd = length(C - P);
	float le = dd + 0.015;
	float cosb = clamp((dd * dd + le * le - rs * rs) / (2.0 * dd * le), -1.0, 1.0);
	vec2 tocent = (C - P) / dd;
	vec2 sdir = rot(tocent, acos(cosb));
	vec2 S = P + sdir * le;
	vec2 tdir = rot(sdir, -0.18);
	vec2 J = P + tdir * (le - 0.075);
	vec2 hdir = normalize(S - J);
	vec2 hperp = vec2(-hdir.y, hdir.x);
	// Shadow of the arm.
	vec2 so = vec2(0.012, -0.02);
	float sh = min(seg(p - so, P - tdir * 0.12, J), seg(p - so, J, S + hdir * 0.02) - 0.008);
	col *= 1.0 - 0.45 * smoothstep(0.022, 0.004, sh);
	// Base.
	vec2 bq = p - P;
	float bl = length(bq);
	col *= 1.0 - 0.5 * smoothstep(0.1, 0.06, length(bq - so));
	if (bl < 0.07 + px) {
		vec3 bc = metal.rgb * (0.35 + 0.3 * noise1(bl * 900.0));
		bc *= 0.7 + 0.4 * dot(bq / max(bl, 1e-4), LIGHT2) * smoothstep(0.05, 0.07, bl);
		bc += vec3(0.4) * pow(abs(dot(bq / max(bl, 1e-4), LIGHT2)), 12.0) * step(bl, 0.05);
		col = mix(col, bc, smoothstep(0.07 + px, 0.07 - px, bl));
	}
	// The arm rest, with the lift lever.
	vec2 rest = P + vec2(-0.03, -0.2);
	float rd = box(p - rest, vec2(0.012, 0.03), 0.006);
	col = mix(col, metal.rgb * 0.4, smoothstep(px, -px, rd));
	float lever = seg(p, P + vec2(0.05, -0.08), P + vec2(0.09, -0.16)) - 0.006;
	col = mix(col, metal.rgb * 0.5 + 0.2 * smoothstep(0.006, 0.0, abs(lever + 0.004)), smoothstep(px, -px, lever));
	// Counterweight behind the pivot.
	vec2 wq = vec2(dot(p - P, -tdir), dot(p - P, vec2(-tdir.y, tdir.x)));
	float cw = box(wq - vec2(0.09, 0.0), vec2(0.04, 0.026), 0.006);
	if (cw < px) {
		vec3 wc = tube(wq.y / 0.026, metal.rgb * 0.8);
		wc *= 0.85 + 0.15 * step(0.5, fract(wq.x * 160.0)) * step(abs(wq.x - 0.09), 0.025);
		col = mix(col, wc, smoothstep(px, -px, cw));
	}
	// Tube and headshell.
	float td = seg(p, P - tdir * 0.05, J);
	float tw = 0.0075;
	if (td < tw + px) {
		vec2 along = normalize(J - P);
		float side = dot(p - P, vec2(-along.y, along.x)) / tw;
		col = mix(col, tube(clamp(side, -1.0, 1.0), metal.rgb), smoothstep(tw + px, tw - px, td));
	}
	vec2 hq = vec2(dot(p - S, hdir), dot(p - S, hperp));
	float hs = box(hq - vec2(-0.03, 0.0), vec2(0.045, 0.016), 0.005);
	float lift = seg(hq, vec2(-0.02, 0.016), vec2(-0.005, 0.04)) - 0.003;
	if (min(hs, lift) < px) {
		vec3 hc = metal.rgb * 0.75 * (0.8 + 0.2 * smoothstep(-0.016, 0.016, hq.y));
		float cart = box(hq - vec2(-0.012, 0.0), vec2(0.018, 0.011), 0.003);
		hc = mix(hc, vec3(0.07) + vec3(0.12) * smoothstep(0.011, -0.011, hq.y), smoothstep(px, -px, cart));
		hc = mix(hc, vec3(0.8, 0.12, 0.1), smoothstep(px, -px, length(hq - vec2(-0.022, 0.0)) - 0.003));
		col = mix(col, hc, smoothstep(px, -px, min(hs, lift)));
	}

	// The magnifier: the groove under the needle, its walls the waveform.
	vec2 mc = vec2(aspect - 0.2, 0.33);
	float MR = 0.15;
	vec2 mq = p - mc;
	float ml = length(mq);
	if (show_loupe) {
		col *= 1.0 - 0.5 * smoothstep(MR + 0.04, MR, length(mq - vec2(0.015, -0.02)));
		// A thin line from the needle to the magnifier.
		float lead = seg(p, S, mc + normalize(S - mc) * (MR + 0.012));
		col = mix(col, vec3(0.85), smoothstep(1.2 * px, 0.0, lead) * 0.35);
		if (ml < MR + 0.012) {
			vec2 g = mq / MR;
			vec3 mcol = record.rgb * 0.6 + vec3(0.02);
			float pitch = 0.36;
			float gy = g.y / pitch + 0.5;
			float gi = floor(gy);
			float near_g = 0.0;
			for (int k = -1; k <= 1; k++) {
				float j = gi + float(k);
				float x01 = g.x * 0.5 + 0.5;
				float lag = clamp(x01 * 0.88 + (j + 2.0) * 0.03, 0.0, 1.0);
				float amp = (0.16 + 0.3 * clamp(level * 1.4, 0.0, 1.0)) * (j == 0.0 ? 1.0 : 0.8);
				float centre = j * pitch + amp * groove_wave(lag) * pitch * 1.6;
				float slope = amp * pitch * 1.6 * (groove_wave(lag + 0.004) - groove_wave(lag - 0.004)) / 0.008 * 0.31;
				float dy = (g.y - centre) / sqrt(1.0 + slope * slope);
				float half_w = pitch * (0.26 + 0.12 * clamp(level, 0.0, 1.0));
				float inside = smoothstep(half_w + 0.01, half_w - 0.01, abs(dy));
				float wall = clamp(dy / half_w, -1.0, 1.0);
				vec3 gc = mix(vec3(0.03), vec3(0.75, 0.78, 0.85), pow(abs(wall), 1.5) * (wall > 0.0 ? 1.0 : 0.45));
				gc += vec3(1.0) * smoothstep(0.08, 0.0, abs(wall - 0.7)) * 0.35;
				mcol = mix(mcol, gc, inside);
				near_g = max(near_g, inside);
			}
			// The land between grooves.
			mcol += vec3(0.08, 0.085, 0.1) * (1.0 - near_g) * (0.6 + 0.4 * noise2(g * 40.0));
			// The needle: a cantilever coming in from the top, its diamond in the middle groove.
			float x01 = 0.5;
			float tip_y = (0.16 + 0.3 * clamp(level * 1.4, 0.0, 1.0)) * groove_wave(x01 * 0.88 + 0.06) * pitch * 1.6;
			vec2 tip = vec2(0.0, tip_y);
			float cant = seg(g, tip + vec2(0.0, 0.05), vec2(0.35, 1.2)) - mix(0.012, 0.03, clamp((g.y - tip.y) / 1.2, 0.0, 1.0));
			float diamond = max(abs(g.x - tip.x) * 1.2 + abs(g.y - tip.y - 0.06), 0.0) - 0.09;
			vec3 needle = vec3(0.6, 0.62, 0.66) * (0.6 + 0.4 * smoothstep(-0.045, 0.045, dot(g - tip, normalize(vec2(1.0, -0.29)))));
			mcol = mix(mcol, vec3(0.0), smoothstep(0.06, 0.0, min(cant, diamond)) * 0.5);
			mcol = mix(mcol, needle, smoothstep(0.01, -0.01, cant));
			mcol = mix(mcol, vec3(0.85, 0.9, 1.0) * (0.7 + 0.3 * g.x / 0.1), smoothstep(0.01, -0.01, diamond));
			// Glass: a soft highlight and darkening towards the rim.
			mcol *= 1.0 - 0.45 * pow(ml / MR, 4.0);
			mcol += vec3(1.0) * 0.12 * smoothstep(0.5, 0.0, length(g - vec2(-0.45, 0.5)));
			col = mix(col, mcol, smoothstep(MR + px, MR - px, ml));
			// The bezel.
			float bez = abs(ml - MR - 0.006) - 0.007;
			vec3 bc = metal.rgb * (0.55 + 0.45 * dot(mq / max(ml, 1e-4), LIGHT2));
			col = mix(col, bc, smoothstep(px, -px, bez));
		}
	}

	col *= 1.0 - 0.3 * pow(length(UV - 0.5) * 1.2, 2.0);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
