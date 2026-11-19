// Circuit (visualiser.json): a circuit board seen close. Copper tracks run under a glossy solder mask in lanes, a bus
// at a time jogging across at 45 degrees as tracks do; where one ends it drops through a via. Chips sit on the lanes
// (their legs on the tracks), with a big lidded processor in the middle; small resistors and capacitors sit on some
// tracks; part labels and outlines are printed in white. Bursts of light run along the tracks: each lane is a part of
// the spectrum (low notes at the bottom), its bursts as bright as its band; a column of LEDs on the right is a level
// meter. The bursts run on the music's clock (drive). Worked out per pixel from the clocks: no memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float activity = 0.55;
uniform float speed = 0.5;
uniform float sheen = 0.5;
uniform vec4 mask : source_color = vec4(0.05, 0.3, 0.16, 1.0);
uniform vec4 copper : source_color = vec4(0.85, 0.55, 0.3, 1.0);
uniform vec4 signal : source_color = vec4(0.4, 1.0, 0.95, 1.0);
uniform vec4 silk : source_color = vec4(0.92, 0.93, 0.9, 1.0);

const float PITCH = 0.028;
const float COL = 0.3;
const float LANES = 36.0;
const float TRACE = 0.0032;


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

float fill(float d) {
	return fill_px(d * size.y);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t);
}

float box(vec2 p, vec2 c, vec2 half_size) {
	vec2 d = abs(p - c) - half_size;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// 3 x 5 glyphs, a row of 3 bits each, the top row highest: digits, then U R C D L.
int glyph(int d) {
	return d == 0 ? 31599 : d == 1 ? 11415 : d == 2 ? 29671 : d == 3 ? 29647 : d == 4 ? 23497 : d == 5 ? 31183
			: d == 6 ? 31215 : d == 7 ? 29257 : d == 8 ? 31727 : d == 9 ? 31695 : d == 10 ? 23407 : d == 11 ? 27565
			: d == 12 ? 31015 : d == 13 ? 27502 : 18727;
}

// 1 where a part label (a letter and two digits) is printed at p, its top left at o, cell size c.
float label(vec2 p, vec2 o, int letter, int number, float c) {
	vec2 q = (p - o) / c;
	if (q.x < 0.0 || q.y < 0.0 || q.y >= 5.0 || q.x >= 11.0) {
		return 0.0;
	}
	float i = floor(q.x / 4.0);
	float cx = mod(q.x, 4.0);
	if (cx >= 3.0) {
		return 0.0;
	}
	int g = i < 0.5 ? letter : i < 1.5 ? (number / 10) % 10 : number % 10;
	int bit = (4 - int(q.y)) * 3 + (2 - int(cx));
	return float((glyph(g) >> bit) & 1);
}

// The bus in column s: x its first lane, y how many lanes, z which way it jogs (+1 down, -1 up), w where along the
// column (0..1).
vec4 bus(float s) {
	vec3 h = hash3(vec2(s, 0.0), 11.0);
	float n = 3.0 + floor(h.y * 6.0);
	float a = floor(h.x * (LANES - n - 2.0)) + 1.0;
	return vec4(a, n, h.z < 0.5 ? -1.0 : 1.0, 0.2 + 0.45 * hash3(vec2(s, 1.0), 12.0).x);
}

// A burst of light on the track that starts in lane j of column s, at u (0..1) along it.
float burst(float u, float j, float s) {
	vec3 h = hash3(vec2(j, s), 21.0);
	if (h.z > activity) {
		return 0.0;
	}
	float b = band(0.04 + (1.0 - (j + 0.5) / LANES) * 0.9);
	float ph = fract(drive * speed * (0.5 + 0.9 * h.x) + h.y);
	float head = ph * 1.6 - 0.3;
	float dd = head - u;
	float shape = dd >= 0.0 ? exp(-dd * 9.0) : exp(dd * 160.0);
	return shape * (0.15 + 1.3 * b);
}

// The tracks near p: x the distance to the nearest (heights), y the light running along it, and z the distance to the
// nearest via.
vec3 tracks(vec2 p) {
	float s = floor(p.x / COL);
	vec4 b = bus(s);
	float xs = s * COL;
	float x0 = xs + b.w * COL;
	float u = (p.x - xs) / COL;
	float k = floor(p.y / PITCH);
	float conflict = b.z > 0.0 ? b.x + b.y : b.x - 1.0;
	float vacated = b.z > 0.0 ? b.x : b.x + b.y - 1.0;
	float dmin = 1.0;
	float light = 0.0;
	float via = 1.0;
	for (int o = -1; o <= 1; o++) {
		float j = k + float(o);
		float y = (j + 0.5) * PITCH;
		float d = 0.0;
		if (j >= b.x && j < b.x + b.y) {
			vec2 B = vec2(x0, y);
			vec2 C = vec2(x0 + PITCH, y + b.z * PITCH);
			d = min(seg(p, vec2(xs, y), B), min(seg(p, B, C), seg(p, C, vec2(xs + COL, C.y))));
		} else if (j == conflict) {
			vec2 stop = vec2(x0 - 0.018, y);
			d = seg(p, vec2(xs, y), stop);
			via = min(via, length(p - stop));
		} else {
			d = seg(p, vec2(xs, y), vec2(xs + COL, y));
		}
		float w = exp(-d * d / (TRACE * TRACE * 2.0)) + 0.3 * exp(-d / 0.009);
		light += burst(u, j, s) * w;
		if (j == vacated) {
			vec2 start = vec2(x0 + PITCH + 0.018, y);
			float d2 = seg(p, start, vec2(xs + COL, y));
			via = min(via, length(p - start));
			light += burst(u, j + 50.0, s) * (exp(-d2 * d2 / (TRACE * TRACE * 2.0)) + 0.3 * exp(-d2 / 0.009));
			d = min(d, d2);
		}
		// A via along some tracks, where they change layer.
		vec3 hv = hash3(vec2(j, s), 31.0);
		if (hv.x < 0.25 && !(j >= b.x - 1.0 && j <= b.x + b.y)) {
			via = min(via, length(p - vec2(xs + COL * (0.1 + 0.8 * hv.y), y)));
		}
		dmin = min(dmin, d);
	}
	return vec3(dmin, light, via);
}

// A chip at cell c of a coarse grid, or none: centre, half size (snapped to the lanes).
vec4 chip(vec2 c, vec2 big) {
	vec3 h = hash3(c, 41.0);
	vec2 centre_guess = (c + 0.5) * vec2(0.42, 12.0 * PITCH);
	if (h.x > 0.5 || length(centre_guess - big) < 0.42) {
		return vec4(0.0);
	}
	float lanes = 3.0 + floor(h.y * 5.0);
	float l0 = c.y * 12.0 + 2.0 + floor(h.z * (9.0 - lanes));
	float hw = 0.035 + 0.06 * hash3(c, 42.0).x;
	float cx = (c.x + 0.25 + 0.5 * hash3(c, 43.0).x) * 0.42;
	return vec4(cx, (l0 + lanes * 0.5) * PITCH, hw, lanes * PITCH * 0.5);
}

// Draws a chip body with legs over col: legs on the left and right at every lane, and on top and bottom for a
// square one (quad).
void draw_chip(inout vec3 col, vec2 p, vec4 ch, bool quad, float lid, float id) {
	vec2 c = ch.xy;
	vec2 hs = ch.zw - vec2(0.0, 0.006);
	// Legs.
	vec2 q = p - c;
	float legs = 1.0;
	if (abs(q.x) > hs.x && abs(q.x) < hs.x + 0.016 && abs(q.y) < hs.y) {
		float ly = mod(q.y + ch.w, PITCH) - PITCH * 0.5;
		legs = max(abs(ly) - PITCH * 0.18, abs(abs(q.x) - hs.x - 0.008) - 0.008);
	}
	if (quad && abs(q.y) > hs.y && abs(q.y) < hs.y + 0.016 && abs(q.x) < hs.x - 0.01) {
		float lx = mod(q.x, PITCH * 0.75) - PITCH * 0.375;
		legs = min(legs, max(abs(lx) - PITCH * 0.15, abs(abs(q.y) - hs.y - 0.008) - 0.008));
	}
	vec3 tin = vec3(0.78, 0.8, 0.82) * (0.75 + 0.35 * smoothstep(-0.004, 0.004, q.y));
	col *= 1.0 - 0.4 * (1.0 - smoothstep(0.0, 0.01, box(p - vec2(0.004, 0.007), c, hs)));
	col = mix(col, tin, fill(legs));
	float body = box(p, c, hs - 0.002) - 0.002;
	vec3 bc = vec3(0.09, 0.09, 0.1) * (0.85 + 0.3 * noise2(p * 300.0));
	if (lid > 0.5) {
		// A brushed metal lid with a bevel.
		float lb = box(p, c, hs - 0.03);
		vec3 metal = vec3(0.62, 0.63, 0.66) * (0.84 + 0.16 * noise2(p * vec2(30.0, 1500.0)));
		metal *= 0.85 + 0.3 * smoothstep(-0.25, 0.25, q.x - q.y);
		bc = mix(bc, metal, fill(lb));
		bc = mix(bc, vec3(0.3), smoothstep(1.5, 0.0, abs(lb * size.y)));
	} else {
		// Pin one's dimple, and its printed lines.
		bc *= 1.0 - 0.4 * fill(length(q - vec2(-hs.x + 0.012, -hs.y + 0.012)) - 0.004);
		vec2 tp = q / vec2(hs.x - 0.012, 0.008);
		float row = floor(tp.y + 0.5);
		vec3 hr = hash3(vec2(id, row), 44.0);
		float txt = step(abs(row), 1.0) * step(abs(tp.x), 0.3 + 0.6 * hr.x)
				* step(0.35, fract(tp.x * (3.0 + 4.0 * hr.y))) * step(abs(fract(tp.y + 0.5) - 0.5), 0.3);
		bc = mix(bc, vec3(0.42), txt * 0.8);
	}
	// A bevel catching the light along the top edge.
	bc += vec3(0.12) * smoothstep(-3.0, 0.0, body * size.y) * smoothstep(0.004, -0.004, q.y + q.x * 0.3);
	col = mix(col, bc, fill(body));
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = UV * vec2(aspect, 1.0);
	// The mask, glossy, with the board's weave faintly through it.
	vec3 col = mask.rgb * (0.85 + 0.15 * noise2(p * vec2(400.0, 60.0)) * noise2(p * vec2(60.0, 400.0)));
	vec3 tr = tracks(p);
	// Copper under the mask: lighter, raised a little (a lit edge on top, a dark one under).
	float cov = fill(tr.x - TRACE);
	vec3 over = mix(mask.rgb, copper.rgb, 0.32) * 1.25;
	col = mix(col, over, cov);
	col = mix(col, col * 1.25, cov * smoothstep(0.0, -TRACE, tr.x - TRACE) * 0.4);
	// Vias: a tinned ring with a hole.
	col = mix(col, vec3(0.75, 0.74, 0.7), fill(tr.z - 0.0065));
	col = mix(col, vec3(0.02), fill(tr.z - 0.0028));

	// Small parts on some tracks: resistors (black, printed) and capacitors (tan), each with two metal ends.
	float lane = floor(p.y / PITCH);
	float cs = floor(p.x / 0.11);
	vec3 hp = hash3(vec2(cs, lane), 51.0);
	if (hp.x < 0.07) {
		vec2 c = vec2((cs + 0.3 + 0.4 * hp.y) * 0.11, (lane + 0.5) * PITCH);
		float pd = box(p, c, vec2(0.016, 0.0075));
		col *= 1.0 - 0.35 * (1.0 - smoothstep(0.0, 0.006, box(p - vec2(0.003, 0.005), c, vec2(0.016, 0.0075))));
		vec3 pc = hp.z < 0.5 ? vec3(0.08) : vec3(0.62, 0.5, 0.33);
		pc = mix(pc, vec3(0.8, 0.8, 0.82), step(0.011, abs(p.x - c.x)));
		pc *= 0.85 + 0.3 * smoothstep(0.006, -0.006, p.y - c.y);
		col = mix(col, pc, fill(pd));
		// Its label beside it.
		col = mix(col, silk.rgb, label(p, c + vec2(-0.012, -0.023), hp.z < 0.5 ? 11 : 12,
				int(hp.y * 89.0) + 1, 0.0021) * 0.9);
	}

	// Chips on a coarse grid; the big processor in the middle.
	vec2 big = vec2(aspect * 0.64, (floor(0.52 / PITCH) + 0.5) * PITCH);
	vec2 gc = floor(p / vec2(0.42, 12.0 * PITCH));
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = gc + vec2(float(i), float(j));
			vec4 ch = chip(c, big);
			if (ch.z > 0.0 && abs(p.x - ch.x) < ch.z + 0.06 && abs(p.y - ch.y) < ch.w + 0.06) {
				float quad = hash3(c, 45.0).x;
				// The outline printed round it, and its label above.
				float ol = abs(box(p, ch.xy, ch.zw + vec2(0.024, 0.012))) - 0.0012;
				col = mix(col, silk.rgb, fill(ol) * 0.8);
				col = mix(col, silk.rgb, label(p, ch.xy + vec2(-ch.z - 0.02, -ch.w - 0.03), quad < 0.35 ? 10 : 13,
						int(hash3(c, 46.0).x * 98.0) + 1, 0.0028) * 0.9);
				draw_chip(col, p, ch, quad < 0.35, 0.0, c.x * 7.0 + c.y);
			}
		}
	}
	vec4 bigc = vec4(big, 0.17, 6.0 * PITCH);
	if (abs(p.x - big.x) < 0.26 && abs(p.y - big.y) < 0.26) {
		float ol = abs(box(p, big, bigc.zw + vec2(0.03, 0.03))) - 0.0014;
		col = mix(col, silk.rgb, fill(ol) * 0.8);
		col = mix(col, silk.rgb, label(p, big + vec2(-bigc.z - 0.03, -bigc.w - 0.052), 10, 1, 0.0034) * 0.9);
		draw_chip(col, p, bigc, true, 1.0, 0.0);
	}

	// The light running along the tracks, over everything flat (it glows through the mask).
	vec3 glow = signal.rgb * tr.y + vec3(1.0) * max(tr.y - 0.8, 0.0) * 0.5;
	col += glow * 1.1;

	// A level meter of LEDs down the right: low notes at the bottom, green to amber to red.
	float lx = aspect - 0.075;
	if (abs(p.x - lx) < 0.06) {
		float li = floor((0.84 - p.y) / 0.044);
		if (li >= 0.0 && li < 16.0) {
			vec2 c = vec2(lx, 0.84 - (li + 0.5) * 0.044);
			float on = smoothstep(0.08, 0.45, band(0.03 + li / 15.0 * 0.92));
			vec3 lc = li < 9.0 ? vec3(0.25, 1.0, 0.35) : li < 13.0 ? vec3(1.0, 0.75, 0.15) : vec3(1.0, 0.22, 0.15);
			float d = box(p, c, vec2(0.015, 0.008)) - 0.002;
			col *= 1.0 - 0.3 * (1.0 - smoothstep(0.0, 0.006, box(p - vec2(0.003, 0.005), c, vec2(0.016, 0.009))));
			vec3 body = mix(vec3(0.85, 0.85, 0.8), lc * (0.25 + 1.2 * on), fill(box(p, c, vec2(0.011, 0.005))));
			body = mix(body, vec3(0.75), step(0.012, abs(p.x - c.x)));
			col = mix(col, body, fill(d));
			col += lc * on * 0.35 * exp(-max(d, 0.0) * 90.0);
		}
		col = mix(col, silk.rgb, fill(abs(box(p, vec2(lx, 0.488), vec2(0.026, 0.36))) - 0.0012) * 0.8);
	}

	// Mounting holes in the corners: plated rings.
	vec2 mh = vec2(p.x < aspect * 0.5 ? 0.06 : aspect - 0.06, p.y < 0.5 ? 0.06 : 0.94);
	float md = length(p - mh);
	col = mix(col, vec3(0.8, 0.72, 0.5) * (0.8 + 0.3 * smoothstep(0.02, -0.02, p.y - mh.y)), fill(md - 0.03));
	col = mix(col, vec3(0.01), fill(md - 0.017));

	// The gloss: a broad soft reflection drifting across the board.
	vec2 sp = vec2(aspect * (0.5 + 0.45 * sin(drive * 0.03)), 0.35 + 0.2 * cos(drive * 0.021));
	col += vec3(0.9, 0.95, 1.0) * sheen * 0.1 * exp(-length((p - sp) * vec2(1.0, 1.8)) * 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
