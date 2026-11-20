// Grand piano (visualiser.json): a grand piano on a dark stage, seen from above its keyboard with the lid up, every
// surface a plane found exactly. Inside: the spruce soundboard, the gilt iron plate with its struts, the bridge, and
// forty-eight strings, the long copper-wound ones the low notes. Each string is a part of the spectrum: as its part
// sounds the string swells into the spindle a real string blurs into (widest in the middle, still at the ends) and
// glows; its hammer brightens under it and its damper lifts. The keyboard plays itself: four octaves, each key
// (white and black) going down and lighting with its own note. The fallboard above the keys mirrors them, and the
// raised lid, black and polished, mirrors the strings: the ray is sent back from it and the inside found again.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float vib = 0.7;
uniform float shine = 0.6;
uniform vec4 lacquer : source_color = vec4(0.02, 0.02, 0.025, 1.0);
uniform vec4 plate : source_color = vec4(0.75, 0.58, 0.25, 1.0);
uniform vec4 board : source_color = vec4(0.55, 0.38, 0.18, 1.0);
uniform vec4 tone : source_color = vec4(1.0, 0.7, 0.3, 1.0);

const float N = 48.0;
const float LID = 0.9;

float hash1(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x), mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

// How far back the case goes at x: long at the bass side, short at the top.
float zend(float x) {
	return 2.3 + 3.8 * smoothstep(3.2, -2.2, x);
}

float note_band(float k) {
	return band(0.03 + 0.94 * k / (N - 1.0));
}

// The semitone of white key i.
float white_semi(float i) {
	float o = floor(i / 7.0);
	float d = i - o * 7.0;
	float s = d < 0.5 ? 0.0 : (d < 1.5 ? 2.0 : (d < 2.5 ? 4.0 : (d < 3.5 ? 5.0 : (d < 4.5 ? 7.0 : (d < 5.5 ? 9.0 : 11.0)))));
	return o * 12.0 + s;
}

// The keyboard at q (x -3..3, y from the front edge -0.95 back to 0.3).
vec3 keys_at(vec2 q) {
	float wk = (q.x + 3.0) / 6.0 * 28.0;
	float i = floor(wk);
	float f = fract(wk);
	float press = smoothstep(0.15, 0.6, note_band(white_semi(i)));
	vec3 col = vec3(0.93, 0.91, 0.85) * (1.0 - 0.3 * press) + tone.rgb * press * shine * 0.45;
	col *= smoothstep(0.0, 0.06, f) * smoothstep(1.0, 0.94, f);
	col *= 0.8 + 0.2 * smoothstep(-0.95, -0.75, q.y);
	float j = floor(wk + 0.5);
	float d = mod(j, 7.0);
	if (d > 0.5 && abs(d - 3.0) > 0.5 && j > 0.5 && j < 27.5 && q.y > -0.35) {
		float off = wk - j;
		if (abs(off) < 0.3) {
			float pr = smoothstep(0.15, 0.6, note_band(white_semi(j) - 1.0));
			col = vec3(0.03, 0.03, 0.035) + vec3(0.14) * smoothstep(0.22, 0.0, abs(off + 0.1)) * (1.0 - 0.6 * pr) + tone.rgb * pr * shine * 0.55;
			col *= 0.6 + 0.4 * smoothstep(-0.35, -0.25, q.y);
		} else if (off > 0.0 && off < 0.42) {
			col *= 0.72;
		}
	}
	return col;
}

// The inside of the piano at q (x across, y back from the keys), aa the size of a pixel there.
vec3 harp_at(vec2 q, float aa) {
	float ze = zend(q.x);
	float zb = 0.78 * ze;
	vec3 col = board.rgb * (0.7 + 0.3 * vnoise(vec2(q.x * 30.0, q.y * 0.7)));
	col = mix(col, board.rgb * 0.4, smoothstep(0.07, 0.05, abs(q.y - zb)));
	vec3 gold = plate.rgb * (0.5 + 0.4 * vnoise(q * 7.0 + 3.0));
	if (q.y < 1.05 || q.y > zb + 0.25) {
		col = gold;
		// The round holes in the plate's far end.
		vec2 hq = vec2(fract(q.x / 1.1) - 0.5, (q.y - (zb + 0.25 + (ze - zb - 0.25) * 0.5)) / 1.1);
		col = mix(col, lacquer.rgb + 0.02, smoothstep(0.13, 0.11, length(hq)) * step(zb + 0.25, q.y));
	}
	float gx = (q.x + 3.0) / 6.0 * N;
	float k = floor(gx);
	float dx = abs(fract(gx) - 0.5) * 0.125;
	float b = note_band(k);
	float xk = (k + 0.5) / N * 6.0 - 3.0;
	float z1 = 0.78 * zend(xk) + 0.12;
	// The hammers, under the strings.
	if (q.y > 1.12 && q.y < 1.34) {
		float oval = length(vec2(dx / 0.05, (q.y - 1.23) / 0.11));
		col = mix(col, vec3(0.85, 0.82, 0.75) * (0.25 + 0.9 * b), smoothstep(1.0, 0.8, oval));
	}
	// The strings.
	if (q.y > 0.62 && q.y < z1) {
		float env = sin(PI * (q.y - 0.62) / (z1 - 0.62));
		float w0 = k < 14.0 ? 0.014 : 0.007;
		float a = 0.045 * b * env * vib;
		float core = smoothstep(w0 + a + aa, w0 + a * 0.3, dx) * w0 / (w0 + a * 0.6);
		vec3 sc = (k < 14.0 ? vec3(0.8, 0.47, 0.27) : vec3(0.82, 0.84, 0.88)) * 0.85 + tone.rgb * b * env * shine * 1.3;
		col = mix(col, sc, clamp(core * (1.0 + 2.5 * b), 0.0, 1.0));
	}
	// The dampers, lifting as their strings sound.
	if (q.y > 1.42 && q.y < 1.74 && k < 38.0) {
		float lift = smoothstep(0.12, 0.45, b);
		col *= 1.0 - 0.4 * smoothstep(0.07, 0.04, dx) * lift;
		col = mix(col, mix(vec3(0.045), vec3(0.5, 0.08, 0.08), lift * 0.7), smoothstep(0.048, 0.04, dx));
	}
	// The tuning pins.
	float pz = 0.34 + 0.09 * mod(k, 3.0);
	col = mix(col, vec3(0.75, 0.77, 0.8), smoothstep(0.028, 0.02, length(vec2(dx, q.y - pz))));
	// The plate's struts, over the strings.
	float strut = 1e3;
	for (int s = 0; s < 4; s++) {
		strut = min(strut, abs(q.x + 1.9 - 1.25 * float(s) - 0.1 * (q.y - 1.0)));
	}
	if (q.y > 1.0 && q.y < zb + 0.3) {
		col *= 1.0 - 0.35 * smoothstep(0.2, 0.09, strut - 0.03);
		col = mix(col, gold * (0.8 + 0.4 * smoothstep(0.09, 0.0, strut)), smoothstep(0.1, 0.085, strut));
	}
	return col;
}

bool in_case(vec2 q, float pad) {
	return abs(q.x) < 3.0 + pad && q.y > 0.55 - pad && q.y < zend(q.x) + pad * 0.8;
}

// The hall as polished lacquer sees it.
vec3 hall_at(vec3 d) {
	vec3 c = vec3(0.015, 0.012, 0.012) + vec3(0.1, 0.09, 0.08) * smoothstep(0.2, 1.0, d.y);
	c += vec3(1.0, 0.95, 0.85) * smoothstep(0.93, 0.99, dot(d, normalize(vec3(0.3, 0.9, -0.3)))) * 0.9;
	return c;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	vec3 ro = vec3(2.6 + 0.5 * sin(drive * 0.017), 4.3 + 0.3 * sin(drive * 0.011), -5.6);
	vec3 fw = normalize(vec3(-0.7, 0.9, 2.0) - ro);
	vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
	vec3 up = cross(fw, rt);
	vec3 rd = normalize(fw * 1.2 + rt * p.x + up * p.y);

	// The hall: dark, a curtain far behind.
	vec3 col = vec3(0.05, 0.012, 0.016) * (0.5 + 0.5 * sin(rd.x * 60.0 + 2.0 * sin(rd.x * 17.0))) * smoothstep(-0.1, 0.3, rd.y);
	float best = 1e9;
	if (rd.y < 0.0) {
		// The stage.
		float t = (-3.0 - ro.y) / rd.y;
		vec3 q = ro + rd * t;
		best = t;
		float plank = 0.8 + 0.2 * hash1(vec2(floor(q.x * 1.5), 1.0));
		float spot = exp(-dot(q.xz - vec2(0.0, 2.0), q.xz - vec2(0.0, 2.0)) * 0.012);
		float under = smoothstep(0.0, 2.0, length(max(abs(q.xz - vec2(0.0, 2.4)) - vec2(3.0, 3.0), 0.0)));
		col = vec3(0.3, 0.2, 0.12) * plank * (0.05 + 0.45 * spot) * (0.25 + 0.75 * under);
	}
	// The front of the case, and its right side.
	float tf = (-1.0 - ro.z) / rd.z;
	vec3 qf = ro + rd * tf;
	if (tf > 0.0 && tf < best && abs(qf.x) < 3.3 && qf.y > -1.2 && qf.y < -0.3) {
		best = tf;
		col = lacquer.rgb + hall_at(reflect(rd, vec3(0.0, 0.0, -1.0))) * 0.5 + vec3(0.03) * smoothstep(-0.36, -0.3, qf.y);
	}
	float ts = (3.3 - ro.x) / rd.x;
	vec3 qs = ro + rd * ts;
	if (ts > 0.0 && ts < best && qs.z > -1.0 && qs.z < 2.55 && qs.y > -1.2 && qs.y < (qs.z > 0.3 ? 0.4 : -0.3)) {
		best = ts;
		col = lacquer.rgb + hall_at(reflect(rd, vec3(1.0, 0.0, 0.0))) * 0.5;
	}
	if (rd.y < 0.0) {
		// The keys, and the blocks at their ends.
		float tk = (-0.3 - ro.y) / rd.y;
		vec3 qk = ro + rd * tk;
		if (tk < best && abs(qk.x) < 3.3 && qk.z > -1.0 && qk.z < 0.3) {
			best = tk;
			if (abs(qk.x) < 3.0 && qk.z > -0.95) {
				col = keys_at(qk.xz) * (0.75 + 0.25 * smoothstep(0.3, 0.0, qk.z));
			} else {
				col = lacquer.rgb + hall_at(reflect(rd, vec3(0.0, 1.0, 0.0))) * 0.6;
			}
		}
		// The rim's top, and through it the inside.
		float tr = (0.4 - ro.y) / rd.y;
		vec3 qr = ro + rd * tr;
		if (tr < best && in_case(qr.xz, 0.27)) {
			if (in_case(qr.xz, 0.0)) {
				float th = -ro.y / rd.y;
				vec3 qh = ro + rd * th;
				best = th;
				if (in_case(qh.xz, 0.0)) {
					col = harp_at(qh.xz, th * 0.0009);
					// The shadow of the rim on the inside.
					float edge = min(min(3.0 - abs(qh.x), qh.z - 0.55), zend(qh.x) - qh.z);
					col *= 0.55 + 0.45 * smoothstep(0.0, 0.5, edge);
				} else {
					col = lacquer.rgb * 0.6 + vec3(0.012);
				}
			} else {
				best = tr;
				col = lacquer.rgb + hall_at(reflect(rd, vec3(0.0, 1.0, 0.0))) * 0.7;
			}
		}
	}
	// The fallboard: polished, the keys mirrored in it.
	float tb = (0.3 - ro.z) / rd.z;
	vec3 qb = ro + rd * tb;
	if (tb > 0.0 && tb < best && abs(qb.x) < 3.0 && qb.y > -0.3 && qb.y < 0.4) {
		best = tb;
		vec3 rr = vec3(rd.xy, -rd.z);
		vec3 qm = qb + rr * ((-0.3 - qb.y) / rr.y);
		col = lacquer.rgb + vec3(0.01);
		if (qm.z > -0.95) {
			col += keys_at(qm.xz) * 0.12;
		}
	}
	// The lid: polished, the strings mirrored in it.
	vec3 nl = vec3(sin(LID), -cos(LID), 0.0);
	vec3 along = vec3(cos(LID), sin(LID), 0.0);
	vec3 hinge = vec3(-3.3, 0.4, 0.0);
	float dl = dot(rd, nl);
	if (dl < -0.001) {
		float tl = dot(hinge - ro, nl) / dl;
		vec3 ql = ro + rd * tl;
		float s = dot(ql - hinge, along);
		if (tl > 0.0 && tl < best && s > 0.0 && s < 6.6 && ql.z > 0.3 && ql.z < zend(s - 3.3) + 0.25) {
			best = tl;
			vec3 rr = reflect(rd, nl);
			col = lacquer.rgb + hall_at(rr) * 0.35 + vec3(0.008);
			if (rr.y < -0.01) {
				float t2 = -ql.y / rr.y;
				vec3 qm = ql + rr * t2;
				if (in_case(qm.xz, 0.0)) {
					col += harp_at(qm.xz, (tl + t2) * 0.0009) * 0.6;
				}
			}
			float edge = min(min(s, 6.6 - s), min(ql.z - 0.3, zend(s - 3.3) + 0.25 - ql.z));
			col += vec3(0.06) * smoothstep(0.06, 0.0, edge);
		}
	}
	col *= 1.0 - 0.3 * dot(p, p);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
