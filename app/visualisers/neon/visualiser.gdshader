// Neon (visualiser.json): glass-tube signs on a brick wall at night, over a wet pavement that mirrors them. The word
// LIVE (straight tubes) glows with the low notes, over a bar that brightens on each beat; a pair of joined notes
// glows with the middle; a star glows with the high notes; three arcs of sound light one after another as the
// music gets louder; and along the foot of the wall stand fourteen columns of five short tubes, each column a part
// of the spectrum, lit as high as its part sounds. Each tube is a distance to a line: a white-hot core, a coloured
// halo, and its light on the bricks. The wall is drawn twice: once straight, once upside down in the puddles, where
// the high notes shake the picture.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float power = 0.75;
uniform float wet = 0.6;
uniform vec4 tube_a : source_color = vec4(1.0, 0.15, 0.4, 1.0);
uniform vec4 tube_b : source_color = vec4(0.1, 0.8, 1.0, 1.0);
uniform vec4 tube_c : source_color = vec4(1.0, 0.7, 0.1, 1.0);
uniform vec4 brick : source_color = vec4(0.5, 0.22, 0.16, 1.0);

const float FOOT = -0.3;

float hash1(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise1(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x), mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

float seg_sd(vec2 q, vec2 a, vec2 b) {
	vec2 pa = q - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// A five-pointed star of radius r, its inner corners at r * rf.
float star_sd(vec2 q0, float r, float rf) {
	vec2 k1 = vec2(0.809016994, -0.587785252);
	vec2 k2 = vec2(-k1.x, k1.y);
	vec2 q = vec2(abs(q0.x), q0.y);
	q -= 2.0 * max(dot(k1, q), 0.0) * k1;
	q -= 2.0 * max(dot(k2, q), 0.0) * k2;
	q.x = abs(q.x);
	q.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(q, ba) / dot(ba, ba), 0.0, r);
	return length(q - ba * h) * sign(q.y * ba.x - q.x * ba.y);
}

// An arc of radius r about the +x direction, half-angle a.
float arc_sd(vec2 q, float r, float a) {
	vec2 s = vec2(q.x, abs(q.y));
	if (atan(s.y, s.x) < a) {
		return abs(length(s) - r);
	}
	return length(s - r * vec2(cos(a), sin(a)));
}

// A tilted oval ring (a note's head).
float head_sd(vec2 q) {
	vec2 r = vec2(0.94 * q.x + 0.34 * q.y, -0.34 * q.x + 0.94 * q.y);
	return abs(length(r / vec2(0.038, 0.026)) - 1.0) * 0.026;
}

// Adds the tube at distance d, of colour c, lit to k: light to shine (what falls on the wall) and the glass to
// glass (rgb and how much of the pixel it covers).
void tube(inout vec3 shine, inout vec4 glass, float d, vec3 c, float k, float reach, float px) {
	float lit = k * power;
	shine += c * lit * (0.0007 / (d * d + 0.0007) * 0.9 + exp(-d * 7.0) * 0.32) * smoothstep(reach, reach * 0.4, d);
	float m = smoothstep(0.0058 + px, 0.0058 - px, d);
	if (m > 0.0) {
		float across = d / 0.0058;
		vec3 gc = mix(c, vec3(1.0), 0.75 * (1.0 - across * across)) * (0.2 + 2.4 * lit) + vec3(0.06, 0.06, 0.07);
		glass = vec4(mix(glass.rgb, gc, m), max(glass.a, m));
	}
}

// The wall at q: bricks in the light of the signs, and the signs.
vec3 wall_at(vec2 q, float px) {
	vec3 shine = vec3(0.0);
	vec4 glass = vec4(0.0);
	float k_a = 0.6 + 0.4 * bass;
	float k_b = 0.55 + 0.45 * mid;
	float k_c = 0.5 + 0.5 * treble;

	// LIVE.
	float d = seg_sd(q, vec2(-0.72, 0.36), vec2(-0.72, 0.2));
	d = min(d, seg_sd(q, vec2(-0.72, 0.2), vec2(-0.64, 0.2)));
	d = min(d, seg_sd(q, vec2(-0.58, 0.36), vec2(-0.58, 0.2)));
	d = min(d, seg_sd(q, vec2(-0.52, 0.36), vec2(-0.47, 0.2)));
	d = min(d, seg_sd(q, vec2(-0.47, 0.2), vec2(-0.42, 0.36)));
	d = min(d, seg_sd(q, vec2(-0.36, 0.36), vec2(-0.36, 0.2)));
	d = min(d, seg_sd(q, vec2(-0.36, 0.36), vec2(-0.28, 0.36)));
	d = min(d, seg_sd(q, vec2(-0.36, 0.28), vec2(-0.295, 0.28)));
	d = min(d, seg_sd(q, vec2(-0.36, 0.2), vec2(-0.28, 0.2)));
	tube(shine, glass, d, tube_a.rgb, k_a, 2.0, px);
	tube(shine, glass, seg_sd(q, vec2(-0.74, 0.14), vec2(-0.26, 0.14)), tube_c.rgb, 0.5 + 0.4 * beat, 2.0, px);

	// Two notes joined by two beams.
	vec2 h1 = vec2(-0.07, -0.01);
	vec2 h2 = vec2(0.09, 0.03);
	d = min(head_sd(q - h1), head_sd(q - h2));
	d = min(d, seg_sd(q, h1 + vec2(0.037, 0.012), h1 + vec2(0.037, 0.27)));
	d = min(d, seg_sd(q, h2 + vec2(0.037, 0.012), h2 + vec2(0.037, 0.27)));
	d = min(d, seg_sd(q, h1 + vec2(0.037, 0.27), h2 + vec2(0.037, 0.27)));
	d = min(d, seg_sd(q, h1 + vec2(0.037, 0.225), h2 + vec2(0.037, 0.225)));
	tube(shine, glass, d, tube_b.rgb, k_b, 2.0, px);

	// The arcs of sound: one more lit as the music gets louder.
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		float on = smoothstep(fi * 0.2 + 0.08, fi * 0.2 + 0.3, level * 1.3);
		tube(shine, glass, arc_sd(q - vec2(0.2, 0.15), 0.07 + 0.045 * fi, 0.6), mix(tube_b.rgb, tube_a.rgb, fi * 0.5), 0.12 + 0.88 * on, 2.0, px);
	}

	// The star.
	tube(shine, glass, abs(star_sd(q - vec2(0.6, 0.25), 0.125, 0.45)), tube_c.rgb, k_c, 2.0, px);
	tube(shine, glass, abs(length(q - vec2(0.6, 0.25)) - 0.165), tube_a.rgb, 0.35 + 0.65 * band_between(0.55, 0.75), 2.0, px);

	// The columns along the foot of the wall.
	float gx = (q.x + 0.7) / 0.1;
	float id0 = floor(gx);
	for (int j = -1; j <= 1; j++) {
		float id = id0 + float(j);
		if (id < 0.0 || id > 13.0) {
			continue;
		}
		float x = (id + 0.5) * 0.1 - 0.7;
		float b = band(0.04 + 0.92 * id / 13.0);
		for (int s = 0; s < 5; s++) {
			float fs = float(s);
			float y = -0.235 + fs * 0.042;
			float on = smoothstep(fs / 5.0, fs / 5.0 + 0.14, b * 1.15);
			vec3 c = s == 4 ? tube_a.rgb : (s == 3 ? tube_c.rgb : tube_b.rgb);
			tube(shine, glass, seg_sd(q, vec2(x, y - 0.011), vec2(x, y + 0.011)), c, 0.06 + 0.94 * on, 0.14, px);
		}
	}

	// The bricks.
	float row = floor(q.y / 0.042);
	vec2 bq = vec2(q.x / 0.12 + 0.5 * mod(row, 2.0), q.y / 0.042);
	vec2 bid = floor(bq);
	vec2 bf = fract(bq);
	float mortar = min(min(bf.x, 1.0 - bf.x) * 0.12, min(bf.y, 1.0 - bf.y) * 0.042);
	float face = smoothstep(0.002, 0.005, mortar);
	float rough = noise1(q * 140.0) * 0.5 + noise1(q * 47.0) * 0.5;
	vec3 alb = brick.rgb * (0.55 + 0.6 * hash1(bid)) * (0.7 + 0.5 * rough);
	alb = mix(vec3(0.16, 0.15, 0.14) * (0.7 + 0.5 * rough), alb, face);
	// A brick's upper edge takes more of the light from above it, its lower edge less.
	float edge = (smoothstep(0.7, 1.0, bf.y) - smoothstep(0.3, 0.0, bf.y)) * face;
	vec3 col = alb * (vec3(0.035, 0.037, 0.05) + shine * (1.4 + 0.35 * edge));
	// An iron box and the pipe that feeds the signs.
	vec2 xq = abs(q - vec2(0.82, -0.14)) - vec2(0.035, 0.05);
	float box_d = max(xq.x, xq.y);
	float pipe_d = max(abs(q.x - 0.82) - 0.006, -0.09 - q.y);
	vec3 iron = vec3(0.12, 0.13, 0.14) * (0.02 + shine) * (1.0 + 0.5 * smoothstep(0.004, -0.004, min(abs(xq.x), abs(xq.y)) - 0.004));
	col = mix(col, iron, max(smoothstep(px, -px, box_d), smoothstep(px, -px, pipe_d)));
	// The glass over it all, and its halo in the air.
	col = mix(col, glass.rgb, glass.a);
	col += shine * 0.08;
	return col;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float px = 1.0 / size.y;
	p.x += 0.02 * sin(drive * 0.02);
	vec3 col;
	if (p.y > FOOT) {
		col = wall_at(p, px);
		// Where the wall meets the ground: a dark line.
		col *= 0.45 + 0.55 * smoothstep(0.0, 0.03, p.y - FOOT);
	} else {
		// The pavement: slabs going away from the wall, wet, with puddles that mirror it.
		float down = FOOT - p.y;
		float z = 0.25 / (0.25 - down * 0.9);
		vec2 g = vec2(p.x * z, z * 3.0);
		vec2 sg = abs(fract(g * vec2(2.2, 1.0)) - 0.5);
		float joint = smoothstep(0.47, 0.5, max(sg.x, sg.y));
		float puddle = smoothstep(0.42, 0.62, noise1(g * vec2(1.6, 0.9) + 4.0) * 0.7 + noise1(g * 4.3) * 0.3) * wet;
		float shake = (0.25 + 1.5 * treble) * (0.4 + 0.6 * puddle);
		vec2 wob = vec2(noise1(vec2(p.x * 26.0, down * 130.0 - drive * 1.1)) - 0.5, noise1(vec2(p.x * 21.0 + 9.0, down * 110.0 + drive * 0.8)) - 0.5);
		vec2 rq = vec2(p.x + wob.x * 0.03 * shake, FOOT + down * 2.0 + wob.y * 0.04 * shake);
		vec3 mirrored = wall_at(rq, px * 3.0);
		float grit = noise1(g * 60.0);
		vec3 slab = vec3(0.05, 0.05, 0.055) * (0.7 + 0.5 * grit) * (1.0 - 0.5 * joint);
		// The light the signs throw down on the stone, roughly: what the wall shows a little above its foot.
		col = slab * (0.25 + 2.0 * dot(mirrored, vec3(0.33))) + mirrored * (0.1 + 0.75 * puddle) * (0.35 + 0.65 * wet) * smoothstep(0.26, 0.0, down);
		col *= 0.5 + 0.5 * smoothstep(0.0, 0.02, down);
	}
	col = 1.0 - exp(-col * 1.6);
	col *= 1.0 - 0.3 * dot(p, p);
	COLOR = vec4(col, 1.0);
}
