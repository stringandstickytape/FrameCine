// Reel to reel (visualiser.json): the front of a reel-to-reel tape machine, drawn flat and exact. On the brushed
// plate two metal reels turn on the music's clock (drive), tape showing through their three windows; over a long
// time the tape winds from one to the other and back, one pack growing as the other shrinks. The tape runs down past
// guide rollers and across the heads, held to the capstan by its rubber roller. A counter between the reels counts.
// On the dark panel below: two lit meters, their needles the low and the high half of the sound, over scales with
// a red end; between them a round green scope tube drawing the waveform itself; knobs that turn a little with the
// bass and the top; a row of keys, the play key lit. Wooden cheeks at the sides.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float speed = 0.5;
uniform float lamp = 0.7;
uniform vec4 face : source_color = vec4(0.62, 0.63, 0.65, 1.0);
uniform vec4 tape : source_color = vec4(0.3, 0.17, 0.09, 1.0);
uniform vec4 meter : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform vec4 scope : source_color = vec4(0.3, 1.0, 0.5, 1.0);
uniform vec4 cheek : source_color = vec4(0.3, 0.14, 0.06, 1.0);

float hash1(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float seg_sd(vec2 q, vec2 a, vec2 b) {
	vec2 pa = q - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

float box_sd(vec2 q, vec2 h, float r) {
	vec2 d = abs(q) - h + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
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

// A reel at q from its middle, turned by ang, its tape wound out to pack.
vec3 reel_at(vec2 q, float ang, float pack, vec3 under, float px) {
	float r = length(q);
	if (r > 0.262) {
		return under * (1.0 - 0.35 * smoothstep(0.29, 0.262, length(q - vec2(0.008, -0.01))));
	}
	float a = atan(q.y, q.x);
	vec3 col = under * 0.4;
	vec3 tp = tape.rgb * (0.7 + 0.3 * smoothstep(0.08, pack, r)) * (0.85 + 0.15 * cos(a * 2.0 - 1.0));
	col = mix(col, tp, smoothstep(pack + px, pack - px, r));
	float sect = abs(fract((a + ang) * 3.0 / TAU) - 0.5);
	float win = smoothstep(0.3, 0.27, sect) * smoothstep(0.1, 0.11, r) * smoothstep(0.23, 0.22, r);
	vec3 fl = face.rgb * (0.48 + 0.2 * cos(a * 2.0 - 0.8));
	col = mix(col, fl, (1.0 - win) * smoothstep(0.25 + px, 0.25 - px, r));
	col *= 1.0 - 0.35 * smoothstep(0.01, 0.0, abs(r - 0.25));
	vec3 hc = vec3(0.12) + 0.08 * cos(a * 2.0 - 0.8);
	float notch = smoothstep(0.1, 0.07, abs(fract((a + ang) * 3.0 / TAU + 0.5) - 0.5)) * step(0.03, r) * step(r, 0.065);
	hc = mix(hc, vec3(0.03), notch);
	hc = mix(hc, face.rgb * 0.8, smoothstep(0.022, 0.018, r));
	return mix(col, hc, smoothstep(0.075 + px, 0.075 - px, r));
}

// A meter at q from its middle, its needle at v (0..1).
vec3 vu_at(vec2 q, float v, vec3 under) {
	float sd = box_sd(q, vec2(0.2, 0.125), 0.01);
	if (sd > 0.014) {
		return under;
	}
	vec3 fc = meter.rgb * (0.3 + 0.6 * lamp) * (0.75 + 0.25 * smoothstep(0.125, -0.125, q.y));
	vec2 pv = q - vec2(0.0, -0.16);
	float pr = length(pv);
	float pa = atan(pv.x, pv.y);
	vec3 ink = pa > 0.38 ? vec3(0.7, 0.08, 0.05) : vec3(0.08);
	float on_scale = step(abs(pa), 0.79);
	fc = mix(fc, ink, smoothstep(0.004, 0.002, abs(pr - 0.22)) * on_scale);
	fc = mix(fc, vec3(0.7, 0.08, 0.05), step(0.38, pa) * on_scale * step(abs(pr - 0.233), 0.007));
	float tk = abs(fract(pa / 0.13 + 0.5) - 0.5) * 0.13 * pr;
	fc = mix(fc, ink, smoothstep(0.003, 0.0015, tk) * step(0.22, pr) * step(pr, 0.25) * on_scale);
	fc = mix(fc, vec3(0.1), step(box_sd(q - vec2(0.0, -0.085), vec2(0.03, 0.012), 0.004), 0.0));
	float na = mix(-0.75, 0.75, clamp(v, 0.0, 1.0));
	vec2 nd = vec2(sin(na), cos(na));
	vec2 ps = pv - vec2(0.006, -0.006);
	float shadow = smoothstep(0.006, 0.002, abs(dot(ps, vec2(nd.y, -nd.x)))) * step(0.0, dot(ps, nd)) * step(dot(ps, nd), 0.255);
	fc *= 1.0 - 0.3 * shadow;
	float needle = smoothstep(0.004, 0.002, abs(dot(pv, vec2(nd.y, -nd.x)))) * step(0.0, dot(pv, nd)) * step(dot(pv, nd), 0.255);
	fc = mix(fc, vec3(0.05), needle);
	fc += 0.06 * smoothstep(0.0, 0.3, q.y + q.x * 0.5);
	vec3 col = mix(vec3(0.1), fc, smoothstep(0.0, -0.004, sd));
	return mix(under, col, smoothstep(0.014, 0.01, sd));
}

// A knob at q from its middle, radius r, turned to ang.
vec3 knob_at(vec2 q, float r, float ang, vec3 under) {
	float l = length(q);
	if (l > r + 0.012) {
		return under * (1.0 - 0.4 * smoothstep(r + 0.012, r, length(q - vec2(0.004, -0.006))));
	}
	float a = atan(q.y, q.x);
	vec3 c = face.rgb * (0.35 + 0.3 * abs(cos(a - 0.9))) * (0.9 + 0.1 * sin(a * 40.0));
	c = mix(c, face.rgb * (0.6 + 0.25 * cos(a * 2.0 - 0.8)), smoothstep(r * 0.72, r * 0.68, l));
	vec2 nd = vec2(sin(ang), cos(ang));
	float mark = smoothstep(0.005, 0.003, abs(dot(q, vec2(nd.y, -nd.x)))) * step(r * 0.25, dot(q, nd)) * step(dot(q, nd), r * 0.66);
	c = mix(c, vec3(0.05), mark);
	return mix(under, c, smoothstep(r + 0.002, r - 0.002, l));
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float px = 1.0 / size.y;
	float brushed = hash1(vec2(floor(p.y * 360.0), 3.0)) * 0.5 + hash1(vec2(floor(p.y * 120.0), floor(p.x * 5.0))) * 0.5;
	vec3 col = face.rgb * (0.55 + 0.1 * brushed + 0.14 * smoothstep(-0.2, 0.5, p.y));
	col += 0.07 * exp(-pow((p.x + p.y * 0.3 - 0.1) * 2.5, 2.0));
	if (p.y < -0.13) {
		col = vec3(0.04, 0.04, 0.045) * (0.8 + 0.25 * brushed);
	}
	col *= 1.0 - 0.5 * smoothstep(0.004, 0.0, abs(p.y + 0.13));

	// The tape's path, the rollers, the heads.
	float wind = abs(fract(drive * speed * 0.003) * 2.0 - 1.0);
	float pack_l = mix(0.215, 0.1, wind);
	float pack_r = sqrt(0.056225 - pack_l * pack_l);
	vec2 cl = vec2(-0.43, 0.2);
	vec2 cr = vec2(0.43, 0.2);
	float tp = seg_sd(p, cl + pack_l * vec2(-0.3, -0.954), vec2(-0.26, -0.06));
	tp = min(tp, seg_sd(p, vec2(-0.24, -0.08), vec2(0.24, -0.08)));
	tp = min(tp, seg_sd(p, vec2(0.26, -0.06), cr + pack_r * vec2(0.3, -0.954)));
	col = mix(col, tape.rgb * 0.8, smoothstep(0.004, 0.002, tp));
	for (int s = 0; s < 2; s++) {
		vec2 g = p - vec2(s == 0 ? -0.24 : 0.24, -0.06);
		col = mix(col, face.rgb * (0.6 + 0.3 * cos(atan(g.y, g.x) * 2.0 - 0.8)), smoothstep(0.02 + px, 0.02 - px, length(g)));
		col = mix(col, vec3(0.1), smoothstep(0.006, 0.004, length(g)));
	}
	float hb = box_sd(p - vec2(0.0, -0.03), vec2(0.13, 0.042), 0.012);
	col *= 1.0 - 0.3 * smoothstep(0.02, 0.0, box_sd(p - vec2(0.006, -0.038), vec2(0.13, 0.042), 0.012));
	col = mix(col, vec3(0.1, 0.1, 0.11) + 0.08 * smoothstep(-0.07, 0.01, p.y), smoothstep(px, -px, hb));
	for (int s = 0; s < 3; s++) {
		float hd = box_sd(p - vec2(float(s - 1) * 0.07, -0.066), vec2(0.02, 0.012), 0.004);
		col = mix(col, face.rgb * 0.85, smoothstep(px, -px, hd));
	}
	col = mix(col, face.rgb * 0.9, smoothstep(0.008 + px, 0.008 - px, length(p - vec2(0.17, -0.07))));
	col = mix(col, vec3(0.05), smoothstep(0.022 + px, 0.022 - px, length(p - vec2(0.17, -0.103))));

	// The reels.
	col = reel_at(p - cl, drive * speed * 0.9, pack_l, col, px);
	col = reel_at(p - cr, drive * speed * 0.7 + 1.0, pack_r, col, px);

	// The counter.
	vec2 cq = p - vec2(0.0, 0.33);
	float cb = box_sd(cq, vec2(0.085, 0.03), 0.004);
	if (cb < 0.006) {
		vec3 cc = vec3(0.02);
		float dx = (cq.x + 0.08) / 0.04;
		float k = floor(dx);
		if (k >= 0.0 && k < 4.0) {
			float count = floor(drive * speed * 2.0);
			int d = int(mod(floor(count / pow(10.0, 3.0 - k)), 10.0));
			cc += vec3(0.9, 0.9, 0.85) * digit_at(vec2((fract(dx) - 0.5) * 1.3, cq.y / 0.021), d);
		}
		col = mix(vec3(0.15), cc, smoothstep(0.0, -0.003, cb));
	}

	// The meters, the scope, the knobs, the keys.
	float low = clamp(pow(band_between(0.0, 0.4), 0.8) * 1.15, 0.0, 1.0);
	float high = clamp(pow(band_between(0.4, 1.0), 0.8) * 1.4, 0.0, 1.0);
	col = vu_at(p - vec2(-0.52, -0.3), low, col);
	col = vu_at(p - vec2(0.52, -0.3), high, col);
	vec2 sq = p - vec2(0.0, -0.285);
	float sr = length(sq);
	if (sr < 0.125) {
		vec3 sc = scope.rgb * 0.05 + vec3(0.0, 0.012, 0.006);
		vec2 gr = abs(fract(sq / 0.035 + 0.5) - 0.5) * 0.035;
		sc += scope.rgb * 0.1 * smoothstep(0.002, 0.0005, min(gr.x, gr.y));
		float u = sq.x / 0.2 + 0.5;
		float w0 = wave_at(u) * 0.06;
		float w1 = wave_at(u + 0.01) * 0.06;
		float dist = abs(sq.y - w0) / sqrt(1.0 + (w1 - w0) * (w1 - w0) / 0.000004);
		sc += scope.rgb * (smoothstep(0.004, 0.001, dist) + 0.3 * exp(-dist * 90.0)) * (0.5 + 0.5 * lamp);
		sc *= smoothstep(0.108, 0.09, sr);
		sc += 0.05 * smoothstep(0.0, 0.2, sq.y + sq.x * 0.4) * step(sr, 0.105);
		col = mix(vec3(0.12) + 0.06 * cos(atan(sq.y, sq.x) * 2.0 - 0.8), sc, smoothstep(0.108, 0.105, sr));
	}
	col = knob_at(p - vec2(-0.235, -0.24), 0.04, -2.0 + 3.0 * bass, col);
	col = knob_at(p - vec2(0.235, -0.24), 0.04, -2.0 + 3.0 * treble, col);
	col = knob_at(p - vec2(-0.235, -0.36), 0.028, 0.6, col);
	col = knob_at(p - vec2(0.235, -0.36), 0.028, -0.9, col);
	for (int s = 0; s < 5; s++) {
		float kd = box_sd(p - vec2(float(s - 2) * 0.07, -0.452), vec2(0.028, 0.02), 0.004);
		vec3 kc = s == 3 ? scope.rgb * (0.3 + 0.5 * lamp) : vec3(0.22, 0.22, 0.23);
		kc *= 0.8 + 0.3 * smoothstep(-0.47, -0.435, p.y);
		col = mix(col, kc, smoothstep(px, -px, kd));
	}
	// A lamp, the screws, the cheeks.
	float ld = length(p - vec2(-0.78, -0.44));
	col = mix(col, meter.rgb * (0.4 + 0.6 * lamp), smoothstep(0.012, 0.01, ld));
	col += meter.rgb * 0.15 * lamp * exp(-ld * ld * 900.0);
	vec2 scq = vec2(abs(p.x) - 0.8, abs(p.y - 0.185) - 0.275);
	float scd = length(scq);
	col = mix(col, face.rgb * (0.35 + 0.3 * step(0.002, abs(scq.x - scq.y))), smoothstep(0.012, 0.01, scd));
	if (abs(p.x) > 0.84) {
		float grain = hash1(vec2(floor(p.x * 300.0), 1.0)) * 0.5 + 0.5 * sin(p.x * 180.0 + 3.0 * sin(p.y * 5.0));
		col = cheek.rgb * (0.7 + 0.25 * grain) * (0.6 + 0.4 * smoothstep(0.89, 0.84, abs(p.x)));
	}
	col *= 1.0 - 0.3 * dot(p, p);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
