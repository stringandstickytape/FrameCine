// Night flight (visualiser.json): a flight down an avenue between the towers of a city at night. The city is a
// grid of blocks, one tower to a block, and the ray walks the grid block by block (so every tower is found exactly,
// however far). Each tower is a part of the spectrum: the more of its part there is, the more of its windows are
// lit; some towers carry neon up their corners or a crown of light on the roof that glow with it, some a big screen
// showing the spectrum as bars. Towers come in three makes (windows in a grid, ribbons of glass, curtain walls lit
// floor by floor). Below, wet streets carry two streams of traffic (white lamps towards, red away) on the music's
// clock (drive), with street lamps along the kerbs; red beacons on the tall roofs, searchlights turning far off, a
// skyline and the moon behind. The camera rises over the roofs and sinks between them as it goes. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float speed = 0.4;
uniform float lit = 0.6;
uniform float fog = 0.5;
uniform vec4 window_a : source_color = vec4(1.0, 0.78, 0.45, 1.0);
uniform vec4 window_b : source_color = vec4(0.6, 0.85, 1.0, 1.0);
uniform vec4 neon : source_color = vec4(1.0, 0.2, 0.6, 1.0);
uniform vec4 glow : source_color = vec4(0.22, 0.14, 0.3, 1.0);

const float INSET = 0.15;


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

// The tower's height in block c (h: its numbers): taller towards the middle of town, a few plazas.
float tower_h(vec2 c, vec3 h) {
	float town = 0.5 + 0.5 * sin(c.x * 0.35 + 1.0) * sin(c.y * 0.23);
	return h.y < 0.07 ? 0.04 : 0.5 + (1.2 + 3.6 * town) * h.x * h.x + 0.6 * town;
}

// The sky: the city's glow low down, the moon, stars, a far skyline with its lights.
vec3 sky_at(vec3 rd) {
	float up = max(rd.y, 0.0);
	vec3 c = mix(glow.rgb * 1.2, vec3(0.01, 0.012, 0.03), smoothstep(0.0, 0.5, up));
	float md = max(dot(rd, normalize(vec3(-0.5, 0.42, 0.75))), 0.0);
	c += vec3(0.9, 0.92, 1.0) * (smoothstep(0.9993, 0.9996, md) * 0.9 + pow(md, 40.0) * 0.12);
	vec2 sc = floor(rd.xy / (rd.z + 1.5) * 140.0);
	float sh = hash3(sc).x;
	c += vec3(0.8, 0.85, 1.0) * step(0.985, sh) * (sh - 0.985) * 30.0 * smoothstep(0.1, 0.4, up);
	float az = atan(rd.x, rd.z);
	float line = 0.02 + 0.07 * hash3(vec2(floor(az * 60.0), 3.0)).x * (0.5 + 0.5 * vnoise(vec2(az * 4.0, 1.0)));
	if (rd.y < line) {
		vec2 w = vec2(az * 600.0, rd.y * 500.0);
		float on = step(0.72, hash3(floor(w)).y) * step(0.25, fract(w.x)) * step(0.3, fract(w.y));
		c = mix(c, glow.rgb * 0.35 + mix(window_a.rgb, window_b.rgb, hash3(floor(w)).z) * on * 0.45, 0.85);
	}
	return c;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 uv = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float z0 = drive * speed * 0.22;
	vec3 ro = vec3(0.035 * sin(z0 * 1.3), 2.3 + 1.6 * sin(z0 * 0.21), z0);
	float yaw = 0.3 * sin(z0 * 0.17);
	vec3 cw = normalize(vec3(sin(yaw), -0.12 - 0.12 * (ro.y - 2.3), cos(yaw)));
	vec3 cu = normalize(cross(cw, vec3(0.05 * sin(z0 * 0.4), 1.0, 0.0)));
	vec3 cv = cross(cu, cw);
	vec3 rd = normalize(uv.x * cu + uv.y * cv + 1.0 * cw);
	if (abs(rd.x) < 1e-4) {
		rd.x = 1e-4;
	}
	if (abs(rd.z) < 1e-4) {
		rd.z = 1e-4;
	}

	// Walk the blocks along the ray.
	vec2 cell = floor(ro.xz);
	vec2 stp = sign(rd.xz);
	vec2 inv = 1.0 / abs(rd.xz);
	vec2 side = (cell + max(stp, 0.0) - ro.xz) / rd.xz;
	float t_in = 0.0;
	float tt = -1.0;
	int kind = 0;
	vec3 nrm = vec3(0.0);
	vec2 hc = vec2(0.0);
	vec3 hh = vec3(0.0);
	float H = 0.0;
	for (int i = 0; i < 60; i++) {
		vec3 h = hash3(cell);
		float th = tower_h(cell, h);
		vec3 bmin = vec3(cell.x + INSET, 0.0, cell.y + INSET);
		vec3 bmax = vec3(cell.x + 1.0 - INSET, th, cell.y + 1.0 - INSET);
		vec3 t1 = (bmin - ro) / rd;
		vec3 t2 = (bmax - ro) / rd;
		vec3 lo = min(t1, t2);
		vec3 hi = max(t1, t2);
		float tn = max(max(lo.x, lo.y), lo.z);
		float tf = min(min(hi.x, hi.y), hi.z);
		float t_out = min(side.x, side.y);
		if (tn < tf && tf > 0.0) {
			tt = max(tn, 0.0);
			kind = 1;
			nrm = lo.x > lo.y && lo.x > lo.z ? vec3(-stp.x, 0.0, 0.0) : (lo.y > lo.z ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, -stp.y));
			hc = cell;
			hh = h;
			H = th;
			break;
		}
		float tg = -ro.y / rd.y;
		if (rd.y < 0.0 && tg < t_out) {
			tt = tg;
			kind = 2;
			break;
		}
		if (t_out > 46.0) {
			break;
		}
		if (side.x < side.y) {
			side.x += inv.x;
			cell.x += stp.x;
		} else {
			side.y += inv.y;
			cell.y += stp.y;
		}
	}

	vec3 col = sky_at(rd);
	vec3 pos = ro + rd * tt;
	float px_w = tt / size.y;
	if (kind == 1) {
		float b = band(0.04 + 0.9 * hh.z);
		vec3 wall = vec3(0.035, 0.04, 0.055) * (0.7 + 0.6 * hh.x);
		if (nrm.y > 0.5) {
			// The roof: plant, a rim of lights on some, a red beacon on the tall.
			vec2 r = pos.xz - hc - 0.5;
			col = wall * 0.8 + vec3(0.02) * step(0.5, vnoise(pos.xz * 30.0));
			float rim = abs(max(abs(r.x), abs(r.y)) - (0.5 - INSET - 0.02));
			col += mix(neon.rgb, window_b.rgb, hh.y) * smoothstep(0.02, 0.0, rim) * step(0.6, hh.x) * (0.3 + 1.2 * b);
			col += vec3(1.0, 0.1, 0.05) * smoothstep(0.03, 0.0, length(r)) * step(3.0, H) * (0.6 + 0.4 * sin(vis_time * 1.5 + hh.z * 20.0));
		} else {
			float a = (abs(nrm.x) > 0.5 ? pos.z - hc.y : pos.x - hc.x) - INSET;
			float wide = 1.0 - 2.0 * INSET;
			vec2 g = vec2(a / 0.05, pos.y / 0.075);
			vec2 gi = floor(g);
			vec2 gf = fract(g);
			vec3 wh = hash3(gi + hc * 37.0 + nrm.xz * 11.0);
			int make = int(hh.y * 2.999);
			float pane;
			if (make == 0) {
				pane = step(0.2, gf.x) * step(gf.x, 0.8) * step(0.25, gf.y) * step(gf.y, 0.8);
			} else if (make == 1) {
				pane = step(0.3, gf.y) * step(gf.y, 0.75);
				wh = hash3(vec2(floor(g.x / 3.0), gi.y) + hc * 37.0);
			} else {
				pane = step(0.06, gf.x) * step(0.1, gf.y);
				wh = mix(wh, hash3(vec2(1.0, gi.y) + hc * 37.0), 0.75);
			}
			float frac_lit = (0.25 + 0.5 * b) * (0.4 + 0.9 * lit);
			float on = 1.0 - smoothstep(frac_lit - 0.05, frac_lit + 0.05, wh.x);
			vec3 wc = mix(window_a.rgb, window_b.rgb, step(0.6, fract(hh.z * 7.0 + wh.z * 0.3))) * (0.4 + 0.45 * wh.y);
			vec3 glass = vec3(0.02, 0.03, 0.05) + glow.rgb * 0.25 * smoothstep(3.0, 0.0, pos.y);
			float detail = clamp(1.0 - px_w / 0.022, 0.0, 1.0);
			vec3 face = mix(wall, mix(glass, wc, on), mix(0.5, pane, detail));
			face = mix(face, wall, step(pos.y, 0.12) * 0.7);
			// A screen on some towers: the spectrum as bars.
			if (hh.x > 0.45 && fract(hh.z * 13.0) < 0.3 && pos.y > H * 0.45 && pos.y < H * 0.8 && a > 0.06 && a < wide - 0.06) {
				float sx = (a - 0.06) / (wide - 0.12);
				float sy = (pos.y - H * 0.45) / (H * 0.35);
				float bar = band(0.03 + 0.9 * (floor(sx * 16.0) + 0.5) / 16.0);
				face = mix(vec3(0.01), mix(neon.rgb, window_b.rgb, sy) * 1.1, step(sy, 0.08 + 0.9 * bar) * step(0.15, fract(sx * 16.0)));
			}
			// Neon up the corners of some.
			float edge = min(a, wide - a);
			face += neon.rgb * smoothstep(0.025, 0.0, edge) * step(0.55, fract(hh.z * 5.0)) * (0.25 + 1.6 * b);
			col = face;
		}
		col += glow.rgb * 0.06;
	} else if (kind == 2) {
		// The street: wet tarmac, lane marks, kerb lamps, two streams of traffic.
		vec2 f = fract(pos.xz);
		vec2 d = min(f, 1.0 - f);
		bool along_z = d.x < d.y;
		float across = along_z ? (f.x < 0.5 ? f.x : f.x - 1.0) : (f.y < 0.5 ? f.y : f.y - 1.0);
		float run = along_z ? pos.z : pos.x;
		float street = step(min(d.x, d.y), INSET);
		vec3 gc = mix(vec3(0.03, 0.035, 0.04), vec3(0.015, 0.016, 0.02), street);
		gc += vec3(0.25) * street * smoothstep(0.004, 0.001, abs(across)) * step(0.5, fract(run * 12.0));
		gc += window_a.rgb * exp(-abs(abs(across) - INSET + 0.015) * 90.0) * (0.25 + 0.75 * pow(0.5 + 0.5 * cos(run * TAU * 5.0), 8.0)) * 0.6;
		float lane = abs(across);
		float dirn = sign(across);
		float car = fract(run * 2.2 * dirn - drive * 0.5 - floor(along_z ? pos.x + 0.5 : pos.z + 0.5) * 0.37);
		float dot_c = smoothstep(0.012, 0.0, abs(lane - 0.045)) * (smoothstep(0.06, 0.0, car) + smoothstep(0.94, 1.0, car));
		gc += (dirn > 0.0 ? vec3(1.0, 0.95, 0.85) : vec3(1.0, 0.1, 0.05)) * dot_c * street * 1.3;
		gc += glow.rgb * 0.35 * street * (0.5 + 0.5 * vnoise(pos.xz * 25.0));
		col = gc;
	}
	if (kind > 0) {
		col = mix(col, glow.rgb * 0.9, 1.0 - exp(-tt * (0.02 + 0.07 * fog)));
	}

	// Two searchlights turning far off, brighter when it is loud.
	for (int k = 0; k < 2; k++) {
		vec3 bp = vec3(k == 0 ? -9.0 : 11.0, 3.0, z0 + 30.0 + float(k) * 8.0);
		float a = drive * 0.12 + float(k) * 2.0;
		vec3 bd = normalize(vec3(0.5 * sin(a), 1.0, 0.5 * cos(a * 0.8)));
		vec3 w0 = ro - bp;
		float bb = dot(rd, bd);
		float den = max(1.0 - bb * bb, 0.001);
		float u = max((dot(bd, w0) - bb * dot(rd, w0)) / den, 0.0);
		float s = max(dot(bp + bd * u - ro, rd), 0.0);
		if (kind == 0 || s < tt) {
			float dist = length(ro + rd * s - bp - bd * u);
			float r = 0.15 + 0.03 * u;
			col += window_b.rgb * exp(-dist * dist / (r * r)) * 0.12 / (1.0 + 0.04 * u) * (0.5 + 0.7 * level);
		}
	}

	col *= 1.0 - 0.3 * pow(length(UV - 0.5) * 1.25, 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
