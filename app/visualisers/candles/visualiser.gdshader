// Candles (visualiser.json): a cluster of pillar candles burning on a polished table in a dark room. Each flame is a
// teardrop (blue at the root, a darker heart round the wick, bright yellow-white, orange at the edge) that wavers on
// its own and leans together in the draught of the bass; each grows and brightens with its own part of the
// spectrum. The wax glows through near the top, round a pool of melted wax; drips run down the sides; wisps of smoke
// rise from two. The flames light the plaster wall behind and lie as long reflections in the table. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float flame = 0.6;
uniform float draught = 0.5;
uniform float glow = 0.6;
uniform vec4 wax : source_color = vec4(0.93, 0.88, 0.78, 1.0);
uniform vec4 fire : source_color = vec4(1.0, 0.62, 0.22, 1.0);
uniform vec4 wall : source_color = vec4(0.42, 0.32, 0.26, 1.0);
uniform vec4 table : source_color = vec4(0.2, 0.11, 0.07, 1.0);

const int CANDLES = 7;
const float TABLE_EDGE = 0.36;


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

// Candle i: x of its middle (a fraction of the width), the y of its base, its radius and its height.
vec4 candle(int i, float aspect) {
	vec4 c;
	if (i == 0) { c = vec4(0.53, 0.31, 0.042, 0.26); }
	else if (i == 1) { c = vec4(0.655, 0.32, 0.05, 0.31); }
	else if (i == 2) { c = vec4(0.79, 0.31, 0.044, 0.2); }
	else if (i == 3) { c = vec4(0.46, 0.19, 0.06, 0.17); }
	else if (i == 4) { c = vec4(0.595, 0.16, 0.068, 0.27); }
	else if (i == 5) { c = vec4(0.73, 0.18, 0.058, 0.13); }
	else { c = vec4(0.86, 0.17, 0.054, 0.22); }
	c.x *= aspect;
	return c;
}

float candle_band(int i) {
	return band(0.05 + float(i) / float(CANDLES - 1) * 0.85);
}

// The flame of candle i: its root (the wick's tip), height and width, and its lean at the top.
vec4 flame_of(int i, float aspect, out float lean) {
	vec4 c = candle(i, aspect);
	float fi = float(i);
	float b = candle_band(i);
	float ry = c.z * 0.22;
	vec2 root = vec2(c.x, c.y + c.w + 0.016);
	float waver = 0.3 * sin(vis_time * 2.3 + fi * 7.0) + 0.15 * sin(vis_time * 5.1 + fi * 3.0) + 0.08 * sin(vis_time * 9.7 + fi);
	float h = (0.058 + 0.08 * flame * b + 0.012 * waver) * (c.z / 0.06 * 0.4 + 0.6);
	float w = 0.011 * (c.z / 0.06 * 0.3 + 0.7) * (1.0 + 0.25 * b);
	lean = (0.35 * sin(vis_time * 1.7 + fi * 2.0) * 0.3 + draught * bass * 0.9 + 0.25 * waver) * w;
	return vec4(root, h, w);
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;

	// Light from the flames: a sum over them, gentle so the room does not pump.
	// Each flame worked out once.
	vec4 flames[CANDLES];
	float leans[CANDLES];
	for (int i = 0; i < CANDLES; i++) {
		float l = 0.0;
		flames[i] = flame_of(i, aspect, l);
		leans[i] = l;
	}
	vec3 light = vec3(0.0);
	vec3 refl = vec3(0.0);
	for (int i = 0; i < CANDLES; i++) {
		float ln = leans[i];
		vec4 f = flames[i];
		vec2 fc = f.xy + vec2(ln * 0.5, f.z * 0.45);
		float I = 0.85 + 0.25 * candle_band(i);
		float d = length(p - fc);
		light += fire.rgb * I * (0.07 / (0.05 + d * d * 5.0)) * 0.16;
		// In the table: a long soft streak below the candle's base.
		vec4 c = candle(i, aspect);
		float my = c.y - (fc.y - c.y) * 0.4;
		refl += fire.rgb * I * exp(-pow((p.x - fc.x) / 0.014, 2.0) - pow((p.y - my) / 0.035, 2.0)) * 0.5;
	}
	light += fire.rgb * 0.05 * exp(-dot(p - vec2(aspect * 0.66, 0.5), p - vec2(aspect * 0.66, 0.5)) / 0.12);
	light *= glow * 1.4 + 0.3;

	vec3 col;
	if (p.y > TABLE_EDGE) {
		// The wall: rough plaster.
		float pl = vnoise(p * 30.0) * 0.6 + vnoise(p * 90.0) * 0.4;
		col = wall.rgb * (0.75 + 0.35 * pl) * (0.04 + light);
	} else {
		// The table: dark polished wood with a grain, the flames in it, a lip at the back.
		float grain = vnoise(vec2(p.x * 3.0, p.y * 140.0 + vnoise(p * vec2(2.0, 20.0)) * 4.0));
		col = table.rgb * (0.7 + 0.5 * grain) * (0.12 + light * 1.2);
		col += refl * (0.6 + 0.3 * grain) * glow;
		col += vec3(0.6, 0.45, 0.3) * 0.25 * smoothstep(0.004, 0.0, abs(p.y - TABLE_EDGE + 0.003)) * (light.r + 0.05);
	}

	// Candles: the back row, then the front.
	for (int i = 0; i < CANDLES; i++) {
		vec4 c = candle(i, aspect);
		float fi = float(i);
		float dx = (p.x - c.x) / c.z;
		float ry = c.z * 0.22;
		// Its shadow on the table, a soft ellipse round its foot.
		col *= 1.0 - 0.5 * smoothstep(1.4, 0.6, length(vec2(dx * 0.8, (p.y - c.y) / (ry * 1.6))));
		// Its reflection: a dim copy of its body upside down.
		if (abs(dx) < 1.0 && p.y < c.y && p.y > c.y - c.w * 0.35) {
			col += wax.rgb * 0.07 * (1.0 - (c.y - p.y) / (c.w * 0.35)) * glow;
		}
		if (abs(dx) > 1.05) {
			continue;
		}
		float dxc = clamp(dx, -1.0, 1.0);
		float sq = sqrt(max(1.0 - dxc * dxc, 0.0));
		float top = c.y + c.w;
		float aa = px / c.z;
		float b = candle_band(i);
		// Body.
		float y_bot = c.y - ry * sq;
		float y_top = top - ry * sq;
		float body = smoothstep(1.0 + aa, 1.0 - aa, abs(dx)) * step(y_bot, p.y) * step(p.y, y_top + px);
		// Drips over the rim, each its own length.
		float drip = 0.0;
		for (int k = 0; k < 4; k++) {
			float fk = float(k);
			float hx = hash1(vec2(fi, fk)) * 1.6 - 0.8;
			float len = (0.15 + 0.5 * hash1(vec2(fi, fk + 9.0))) * c.w;
			float ddx = abs(dx - hx) * c.z;
			float yy = top - ry * sqrt(max(1.0 - hx * hx, 0.0));
			float tip = yy - len;
			float wd = 0.006 * (1.0 + 0.4 * hash1(vec2(fi, fk + 3.0)));
			float in_d = smoothstep(wd + px, wd - px, ddx) * step(tip, p.y) * step(p.y, yy + 0.004);
			in_d = max(in_d, smoothstep(wd * 1.2 + px, wd * 1.2 - px, length(vec2(ddx, p.y - tip))));
			drip = max(drip, in_d);
		}
		if (body > 0.0 || drip > 0.0) {
			// Lit from its own flame above and the room; glowing through near the top.
			float shade = 0.35 + 0.65 * sq * (0.75 + 0.25 * dx);
			vec3 wc = wax.rgb * shade * (0.08 + light * 0.9);
			float through = exp(-max(top - p.y, 0.0) / (0.045 + 0.02 * b)) * (0.7 + 0.5 * b);
			wc += fire.rgb * wax.rgb * through * 0.9 * (0.5 + 0.5 * sq);
			wc += wax.rgb * drip * 0.08 * (0.5 + light.r);
			col = mix(col, wc, max(body, drip * smoothstep(1.4, 0.9, abs(dx))));
		}
		// The top: a rim of wax and a pool of melted wax glowing round the wick.
		float te = length(vec2(dx, (p.y - top) / ry));
		if (te < 1.0 + aa * 2.0) {
			float rim = smoothstep(0.72, 0.85, te);
			vec3 pool = mix(fire.rgb * vec3(1.0, 0.85, 0.6), vec3(1.0, 0.9, 0.7), 0.4) * (0.75 + 0.4 * b);
			vec3 tc = mix(pool, wax.rgb * (0.4 + light * 1.2) + fire.rgb * 0.25, rim);
			col = mix(col, tc, smoothstep(1.0 + aa, 1.0 - aa, te));
		}
	}

	// Wicks and flames.
	for (int i = 0; i < CANDLES; i++) {
		float ln = leans[i];
		vec4 f = flames[i];
		vec2 q = p - f.xy;
		if (abs(q.x) > 0.12 || q.y < -0.06 || q.y > f.z + 0.12) {
			continue;
		}
		// Wick: a short dark curl with an ember at the tip.
		float wk = length(vec2(q.x - 0.002 * (q.y + 0.016) / 0.016, clamp(q.y, -0.016, 0.0) - q.y)) - 0.0018;
		col = mix(col, vec3(0.05), smoothstep(px, -px, wk) * step(-0.016, q.y) * step(q.y, 0.002));
		col += vec3(1.0, 0.3, 0.1) * exp(-dot(q, q) / 0.000004) * 0.6;
		// The flame.
		float fy = (q.y + 0.004) / f.z;
		float x = q.x - ln * fy * fy;
		float wprof = f.w * pow(max(sin(PI * clamp(pow(clamp(fy, 0.0, 1.0), 0.75), 0.0, 1.0)), 0.0), 0.9) * (1.0 - 0.25 * fy);
		float dfl = abs(x) - wprof;
		float inside = smoothstep(px * 1.5, -px * 1.5, dfl) * step(0.0, fy) * step(fy, 1.0);
		float core = clamp(1.0 - abs(x) / max(wprof, 1e-4), 0.0, 1.0);
		vec3 fc = mix(fire.rgb, vec3(1.0, 0.96, 0.82), smoothstep(0.1, 0.7, core) * smoothstep(1.0, 0.35, fy));
		fc = mix(fc, vec3(0.25, 0.35, 1.0) * 0.8, smoothstep(0.2, 0.0, fy) * smoothstep(0.3, 0.9, 1.0 - core) * 0.8);
		fc = mix(fc, fire.rgb * 0.75, smoothstep(0.22, 0.05, fy) * smoothstep(0.4, 0.9, core) * 0.6);
		float b = candle_band(i);
		col = mix(col, fc * (1.0 + 0.2 * b), inside);
		// Its halo.
		vec2 hq = vec2(x, q.y - f.z * 0.45) / vec2(1.0, 1.8);
		col += fire.rgb * (exp(-length(hq) / 0.016) * 0.35 + exp(-length(hq) / 0.03) * 0.1) * (0.8 + 0.5 * b) * glow * (1.0 - inside);
	}
	// Smoke from two candles: a thin curl, fading as it rises.
	for (int s = 0; s < 2; s++) {
		int i = s == 0 ? 1 : 5;
		float ln = leans[i];
		vec4 f = flames[i];
		float sy = p.y - f.y - f.z;
		if (sy < 0.0 || sy > 0.35) {
			continue;
		}
		float sx = f.x + ln + 0.02 * sy / 0.3 * sin(sy * 25.0 - vis_time * 1.5 * (0.6 + drive * 0.0)) + 0.01 * sin(sy * 60.0 - vis_time * 2.2);
		float sd = abs(p.x - sx);
		float wdt = 0.0015 + sy * 0.03;
		col += vec3(0.6, 0.58, 0.55) * 0.12 * exp(-sd * sd / (wdt * wdt)) * smoothstep(0.35, 0.05, sy) * smoothstep(0.0, 0.04, sy);
	}

	col *= 1.0 - 0.45 * pow(length((UV - vec2(0.62, 0.55)) * vec2(1.0, 1.2)) * 1.1, 2.0);
	col = col / (1.0 + col * 0.25);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
