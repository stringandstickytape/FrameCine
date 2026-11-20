// Pinball (visualiser.json): a pinball table seen from the player's end, the music playing it. The table, its walls,
// the back box and the ball are found exactly (planes and a sphere); what is on the table is drawn on its plane.
// A chrome ball runs about the table on the music's clock (drive), reflecting the table it rolls over. The flippers
// take turns to flip on the beat. Three pop bumpers stand at the top (bass, middle, top): each lights with its part,
// and when the ball comes near. An arc of twelve inserts is the spectrum; so are the four lanes at the top and the
// eight targets down the sides. The slingshots flash on the beat. In the back box: the cover in a sunburst, a row of
// bulbs that is the spectrum again, and a score in seven-segment digits that counts the beats.
// More machines stand each side, waiting, in other colours. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float glow = 0.7;
uniform float pace = 0.5;
uniform vec4 field : source_color = vec4(0.1, 0.2, 0.45, 1.0);
uniform vec4 lamp_a : source_color = vec4(1.0, 0.25, 0.2, 1.0);
uniform vec4 lamp_b : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform vec4 lamp_c : source_color = vec4(0.2, 0.9, 1.0, 1.0);
uniform vec4 digits : source_color = vec4(1.0, 0.45, 0.1, 1.0);

const float PITCH = 2.7;

float hash1(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float tri(float x) {
	return abs(fract(x) * 2.0 - 1.0) * 2.0 - 1.0;
}

vec3 lamp_col(float k) {
	return k < 0.5 ? mix(lamp_a.rgb, lamp_b.rgb, k * 2.0) : mix(lamp_b.rgb, lamp_c.rgb, k * 2.0 - 1.0);
}

float seg_sd(vec2 q, vec2 a, vec2 b) {
	vec2 pa = q - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

float edge_d(vec2 q, vec2 a, vec2 b) {
	vec2 e = normalize(b - a);
	return dot(q - a, vec2(e.y, -e.x));
}

vec2 bumper_pos(int i) {
	return i == 0 ? vec2(-0.36, 3.0) : (i == 1 ? vec2(0.36, 3.05) : vec2(0.0, 2.62));
}

float bumper_lit(int i, vec2 ball) {
	float b = i == 0 ? bass : (i == 1 ? mid : treble);
	return clamp(0.15 + 0.85 * b + smoothstep(0.32, 0.14, length(ball - bumper_pos(i))), 0.0, 1.0);
}

// One seven-segment digit d at q (-0.5..0.5 across, -1..1 up): 1 on a lit segment.
float digit_at(vec2 q, int d) {
	int bits = d == 0 ? 63 : (d == 1 ? 6 : (d == 2 ? 91 : (d == 3 ? 79 : (d == 4 ? 102 : (d == 5 ? 109 : (d == 6 ? 125 : (d == 7 ? 7 : (d == 8 ? 127 : 111))))))));
	float m = 1.0;
	for (int s = 0; s < 7; s++) {
		if (((bits >> s) & 1) == 0) {
			continue;
		}
		vec2 c = s == 0 ? vec2(0.0, 0.84) : (s == 1 ? vec2(0.36, 0.42) : (s == 2 ? vec2(0.36, -0.42) : (s == 3 ? vec2(0.0, -0.84) : (s == 4 ? vec2(-0.36, -0.42) : (s == 5 ? vec2(-0.36, 0.42) : vec2(0.0, 0.0))))));
		vec2 hs = (s == 0 || s == 3 || s == 6) ? vec2(0.26, 0.07) : vec2(0.07, 0.33);
		vec2 dd = abs(q - c) - hs;
		m = min(m, max(dd.x, dd.y));
	}
	return smoothstep(0.03, -0.01, m);
}

// The table's face at q (x across -1..1, y up the table 0..4), the ball at ball.
vec3 table_at(vec2 q, vec2 ball) {
	vec2 qa = vec2(abs(q.x), q.y);
	float side = q.x < 0.0 ? 0.0 : 1.0;
	// The art: a sunburst and rings on the field's colour.
	vec2 c0 = q - vec2(0.0, 2.1);
	float rays = smoothstep(-0.25, 0.25, sin(atan(c0.y, c0.x) * 14.0));
	float rr = length(c0);
	vec3 col = field.rgb * (0.4 + 0.22 * rays * smoothstep(0.2, 0.6, rr));
	col = mix(col, lamp_b.rgb * 0.5, smoothstep(0.012, 0.004, abs(rr - 0.62)) * 0.8);
	col = mix(col, lamp_a.rgb * 0.35, smoothstep(0.3, 0.28, rr));
	col = mix(col, field.rgb * 0.2 + 0.05, smoothstep(0.2, 0.19, rr));
	col *= 0.9 + 0.1 * hash1(floor(q * 400.0));
	// The round top, the plunger lane.
	float arch = length(max(q - vec2(0.0, 3.0), vec2(-9.0, 0.0)) * vec2(1.0, 1.0)) - 1.0;
	col = mix(col, vec3(0.05, 0.03, 0.02), step(0.0, arch) * step(3.0, q.y));
	col = mix(col, vec3(0.75, 0.75, 0.8), smoothstep(0.014, 0.006, abs(arch)) * step(3.0, q.y));
	col = mix(col, vec3(0.04), step(0.9, q.x) * step(q.y, 3.0) * 0.85);
	col = mix(col, vec3(0.7, 0.7, 0.75), smoothstep(0.01, 0.004, abs(q.x - 0.9)) * step(q.y, 3.0));

	// The arc of inserts: the spectrum.
	for (int i = 0; i < 12; i++) {
		float k = float(i) / 11.0;
		float a = mix(2.55, 0.59, k);
		vec2 c = vec2(cos(a), sin(a)) * 0.98 + vec2(0.0, 0.92);
		float d = length(q - c);
		if (d < 0.09) {
			float b = band(0.03 + 0.92 * k);
			vec3 lit = lamp_col(k) * (0.14 + 1.25 * b * glow) * (1.0 - 0.5 * d / 0.06);
			col = mix(col, vec3(0.02), smoothstep(0.072, 0.066, d));
			col = mix(col, lit, smoothstep(0.06, 0.054, d));
		}
	}
	// The lanes at the top, a light in each.
	if (q.y > 3.35 && q.y < 3.85 && abs(q.x) < 0.66) {
		float lx = (q.x + 0.6) / 0.3;
		float k = clamp(floor(lx), 0.0, 3.0);
		vec2 f = vec2((lx - k - 0.5) * 0.3, q.y - 3.6);
		float b = band_between(k * 0.25, k * 0.25 + 0.25);
		float d = length(f);
		col = mix(col, vec3(0.02), smoothstep(0.07, 0.064, d));
		col = mix(col, lamp_col(k / 3.0) * (0.14 + 1.3 * b * glow), smoothstep(0.058, 0.052, d));
		float guide = seg_sd(vec2(abs(fract(lx + 0.5) - 0.5) * 0.3, q.y), vec2(0.0, 3.45), vec2(0.0, 3.78));
		col = mix(col, vec3(0.8, 0.8, 0.85), smoothstep(0.022, 0.014, guide));
	}
	// The targets down each side.
	for (int i = 0; i < 4; i++) {
		vec2 dd = abs(qa - vec2(0.84, 1.95 + 0.17 * float(i))) - vec2(0.022, 0.06);
		float d = max(dd.x, dd.y);
		if (d < 0.02) {
			float k = (float(i) + side * 4.0) / 7.0;
			float b = band(0.05 + 0.9 * k);
			col = mix(col, mix(vec3(0.85), lamp_col(k), 0.6) * (0.25 + 1.1 * b * glow), smoothstep(0.006, 0.0, d));
		}
	}
	// The bumpers' skirts and the light they throw.
	for (int i = 0; i < 3; i++) {
		vec2 c = bumper_pos(i);
		float d = length(q - c);
		float lit = bumper_lit(i, ball);
		col += lamp_col(float(i) * 0.5) * lit * glow * 0.55 * exp(-d * d * 22.0);
		col = mix(col, vec3(0.9, 0.9, 0.85), smoothstep(0.2, 0.19, d) * smoothstep(0.15, 0.16, d) * 0.9);
	}
	// The ramp's wires and their shadow.
	vec2 rc = vec2(0.0, 2.62);
	float sh = abs(abs(length(q - rc - vec2(0.03, -0.03)) - 0.66) - 0.04);
	col *= 1.0 - 0.45 * smoothstep(0.02, 0.008, sh) * step(2.5, q.y);
	float wire = abs(abs(length(q - rc) - 0.66) - 0.04);
	col = mix(col, vec3(0.8, 0.82, 0.88), smoothstep(0.012, 0.005, wire) * step(2.5, q.y));
	// The slingshots, flashing on the beat; the lane guides.
	float sl = max(edge_d(qa, vec2(0.45, 1.32), vec2(0.72, 1.28)), max(edge_d(qa, vec2(0.72, 1.28), vec2(0.72, 1.86)), edge_d(qa, vec2(0.72, 1.86), vec2(0.45, 1.32))));
	col = mix(col, lamp_a.rgb * (0.3 + 0.9 * beat * glow) + 0.05, smoothstep(0.005, -0.005, sl));
	col = mix(col, vec3(0.9), smoothstep(0.018, 0.008, abs(sl)));
	float guide = seg_sd(qa, vec2(0.8, 1.22), vec2(0.5, 1.02));
	guide = min(guide, seg_sd(qa, vec2(0.8, 1.22), vec2(0.8, 1.9)));
	col = mix(col, vec3(0.75, 0.77, 0.82), smoothstep(0.016, 0.008, guide));
	// The flippers, taking turns on the beat.
	float turn_now = mod(floor(beats), 2.0);
	float flip = beat * (abs(turn_now - side) < 0.5 ? 1.0 : 0.0);
	float fa = mix(-0.5, 0.45, flip);
	vec2 pv = vec2(0.44, 0.95);
	vec2 tip = pv + 0.34 * vec2(-cos(fa), sin(fa));
	float fl = seg_sd(qa, pv, tip) - 0.042;
	float fs = seg_sd(qa - vec2(0.02, -0.03), pv, tip) - 0.042;
	col *= 1.0 - 0.5 * smoothstep(0.02, -0.01, fs);
	col = mix(col, vec3(0.92, 0.9, 0.85), smoothstep(0.004, -0.004, fl));
	col = mix(col, lamp_a.rgb * 0.9, smoothstep(0.004, -0.004, abs(fl + 0.014) - 0.006));
	// The ball's shadow.
	col *= 1.0 - 0.6 * smoothstep(0.075, 0.02, length(q - ball - vec2(0.03, -0.025)));
	return col;
}

// The back box at q (x -1.1..1.1, y 0.25..2.35).
vec3 backbox_at(vec2 q, float art) {
	vec3 col = vec3(0.015);
	if (abs(q.x) < 1.03 && q.y > 0.85 && q.y < 2.3) {
		// The glass: a sunburst, the cover in the middle.
		vec2 c = q - vec2(0.0, 1.55);
		float rays = smoothstep(-0.2, 0.2, sin(atan(c.y, c.x) * 16.0 + drive * 0.03));
		col = mix(lamp_a.rgb, lamp_b.rgb, rays) * (0.28 + 0.2 * level) * (1.1 - 0.5 * length(c));
		float ring = abs(length(c) - 0.62);
		col = mix(col, lamp_c.rgb * (0.4 + 0.5 * bass), smoothstep(0.03, 0.02, ring));
		vec2 uv = c / 0.84 + 0.5;
		if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0 && art > 0.5) {
			col = texture(cover, vec2(uv.x, 1.0 - uv.y)).rgb * 0.85;
			float fr = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
			col = mix(vec3(0.9, 0.8, 0.5), col, smoothstep(0.015, 0.025, fr));
		} else if (art < 0.5) {
			col = mix(col, field.rgb * 0.6, smoothstep(0.42, 0.4, length(c)));
			col = mix(col, lamp_b.rgb * (0.5 + 0.5 * level), smoothstep(0.03, 0.02, abs(length(c) - 0.3)));
		}
		// The bulbs along the top: the spectrum.
		float bx = (q.x + 1.03) / 2.06 * 16.0;
		float k = floor(bx);
		float d = length(vec2((fract(bx) - 0.5) * 2.06 / 16.0, q.y - 2.22));
		float b = band(0.03 + 0.92 * k / 15.0);
		col = mix(col, vec3(0.03), smoothstep(0.05, 0.045, d));
		col = mix(col, lamp_col(k / 15.0) * (0.15 + 1.2 * b * glow) + 0.6 * b * smoothstep(0.02, 0.0, d), smoothstep(0.04, 0.034, d));
	} else if (abs(q.x) < 0.8 && q.y > 0.38 && q.y < 0.74) {
		// The score.
		col = vec3(0.03, 0.012, 0.008);
		float dx = (q.x + 0.75) / 0.25;
		float k = floor(dx);
		if (k >= 0.0 && k < 6.0) {
			float score = floor(beats) * 750.0;
			int d = int(mod(floor(score / pow(10.0, 5.0 - k)), 10.0));
			vec2 dq = vec2((fract(dx) - 0.5) * 1.25, (q.y - 0.56) / 0.14);
			col += digits.rgb * digit_at(dq, d) * (0.85 + 0.15 * beat);
		}
	}
	return col;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	vec3 ro = vec3(0.15 * sin(drive * 0.03), 2.3, -1.2);
	vec3 fw = normalize(vec3(0.0, 0.6, 2.4) - ro);
	vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
	vec3 up = cross(fw, rt);
	vec3 rd = normalize(fw * 0.95 + rt * p.x + up * p.y);

	float tb = drive * pace * 1.2;
	vec2 ball = vec2(0.8 * tri(tb * 0.31), 0.75 + 2.9 * (0.5 + 0.5 * tri(tb * 0.23 + 0.25)));
	vec3 bc = vec3(ball.x, 0.05, ball.y);
	vec2 nowhere = vec2(9.0);

	// The arcade: dark, a worn carpet, a little of the machines' light on it. The machines stand in a row, PITCH
	// apart; the one in the middle is the one being played, the others wait in other colours.
	vec3 col = vec3(0.02, 0.018, 0.025);
	float best = 1e9;
	float cell = 0.0;
	float t = -ro.y / rd.y;
	vec3 q = ro + rd * t;
	if (rd.y < 0.0 && q.z > 0.0 && q.z < 4.0) {
		float cl = floor((q.x + PITCH * 0.5) / PITCH);
		float lx = q.x - cl * PITCH;
		if (abs(lx) < 1.0) {
			best = t;
			cell = cl;
			col = table_at(vec2(lx, q.z), cl == 0.0 ? ball : nowhere) * (0.85 + 0.12 * level);
			col *= 0.6 + 0.4 * smoothstep(1.0, 0.9, abs(lx));
			col += vec3(0.05, 0.06, 0.08) * smoothstep(3.0, 4.0, q.z);
		} else if (abs(lx) < 1.09) {
			best = t;
			col = vec3(0.04, 0.04, 0.045) + 0.1 * smoothstep(0.03, 0.0, abs(abs(lx) - 1.045));
		}
	}
	if (rd.y < 0.0 && best > 1e8) {
		// The carpet, a long way down.
		float tf = (-1.4 - ro.y) / rd.y;
		vec3 f = ro + rd * tf;
		float pat = step(0.5, hash1(floor(f.xz * 3.0)));
		col = vec3(0.03, 0.022, 0.035) * (0.6 + 0.4 * pat) + lamp_col(0.5) * 0.012 * (0.5 + level);
	}
	// The side walls of the machine the ray is over.
	float t8 = (0.08 - ro.y) / rd.y;
	float c8 = floor((ro.x + rd.x * t8 + PITCH * 0.5) / PITCH);
	for (int s = 0; s < 2; s++) {
		float wx = c8 * PITCH + (s == 0 ? -1.0 : 1.0);
		float tw = (wx - ro.x) / rd.x;
		vec3 w = ro + rd * tw;
		if (tw > 0.0 && tw < best && w.y > 0.0 && w.y < 0.16 && w.z > 0.0 && w.z < 4.0) {
			best = tw;
			cell = 0.0;
			col = vec3(0.2, 0.1, 0.045) * (0.3 + 0.5 * w.y / 0.16);
		}
	}
	// The back boxes.
	float tz = (4.02 - ro.z) / rd.z;
	vec3 bq = ro + rd * tz;
	float cb = floor((bq.x + PITCH * 0.5) / PITCH);
	float bx = bq.x - cb * PITCH;
	if (tz > 0.0 && tz < best && abs(bx) < 1.1 && bq.y > 0.0 && bq.y < 2.35) {
		best = tz;
		cell = cb;
		col = bq.y < 0.25 ? vec3(0.02) : backbox_at(vec2(bx, bq.y), cb == 0.0 ? has_cover : 0.0);
	}
	// The bumpers: a cap over a body.
	float tc = (0.14 - ro.y) / rd.y;
	vec3 hc = ro + rd * tc;
	float cm = floor((hc.x + PITCH * 0.5) / PITCH);
	vec2 near = cm == 0.0 ? ball : nowhere;
	for (int i = 0; i < 3; i++) {
		vec2 c = bumper_pos(i) + vec2(cm * PITCH, 0.0);
		float d = length(hc.xz - c);
		float lit = bumper_lit(i, near);
		vec3 lc = lamp_col(float(i) * 0.5);
		if (tc > 0.0 && tc < best && d < 0.15) {
			best = tc;
			cell = cm;
			float star = smoothstep(-0.3, 0.3, sin(atan(hc.z - c.y, hc.x - c.x) * 8.0));
			col = mix(lc * 0.5, vec3(0.9), star * step(d, 0.11)) * (0.3 + 0.9 * lit * glow);
			col = mix(col, vec3(0.85), smoothstep(0.03, 0.025, d));
		} else {
			vec2 oc2 = ro.xz - c;
			float a = dot(rd.xz, rd.xz);
			float b2 = dot(oc2, rd.xz);
			float disc2 = b2 * b2 - a * (dot(oc2, oc2) - 0.0121);
			if (disc2 > 0.0) {
				float ts = (-b2 - sqrt(disc2)) / a;
				float y = ro.y + rd.y * ts;
				if (ts > 0.0 && ts < best && y > 0.0 && y < 0.14) {
					best = ts;
					cell = cm;
					col = mix(vec3(0.8), lc, 0.5) * (0.2 + 1.0 * lit * glow) * (0.6 + 0.4 * y / 0.14);
				}
			}
		}
	}
	// The machines that wait: other colours, dimmer.
	if (cell != 0.0) {
		col = (mod(cell, 2.0) > 0.5 ? col.gbr : col.brg) * 0.55;
	}
	// The ball: chrome, reflecting the table under it and the lit box above.
	vec3 oc = ro - bc;
	float b = dot(oc, rd);
	float disc = b * b - (dot(oc, oc) - 0.0025);
	if (disc > 0.0) {
		float ts = -b - sqrt(disc);
		if (ts > 0.0 && ts < best) {
			vec3 h = ro + rd * ts;
			vec3 n = (h - bc) / 0.05;
			vec3 r = reflect(rd, n);
			vec3 env;
			if (r.y < -0.05) {
				vec2 pt = clamp(h.xz + r.xz * (h.y / -r.y), vec2(-0.99, 0.01), vec2(0.99, 3.99));
				env = table_at(pt, nowhere) * 0.8;
			} else {
				env = vec3(0.03) + lamp_col(0.5 + 0.5 * r.x) * 0.25 * smoothstep(0.0, 0.6, r.z) * (0.5 + level);
				env += vec3(1.0) * smoothstep(0.9, 0.98, dot(r, normalize(vec3(-0.3, 0.9, -0.2))));
			}
			col = env * (0.75 + 0.25 * pow(1.0 - max(dot(-rd, n), 0.0), 3.0)) + vec3(0.03);
		}
	}
	col *= 1.0 - 0.3 * dot(p, p);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
