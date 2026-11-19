// Contour map (visualiser.json): a printed topographic map, folded and opened out. Land is tinted in steps by height
// (green lowlands, tan uplands, pale tops), shaded from the north-west, with brown contour lines (every fifth one
// heavier) and sea lined with blue water-lines along the coast. Nine summits are each a part of the spectrum: they
// rise with their band, so the contours crowd and spread as the music goes; the tide comes and goes on the
// music's clock. A dashed red
// route runs from summit to summit; a graticule, a frame with a scale border and a compass rose finish the sheet.
// The land drifts slowly under the sheet on the music's clock (drive). No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float relief = 0.6;
uniform float tide = 0.5;
uniform float lines = 0.5;
uniform vec4 sea : source_color = vec4(0.55, 0.74, 0.84, 1.0);
uniform vec4 lowland : source_color = vec4(0.66, 0.79, 0.54, 1.0);
uniform vec4 upland : source_color = vec4(0.82, 0.68, 0.46, 1.0);
uniform vec4 ink : source_color = vec4(0.45, 0.29, 0.16, 1.0);
uniform vec4 paper : source_color = vec4(0.96, 0.93, 0.85, 1.0);

const int PEAKS = 9;


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float hash1(vec2 c) {
	uint h = hash_u(uint(int(c.x) + 100000) * 73856093u ^ uint(int(c.y) + 100000) * 19349663u);
	return float(h & 16777215u) / 16777215.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x), mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(5.2, 1.3);
		a *= 0.5;
	}
	return s / 0.9375;
}

vec2 peak_at(int i, float aspect) {
	float fi = float(i);
	return vec2((0.1 + 0.82 * fract(0.37 + fi * 0.618)) * aspect, 0.18 + 0.64 * fract(0.71 + fi * 0.4142));
}

float height(vec2 p, float aspect, float drift) {
	float h = (fbm(p * 2.4 + vec2(drift, 3.0)) - 0.45) * 0.75;
	for (int i = 0; i < PEAKS; i++) {
		vec2 d = p - peak_at(i, aspect);
		float r = 0.07 + 0.045 * fract(float(i) * 0.53 + 0.2);
		float b = band(0.04 + float(i) / float(PEAKS - 1) * 0.86);
		h += (0.1 + relief * 0.32 * b) * exp(-dot(d, d) / (r * r));
	}
	return h;
}

float seg_d(vec2 p, vec2 a, vec2 b, out float t) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t);
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;
	float drift = drive * 0.004;
	float h = height(p, aspect, drift);
	float sea_level = 0.02 + tide * 0.045 * (0.5 + 0.5 * sin(drive * 0.12));
	float above = h - sea_level;
	float fw = max(fwidth(h), 1e-6);
	float step_h = mix(0.06, 0.022, lines);

	vec3 col;
	if (above > 0.0) {
		// Tints in steps of five contours, a little softened inside each.
		float band_i = floor(above / (step_h * 5.0));
		float t = clamp(band_i / 4.0, 0.0, 1.0);
		col = mix(lowland.rgb, upland.rgb, t);
		col = mix(col, paper.rgb * 0.98, smoothstep(4.5, 6.0, band_i));
		col *= 0.97 + 0.06 * fract(above / (step_h * 5.0));
		// Hill shading from the north-west.
		vec2 grad = vec2(dFdx(h), -dFdy(h)) * size.y;
		float shade = clamp(1.0 - 0.18 * dot(grad, normalize(vec2(1.0, -1.0))) * 0.6, 0.65, 1.2);
		col *= shade;
		// Contours: thin, every fifth heavier; faded where they would crowd into a smear.
		float k = above / step_h;
		float idx = floor(k + 0.5);
		float dpx = abs(k - idx) * step_h / fw;
		bool index_line = mod(idx, 5.0) == 0.0;
		float wpx = index_line ? 0.9 : 0.45;
		float crowd = smoothstep(0.55, 0.25, fw / step_h);
		float line = smoothstep(wpx + 0.7, wpx - 0.3, dpx) * crowd * step(0.5, idx);
		col = mix(col, ink.rgb, line * (index_line ? 0.95 : 0.7));
		// The coast.
		float cd = above / fw;
		col = mix(col, ink.rgb * 0.6 + sea.rgb * 0.2, smoothstep(1.8, 0.6, cd));
	} else {
		float depth = -above;
		col = mix(sea.rgb, sea.rgb * vec3(0.72, 0.8, 0.9), smoothstep(0.0, 0.25, depth));
		// Water-lines along the coast, closer near the shore.
		float wl = depth / 0.014;
		float wd = abs(fract(wl + 0.5) - 0.5) * 0.014 / fw;
		float wline = smoothstep(1.0, 0.2, wd) * smoothstep(0.09, 0.0, depth) * smoothstep(0.55, 0.25, fw / 0.014);
		col = mix(col, sea.rgb * vec3(0.45, 0.6, 0.78), wline * 0.6);
	}

	// Graticule.
	vec2 gq = abs(fract(p / 0.25 + 0.5) - 0.5) * 0.25 / px;
	float grid = smoothstep(0.9, 0.2, min(gq.x, gq.y));
	col = mix(col, vec3(0.2, 0.35, 0.6), grid * 0.3);

	// The route: dashed red, summit to summit, with a ring at each summit it visits.
	float route = 1e3;
	float along = 0.0;
	for (int i = 0; i < 4; i++) {
		float t;
		vec2 a = peak_at(i * 2, aspect);
		vec2 b = peak_at(i * 2 + 2, aspect);
		float d = seg_d(p, a, b, t);
		if (d < route) {
			route = d;
			along = t * length(b - a);
		}
	}
	float dash = step(0.45, fract(along / 0.018));
	col = mix(col, vec3(0.78, 0.12, 0.1), smoothstep(1.6 * px, 0.7 * px, route) * dash * 0.9);
	// Summits: a small triangle on each above the sea.
	for (int i = 0; i < PEAKS; i++) {
		vec2 pk = peak_at(i, aspect);
		vec2 q = p - pk;
		if (abs(q.x) > 0.02 || abs(q.y) > 0.02) {
			continue;
		}
		if (height(pk, aspect, drift) < sea_level) {
			continue;
		}
		float tri = max(abs(q.x) * 0.866 + q.y * 0.5, -q.y) - 0.0045;
		col = mix(col, vec3(0.08), smoothstep(px, -px, tri));
		if (i % 2 == 0) {
			col = mix(col, vec3(0.78, 0.12, 0.1), smoothstep(1.2 * px, 0.2 * px, abs(length(q) - 0.011)));
		}
	}

	// Compass rose, right of middle.
	vec2 cc = vec2(aspect - 0.16, 0.36);
	vec2 cq = p - cc;
	float cl = length(cq);
	if (cl < 0.11) {
		float a = atan(cq.y, cq.x);
		float sector = TAU / 8.0;
		float fa = mod(a + sector * 0.5, sector) - sector * 0.5;
		int si = int(floor((a + sector * 0.5) / sector + 8.0)) % 8;
		float len = si % 2 == 0 ? 0.09 : 0.055;
		float wid = si % 2 == 0 ? 0.014 : 0.01;
		float lx = cl * cos(fa);
		float ly = cl * sin(fa);
		float star = (abs(ly) * len / wid + lx - len) / (len / wid);
		float r_in = smoothstep(px, -px, star);
		vec3 sc = fa > 0.0 ? vec3(0.1) : paper.rgb;
		float edge = smoothstep(1.5 * px, 0.0, abs(star));
		col = mix(col, sc, r_in);
		col = mix(col, vec3(0.1), edge);
		float ring = abs(cl - 0.07) - 0.0012;
		col = mix(col, vec3(0.1), smoothstep(px, -px, ring) * (1.0 - r_in));
		float ticks = step(0.5, fract(a / TAU * 32.0 + 0.25)) * step(abs(cl - 0.077), 0.004);
		col = mix(col, vec3(0.1), ticks * (1.0 - r_in));
	}
	// "N" above the rose.
	vec2 nq = (p - cc - vec2(-0.008, 0.1)) / 0.018;
	if (nq.x > -0.2 && nq.x < 1.0 && nq.y > -0.1 && nq.y < 1.1) {
		float t;
		float nd = min(min(seg_d(nq, vec2(0.0, 0.0), vec2(0.0, 1.0), t), seg_d(nq, vec2(0.0, 1.0), vec2(0.8, 0.0), t)),
				seg_d(nq, vec2(0.8, 0.0), vec2(0.8, 1.0), t));
		col = mix(col, vec3(0.1), smoothstep(0.14, 0.08, nd));
	}

	// The frame: a scale border of alternating black and white, inside a thin line.
	float m = 0.035;
	vec2 e = min(p, vec2(aspect, 1.0) - p);
	float inner = min(e.x, e.y) - m;
	if (inner < 0.0) {
		float run = e.x < e.y ? p.y : p.x;
		float alt = step(0.5, fract(run / 0.05));
		float strip = smoothstep(-0.009, -0.008, inner);
		col = mix(paper.rgb, mix(vec3(0.12), paper.rgb, alt), strip);
		col = mix(col, vec3(0.12), smoothstep(1.2 * px, 0.0, abs(inner + 0.009)));
		col = mix(col, vec3(0.12), smoothstep(1.2 * px, 0.0, abs(inner)));
	}

	// Paper: fibres, the folds and a little wear.
	float fib = vnoise(p * vec2(600.0, 90.0)) * 0.5 + vnoise(p * 40.0) * 0.5;
	col *= 0.95 + 0.07 * fib;
	float fx = fract(p.x / (aspect / 3.0));
	float fy = fract(p.y / 0.5);
	float fold = exp(-min(fx, 1.0 - fx) * aspect / 3.0 / 0.006) * (fx < 0.5 ? 1.0 : -1.0)
			+ exp(-min(fy, 1.0 - fy) * 0.5 / 0.006) * (fy < 0.5 ? -1.0 : 1.0);
	col *= 1.0 + 0.06 * fold;
	col *= 1.0 - 0.25 * pow(length(UV - 0.5) * 1.2, 3.0);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
