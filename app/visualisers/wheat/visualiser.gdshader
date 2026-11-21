// Wheat field (visualiser.json): a field of ripe wheat on a summer day, reaching to the horizon, with a windmill,
// far hills, heaped clouds and the sun. The wind is the music: five trains of gusts cross the field, each a part of
// the spectrum (the low notes the longest waves), and where a gust bends the wheat it shines pale; the shadows of
// the clouds drift over it on the music's clock (drive), which also turns the mill's sails. Poppies stand in the
// field, and close to the eye three ranks of stalks sway with the low and the middle notes, each ear drawn with its
// grains and its beard. Swallows fly across.
// The field is a plane seen in true perspective; the clouds are a ceiling of noise; the near stalks are drawn flat.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float gust = 0.7;
uniform float flowers = 0.5;
uniform vec4 wheat : source_color = vec4(0.85, 0.62, 0.2, 1.0);
uniform vec4 sky : source_color = vec4(0.2, 0.45, 0.85, 1.0);
uniform vec4 poppy : source_color = vec4(0.9, 0.1, 0.05, 1.0);
uniform vec4 sun : source_color = vec4(1.0, 0.93, 0.75, 1.0);
uniform vec4 mill : source_color = vec4(0.9, 0.88, 0.82, 1.0);

const float HOR = 0.07;
const vec2 SUN_AT = vec2(0.52, 0.37);

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

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * noise1(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

float seg_sd(vec2 q, vec2 a, vec2 b) {
	vec2 pa = q - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// How thick the cloud is over the ground point g.
float cloud_at(vec2 g) {
	return smoothstep(0.48, 0.74, fbm(g * 0.22 + vec2(drive * 0.012, drive * 0.004)));
}

// How hard the wind bends the wheat at the ground point g: -1..1.
float wind_at(vec2 g) {
	float s = 0.0;
	for (int k = 0; k < 5; k++) {
		float fk = float(k);
		float ang = 0.5 + fk * 0.37;
		vec2 dir = vec2(cos(ang), sin(ang));
		float f = 0.45 * pow(1.75, fk);
		float b = band_between(fk / 5.0 + 0.02, fk / 5.0 + 0.18);
		s += (0.22 + 0.7 * b) * sin(dot(dir, g) * f - drive * (0.5 + 0.3 * fk) + fk * 1.9) / (1.0 + 0.25 * fk);
	}
	return clamp(s * 0.55 * gust, -1.0, 1.0);
}

// One rank of near stalks: spacing sp, their ears about y = top. Paints over col.
void rank(inout vec3 col, vec2 p, float sp, float top, float seed, float shade, float px) {
	float gx = p.x / sp;
	float id0 = floor(gx);
	for (int j = -1; j <= 1; j++) {
		float id = id0 + float(j);
		float h1 = hash1(vec2(id, seed));
		float h2 = hash1(vec2(id, seed + 7.3));
		float x0 = (id + 0.5 + (h1 - 0.5) * 0.7) * sp;
		float yt = top + (h2 - 0.5) * 0.11;
		float t = (p.y + 0.56) / (yt + 0.56);
		if (t > 1.25) {
			continue;
		}
		float bend = (0.35 * sin(x0 * 2.6 - drive * 1.1 + seed) * (0.45 + 0.55 * bass) + 0.2 * sin(x0 * 8.0 - drive * 2.1 + h1 * 6.0) * (0.4 + 0.6 * mid)) * 0.11 * gust + (h2 - 0.5) * 0.03;
		float sc = sp / 0.07;
		float xs = x0 + bend * t * t;
		float dx = p.x - xs;
		vec3 base = wheat.rgb * shade * (0.55 + 0.5 * t) * (0.85 + 0.3 * h1);
		// The stalk.
		if (t < 0.8) {
			col = mix(col, base * 0.8, smoothstep(0.0028 * sc + px, 0.0028 * sc - px, abs(dx)));
		}
		// The beard: fine rays up and out from the ear.
		vec2 bq = vec2(dx - bend * 0.25 * (t - 0.8), p.y - (yt + 0.56) * 0.8 + 0.56);
		float br = length(bq);
		float ba = atan(bq.x, bq.y);
		if (bq.y > 0.0 && br < 0.11 * sc && abs(ba) < 0.34) {
			float ray = abs(fract(ba * 14.0 + h1) - 0.5) / 14.0 * br;
			float m = smoothstep(0.0012 * sc + px, 0.0012 * sc - px * 0.5, ray) * smoothstep(0.11 * sc, 0.07 * sc, br) * smoothstep(0.34, 0.2, abs(ba));
			col = mix(col, base * 1.25, m * 0.7);
		}
		// The ear: a spindle of grains in a herring-bone.
		float e = (t - 0.78) / 0.24;
		if (e > 0.0 && e < 1.0) {
			float wdt = 0.011 * sc * pow(sin(PI * e), 0.6);
			float ex = dx / max(wdt, 1e-4);
			float grains = abs(fract(e * 7.0 + abs(ex) * 0.45) - 0.5);
			vec3 ec = base * (1.0 + 0.25 * sqrt(max(1.0 - ex * ex, 0.0))) * (0.8 + 0.5 * grains) * (0.9 + 0.2 * step(0.0, ex));
			col = mix(col, ec, smoothstep(wdt + px, wdt - px, abs(dx)));
		}
	}
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float px = 1.0 / size.y;
	vec3 haze = mix(sky.rgb, vec3(0.9, 0.92, 0.95), 0.72);
	vec3 col;
	float sd2 = dot(p - SUN_AT, p - SUN_AT);

	if (p.y > HOR) {
		// The sky, and the clouds on a ceiling above.
		float up = p.y - HOR;
		col = mix(haze, sky.rgb, smoothstep(0.0, 0.45, up));
		vec2 g = vec2(p.x, 1.0) / (up + 0.06) * 3.0;
		float c = cloud_at(g);
		float c_sun = cloud_at(g + normalize(SUN_AT - p) * 1.1);
		vec3 cc = mix(vec3(0.55, 0.58, 0.66), vec3(1.0, 0.98, 0.95), clamp(0.55 + 1.2 * (c - c_sun), 0.0, 1.0));
		cc = mix(cc, sun.rgb, 0.25 * exp(-sd2 * 6.0));
		col = mix(col, cc, c * smoothstep(0.0, 0.07, up));
		col += sun.rgb * (exp(-sd2 * 900.0) * 1.2 + exp(-sd2 * 30.0) * 0.3 * (1.0 - 0.5 * c)) * (0.9 + 0.2 * level);
		// Far hills, then a line of trees.
		float hill = HOR + 0.018 + 0.03 * noise1(vec2(p.x * 2.3 + 5.0, 0.0)) + 0.01 * noise1(vec2(p.x * 9.0, 3.0));
		col = mix(col, mix(vec3(0.3, 0.42, 0.5), haze, 0.35), smoothstep(px, -px, p.y - hill));
		float trees = HOR + 0.006 + 0.012 * noise1(vec2(p.x * 38.0, 1.0)) * smoothstep(0.2, 0.6, noise1(vec2(p.x * 5.0, 8.0)));
		col = mix(col, vec3(0.12, 0.22, 0.12), smoothstep(px, -px, p.y - trees));
	} else {
		// The field: a plane one unit under the eye.
		float z = 1.0 / (HOR - p.y + 0.004);
		vec2 g = vec2(p.x * z, z);
		float far = smoothstep(2.0, 40.0, z);
		float w = wind_at(g);
		float streak = noise1(vec2(g.x * 26.0, g.y * 5.0)) * (1.0 - smoothstep(1.0, 9.0, z));
		float mottle = noise1(g * 1.3) * 0.5 + noise1(g * 4.1) * 0.5;
		vec3 fc = wheat.rgb * (0.62 + 0.25 * mottle + 0.22 * streak);
		fc = mix(fc, wheat.rgb * 1.2 + vec3(0.22, 0.2, 0.12), smoothstep(-0.1, 1.0, w) * 0.42);
		fc *= 1.0 - 0.18 * smoothstep(0.0, -1.0, w);
		// The tracks the tractor left: pairs of lines to the horizon.
		float track = abs(abs(fract(g.x / 3.2 + 0.5) - 0.5) * 3.2 - 0.3);
		fc *= 1.0 - 0.3 * smoothstep(0.07, 0.03, track) * (1.0 - far);
		// The clouds' shadows.
		fc *= 1.0 - 0.42 * cloud_at(g * 3.0 + vec2(0.0, 2.0));
		// Poppies: each a small disc on a stalk, swaying.
		if (z < 9.0 && flowers > 0.01) {
			for (int j = 0; j < 2; j++) {
				vec2 cell = vec2(floor(g.x * 2.2), floor(g.y * 2.2) - float(j));
				float h1 = hash1(cell + 3.1);
				if (h1 > flowers * 0.55) {
					continue;
				}
				vec2 cg = (cell + 0.2 + 0.6 * vec2(hash1(cell + 11.0), hash1(cell + 23.0))) / 2.2;
				float cz = max(cg.y, 0.3);
				vec2 at = vec2(cg.x / cz + 0.012 * wind_at(cg) / cz, HOR - 0.955 / cz);
				float rad = (0.022 + 0.012 * h1) / cz;
				vec2 fq = (p - at) / rad;
				float fr = length(fq);
				vec3 pc = poppy.rgb * (0.65 + 0.45 * smoothstep(1.0, 0.2, fr)) * (0.85 + 0.15 * sin(atan(fq.y, fq.x) * 4.0 + h1 * 9.0));
				pc = mix(pc, vec3(0.05, 0.03, 0.05), smoothstep(0.3, 0.2, fr));
				fc = mix(fc, pc, smoothstep(1.0, 1.0 - 2.0 * px / rad, fr));
			}
		}
		col = mix(fc, mix(wheat.rgb, haze, 0.6), far * 0.85);
		col += sun.rgb * 0.12 * exp(-sd2 * 5.0);
	}

	// The windmill on the horizon: a tower, a cap, four sails turning.
	vec2 mq = p - vec2(-0.43, HOR);
	if (abs(mq.x) < 0.14 && mq.y > -0.01 && mq.y < 0.27) {
		float tw = mix(0.021, 0.012, clamp(mq.y / 0.125, 0.0, 1.0));
		float tower = max(abs(mq.x) - tw, max(mq.y - 0.125, -mq.y - 0.004));
		vec3 tc = mill.rgb * (0.6 + 0.4 * smoothstep(-tw, tw, mq.x));
		tc = mix(tc, vec3(0.1), smoothstep(0.004, 0.003, length(vec2(mq.x, (mq.y - 0.07) * 0.6))));
		col = mix(col, tc, smoothstep(px, -px, tower));
		float cap = length((mq - vec2(0.0, 0.125)) * vec2(1.0, 1.5)) - 0.015;
		col = mix(col, vec3(0.25, 0.2, 0.18), smoothstep(px, -px, max(cap, 0.125 - mq.y)));
		vec2 hq = mq - vec2(0.0, 0.132);
		float sa = drive * 0.3;
		vec2 rq = vec2(cos(sa) * hq.x + sin(sa) * hq.y, -sin(sa) * hq.x + cos(sa) * hq.y);
		for (int s = 0; s < 4; s++) {
			// The spar, and the frame on one side of it.
			float spar = seg_sd(rq, vec2(0.0), vec2(0.115, 0.0)) - 0.0018;
			col = mix(col, vec3(0.22, 0.17, 0.13), smoothstep(px, -px, spar));
			vec2 lq = rq - vec2(0.07, 0.011);
			vec2 la = abs(lq) - vec2(0.043, 0.009);
			float frame = max(la.x, la.y);
			float bars = min(abs(fract(lq.x / 0.0143 + 0.5) - 0.5) * 0.0143, abs(abs(lq.y) - 0.0045) + 0.0005);
			float lat = max(frame, min(bars - 0.0012, -frame - 0.0018));
			col = mix(col, mill.rgb * 0.85, smoothstep(px, -px, frame) * 0.35);
			col = mix(col, vec3(0.3, 0.24, 0.18), smoothstep(px, -px, lat));
			rq = vec2(-rq.y, rq.x);
		}
	}

	// Swallows.
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float t = drive * (0.11 + 0.03 * fi) + fi * 2.4;
		vec2 at = vec2(1.1 * sin(t + fi), 0.2 + 0.1 * sin(t * 1.7 + fi * 2.0) - 0.05 * fi);
		vec2 q = (p - at) / (0.02 + 0.006 * fi);
		q.x *= cos(t + fi) > 0.0 ? 1.0 : -1.0;
		if (abs(q.x) < 1.6 && abs(q.y) < 1.6) {
			float flap = 0.45 * sin(drive * 6.0 + fi * 2.0);
			float wing = abs(q.y - abs(q.x) * flap + 0.25 * q.x * q.x) - 0.1 * (1.0 - abs(q.x));
			float body = length(q * vec2(0.55, 2.2)) - 0.3;
			float bird = min(max(wing, abs(q.x) - 1.0), body);
			col = mix(col, vec3(0.05, 0.06, 0.1), smoothstep(px * 50.0, 0.0, bird) * 0.9);
		}
	}

	// Three ranks of stalks close to the eye, the nearest the biggest and the darkest.
	if (p.y < -0.05) {
		rank(col, p, 0.045, -0.3, 1.0, 0.95, px);
		rank(col, p, 0.065, -0.36, 2.0, 0.78, px);
		rank(col, p, 0.095, -0.41, 3.0, 0.6, px);
	}
	col *= 1.0 - 0.22 * dot(p, p);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
