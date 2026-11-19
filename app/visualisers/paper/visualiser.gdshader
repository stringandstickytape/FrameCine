// Paper diorama (visualiser.json): a landscape cut from layers of coloured paper and set one behind the other in a
// box, lit from the top left so each layer throws a soft shadow on the ones behind. Hills of six layers, darkest at
// the front, palest at the back; pines cut along three of them, a cottage with a lit window, reeds along the front
// that sway with the bass. A paper sun glows with the level; paper clouds drift and paper birds flap across on the
// music's clock (drive). Each layer is a part of the spectrum (the front the low notes, the back the high): its hills
// rise and fall with it. The box sways a little, the layers moving against each other. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float hills = 0.6;
uniform float sway = 0.5;
uniform float shadows = 0.6;
uniform vec4 near : source_color = vec4(0.16, 0.12, 0.3, 1.0);
uniform vec4 far : source_color = vec4(0.95, 0.62, 0.55, 1.0);
uniform vec4 sky : source_color = vec4(1.0, 0.85, 0.66, 1.0);
uniform vec4 sun : source_color = vec4(1.0, 0.96, 0.82, 1.0);

const int LAYERS = 6;
const vec2 TO_LIGHT = vec2(-0.011, 0.014);


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

// The top edge of layer i at x: a few hills from sines, raised by the layer's part of the spectrum.
float ridge(int i, float x, float aspect) {
	float fi = float(i);
	float base = 0.14 + fi * 0.085;
	float f1 = 2.2 + fi * 0.9;
	float y = base + 0.05 * sin(x * f1 + fi * 2.1) + 0.03 * sin(x * f1 * 2.3 + fi * 5.3) + 0.012 * sin(x * f1 * 5.1 + fi);
	float lo = fi / float(LAYERS) * 0.9;
	float b = band(lo + 0.15 * clamp(x / aspect, 0.0, 1.0));
	return y + hills * 0.07 * b * (0.6 + 0.4 * sin(x * f1 * 1.4 + fi * 3.0));
}

// Signed distance (about, in heights) to the paper of layer i: negative inside.
float paper_sd(int i, vec2 p, float aspect) {
	float d = p.y - ridge(i, p.x, aspect);
	// Pines on layers 1 to 3: three tiers each.
	if (i >= 1 && i <= 3) {
		float wc = 0.05 - float(i) * 0.008;
		float cell = floor(p.x / wc);
		float h = hash1(vec2(cell, float(i)));
		if (h < 0.45) {
			float xc = (cell + 0.5 + (fract(h * 13.0) - 0.5) * 0.4) * wc;
			float base = ridge(i, xc, aspect) - 0.01;
			float th = (0.06 + 0.06 * fract(h * 7.0)) * (1.0 - float(i) * 0.15);
			float t = (p.y - base) / th;
			float tier = fract(t * 3.0);
			float hw = th * 0.32 * (1.0 - t) * (0.55 + 0.45 * (1.0 - tier));
			float dt = max(abs(p.x - xc) - hw, max(-t, t - 1.0) * th);
			float trunk = max(abs(p.x - xc) - 0.0025, max(base - 0.012 - p.y, p.y - base - 0.01));
			d = min(d, min(dt, trunk));
		}
	}
	// A cottage on layer 2, with its chimney.
	if (i == 2) {
		float hx = aspect * 0.64;
		float hb = ridge(2, hx, aspect) - 0.006;
		vec2 q = p - vec2(hx, hb);
		float walls = max(abs(q.x) - 0.035, max(-q.y, q.y - 0.04));
		float roof = max(abs(q.x) * 0.75 + q.y - 0.075, 0.035 - q.y);
		float chim = max(abs(q.x - 0.018) - 0.006, max(0.04 - q.y, q.y - 0.08));
		d = min(d, min(walls, min(roof, chim)));
	}
	// Reeds along the front, bending with the bass.
	if (i == 0) {
		float wc = 0.011;
		float cell = floor(p.x / wc);
		float h = hash1(vec2(cell, 31.0));
		if (h < 0.7) {
			float xc = (cell + 0.5) * wc;
			float base = ridge(0, xc, aspect) - 0.01;
			float rh = 0.04 + 0.08 * fract(h * 17.0);
			float t = clamp((p.y - base) / rh, 0.0, 1.0);
			float bend = (sway * (0.4 + 0.8 * bass) * 0.6 + 0.15 * sin(vis_time * 1.3 + cell * 0.7)) * rh * 0.35 * t * t;
			float hw = 0.0022 * (1.0 - t) + 0.0004;
			float dr = max(abs(p.x - xc - bend) - hw, max(base - p.y, p.y - base - rh));
			d = min(d, dr);
		}
	}
	return d;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;
	float swing = sin(drive * 0.06) * 0.025 * sway;
	float fib = vnoise(p * vec2(420.0, 160.0)) * 0.5 + vnoise(p * 60.0) * 0.5;

	// The deepest layer that can show here: below the lowest a layer's edge can go, it hides all behind it.
	int first = LAYERS - 1;
	for (int i = 0; i < LAYERS; i++) {
		if (p.y < 0.14 + float(i) * 0.085 - 0.1) {
			first = i;
			break;
		}
	}

	// The back of the box: the sky, a paper sun, clouds.
	vec2 bp = p + vec2(swing * 0.15, 0.0);
	vec3 col = mix(sky.rgb, mix(sky.rgb, far.rgb, 0.35) * 1.02, smoothstep(0.3, 1.0, bp.y));
	if (first == LAYERS - 1 && p.y > 0.14 + float(LAYERS - 1) * 0.085 - 0.1) {
	vec2 sc = vec2(aspect * 0.7, 0.66);
	float sr = 0.09;
	float sl = length(bp - sc);
	col += sun.rgb * 0.25 * exp(-max(sl - sr, 0.0) * 12.0) * (0.5 + 0.8 * level);
	col *= 1.0 - 0.25 * shadows * smoothstep(sr + 0.012, sr - 0.004, length(bp - sc - TO_LIGHT * 0.6)) * step(sr, sl);
	col = mix(col, sun.rgb * (0.95 + 0.05 * fib), smoothstep(sr + px, sr - px, sl));
	// Clouds: three puffs each, a flat bottom; their shadow on the sky.
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float cx = fract(0.2 + fk * 0.37 + drive * 0.004 * (1.0 + fk * 0.3)) * (aspect + 0.5) - 0.25;
		vec2 cc = vec2(cx, 0.72 + 0.08 * fract(fk * 0.61));
		for (int sh = 1; sh >= 0; sh--) {
			vec2 q = bp - cc + (sh == 1 ? TO_LIGHT * 0.7 : vec2(0.0));
			float d = min(min(length(q) - 0.035, length(q - vec2(0.04, -0.008)) - 0.026), length(q + vec2(0.042, 0.01)) - 0.022);
			d = max(d, -q.y - 0.022);
			if (sh == 1) {
				col *= 1.0 - 0.3 * shadows * smoothstep(0.008, -0.004, d);
			} else {
				col = mix(col, vec3(1.0, 0.99, 0.96) * (0.92 + 0.08 * fib), smoothstep(px, -px, d));
			}
		}
	}
	// Birds: small Vs flapping across.
	for (int k = 0; k < 4; k++) {
		float fk = float(k);
		float bx = fract(fk * 0.29 + drive * 0.012 * (1.0 + 0.2 * fk)) * (aspect + 0.3) - 0.15;
		vec2 q = bp - vec2(bx, 0.58 + 0.12 * fract(fk * 0.73) + 0.01 * sin(drive * 0.3 + fk));
		float flap = sin(vis_time * 7.0 + fk * 2.0) * 0.6;
		q.x = abs(q.x);
		float wing = abs(q.y - q.x * flap - q.x * q.x * 8.0 * (0.4 - flap * 0.3)) - 0.0018;
		col = mix(col, near.rgb * 0.9, smoothstep(px, -px, max(wing, q.x - 0.014)));
	}
	}

	// The layers, back to front: each throws its shadow on what is behind it, then lies over it.
	for (int j = 0; j < LAYERS; j++) {
		int i = LAYERS - 1 - j;
		float fi = float(i);
		// Hidden behind a nearer layer, or this layer and its shadow are all below this pixel.
		float top = 0.14 + fi * 0.085 + 0.092 + 0.07 * hills + (i <= 3 ? 0.13 : 0.0) + 0.02;
		if (i > first || p.y > top) {
			continue;
		}
		vec2 lp = p + vec2(swing * (1.0 - fi / float(LAYERS)), 0.0);
		float dsh = paper_sd(i, lp + TO_LIGHT, aspect);
		col *= 1.0 - 0.38 * shadows * smoothstep(0.012, -0.006, dsh);
		float d = paper_sd(i, lp, aspect);
		if (d < px) {
			float t = fi / float(LAYERS - 1);
			vec3 lc = mix(near.rgb, far.rgb, pow(t, 0.8));
			// Darker down into the layer, the cut edge catching the light.
			lc *= 0.9 + 0.1 * smoothstep(-0.12, 0.0, d);
			lc = mix(lc, lc * 1.25 + vec3(0.04), smoothstep(-0.004, -0.0015, d));
			lc *= 0.93 + 0.1 * fib;
			// The cottage's window.
			if (i == 2) {
				float hx = aspect * 0.64;
				vec2 q = lp - vec2(hx, ridge(2, hx, aspect) - 0.006);
				float win = max(abs(q.x + 0.012) - 0.007, abs(q.y - 0.02) - 0.008);
				vec3 wl = vec3(1.0, 0.8, 0.4) * (0.8 + 0.4 * mid);
				lc = mix(lc, wl, smoothstep(px, -px, win));
				lc += vec3(1.0, 0.7, 0.3) * 0.15 * exp(-max(win, 0.0) * 60.0) * (0.6 + 0.6 * mid);
			}
			col = mix(col, lc, smoothstep(px, -px, d));
		}
	}

	// The box's own edges: a little darker round the sides.
	col *= 1.0 - 0.35 * pow(length((UV - 0.5) * vec2(1.0, 1.1)) * 1.25, 3.0);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
