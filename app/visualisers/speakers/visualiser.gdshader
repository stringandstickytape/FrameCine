// Sound system (visualiser.json): a wall of stacked loudspeaker cabinets, seen square on and filling the picture,
// in the light of two coloured lamps. Three rows: four big bass bins at the bottom, six cabinets of two cones each
// in the middle, eight horns at the top. Each cone is a part of the spectrum (low notes on the left of its row) and
// pumps with it: the cone and its dust cap come forward, the roll of rubber round it leans, and the light on it
// changes as it does. Every cabinet has a small ladder of lamps that shows its part of the sound.
// All of it is a height drawn on a plane and lit from its slope: nothing is marched.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float pump = 0.7;
uniform float lamps = 0.7;
uniform vec4 lamp_a : source_color = vec4(1.0, 0.3, 0.2, 1.0);
uniform vec4 lamp_b : source_color = vec4(0.2, 0.5, 1.0, 1.0);
uniform vec4 cabinet : source_color = vec4(0.13, 0.13, 0.14, 1.0);
uniform vec4 cone : source_color = vec4(0.3, 0.28, 0.26, 1.0);
uniform vec4 ladder : source_color = vec4(0.3, 1.0, 0.4, 1.0);

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

// Light on a surface with normal n and colour alb: the two lamps and a little of the room.
vec3 lit(vec3 n, vec3 alb, float gloss, vec2 where) {
	float sweep = 0.25 * sin(drive * 0.11);
	vec3 la = normalize(vec3(-0.75 + sweep, 0.45, 0.5));
	vec3 lb = normalize(vec3(0.75 + sweep, -0.25, 0.5));
	float fa = 0.55 + 0.45 * smoothstep(1.2, -0.9, where.x);
	float fb = 0.55 + 0.45 * smoothstep(-1.2, 0.9, where.x);
	vec3 h_a = normalize(la + vec3(0.0, 0.0, 1.0));
	vec3 h_b = normalize(lb + vec3(0.0, 0.0, 1.0));
	vec3 c = alb * (lamp_a.rgb * max(dot(n, la), 0.0) * fa + lamp_b.rgb * max(dot(n, lb), 0.0) * fb) * (1.9 + 1.1 * level);
	c += alb * 0.14;
	c += gloss * (lamp_a.rgb * fa * pow(max(dot(n, h_a), 0.0), 40.0) + lamp_b.rgb * fb * pow(max(dot(n, h_b), 0.0), 40.0));
	return c;
}

// A cone of radius rad at q from its middle, pushed out by x (-1..1). under is the cabinet's colour there.
vec3 driver_at(vec2 q, float rad, float x, vec3 under, vec2 where, float px) {
	float rho = length(q) / rad;
	if (rho > 1.06) {
		// The shade the rim throws.
		return under * (1.0 - 0.3 * smoothstep(1.16, 1.06, length(q - vec2(0.01, -0.012) * rad * 8.0) / rad));
	}
	vec2 dir = q / max(length(q), 1e-4);
	float ang = atan(q.y, q.x);
	float slope;
	vec3 alb;
	float gloss;
	float lift = 0.0;
	if (rho > 0.9) {
		// The steel rim and its eight bolts.
		slope = (rho > 1.0 ? -2.5 : 0.0) + (rho < 0.93 ? 1.5 : 0.0);
		alb = vec3(0.16, 0.16, 0.17);
		gloss = 0.35;
		float bolt = length(vec2((fract(ang * 8.0 / TAU + 0.5) - 0.5) * TAU / 8.0 * rho, rho - 0.955)) * rad;
		alb = mix(alb, vec3(0.3), smoothstep(0.035 * rad + px, 0.035 * rad - px, bolt));
	} else if (rho > 0.76) {
		// The roll of rubber: half a round, leaning with the cone.
		float u = (rho - 0.83) / 0.07;
		slope = -u * 2.2 / sqrt(max(1.0 - u * u * 0.8, 0.1)) - x * 1.6;
		alb = vec3(0.05);
		gloss = 0.5;
	} else if (rho > 0.24) {
		// The cone itself: deeper towards the middle, a little nearer and bigger as it comes out.
		float rz = rho * (1.0 - 0.05 * x);
		slope = 1.15 + 0.5 * rz + 0.25 * x;
		float fibre = noise1(vec2(ang * 9.0, rz * 5.0) + rad * 40.0);
		alb = cone.rgb * (0.75 + 0.3 * fibre) * (0.9 + 0.1 * sin(rz * 60.0));
		gloss = 0.08;
		lift = x;
	} else {
		// The dust cap: a dome.
		float u = rho / 0.24;
		slope = -u * 1.6;
		alb = cone.rgb * 0.7;
		gloss = 0.6;
		lift = x;
	}
	vec3 n = normalize(vec3(-dir * slope, 1.0));
	vec3 c = lit(n, alb, gloss, where) * (1.0 + 0.3 * lift);
	// The cone sits down in its basket: darker where the rim shades it.
	c *= 1.0 - 0.45 * smoothstep(0.76, 0.3, rho) * smoothstep(0.1, 0.5, dot(dir, normalize(vec2(-0.4, 0.5))) * 0.5 + 0.5) * (1.0 - 0.4 * x);
	c *= 1.0 - 0.5 * smoothstep(0.012, 0.0, abs(rho - 0.9)) - 0.5 * smoothstep(0.012, 0.0, abs(rho - 0.76)) - 0.35 * smoothstep(0.012, 0.0, abs(rho - 0.24));
	return mix(under, c, smoothstep(1.06, 1.06 - px / rad, rho));
}

// A horn of half-size hs at q: a square mouth narrowing to a dark slot.
vec3 horn_at(vec2 q, vec2 hs, float glow, vec3 under, vec2 where, float px) {
	vec2 a = abs(q) / hs;
	float m = max(a.x, a.y);
	if (m > 1.0) {
		return under;
	}
	vec2 dir = a.x > a.y ? vec2(sign(q.x), 0.0) : vec2(0.0, sign(q.y));
	float slope = 0.6 + 1.6 * (1.0 - m);
	vec3 n = normalize(vec3(-dir * slope, 1.0));
	vec3 c = lit(n, vec3(0.13, 0.13, 0.14), 0.5, where);
	c *= 0.35 + 0.65 * m;
	float slot = smoothstep(0.2, 0.14, a.y) * smoothstep(0.5, 0.44, a.x);
	c = mix(c, vec3(0.0), slot);
	c *= 1.0 - 0.5 * smoothstep(0.03, 0.0, abs(a.x - a.y) * m);
	c += ladder.rgb * glow * 0.05 * slot;
	return mix(under, c, smoothstep(1.0, 1.0 - px / min(hs.x, hs.y), m));
}

// The ladder of lamps: five, lit up to v.
vec3 ladder_at(vec2 q, float v, vec3 under, float px) {
	vec2 a = abs(q) - vec2(0.008, 0.05);
	if (max(a.x, a.y) > 0.004) {
		return under;
	}
	float k = floor((q.y + 0.05) / 0.02);
	vec2 cq = vec2(q.x, q.y + 0.05 - (k + 0.5) * 0.02);
	float dot_m = smoothstep(0.0065 + px, 0.0065 - px, max(abs(cq.x), abs(cq.y) * 1.3));
	float on = smoothstep(k / 5.0, k / 5.0 + 0.12, v * 1.1);
	vec3 lc = k > 3.5 ? vec3(1.0, 0.25, 0.15) : (k > 2.5 ? vec3(1.0, 0.8, 0.2) : ladder.rgb);
	vec3 c = mix(vec3(0.015), lc * (0.08 + 1.1 * on * lamps), dot_m);
	return mix(under, c, smoothstep(0.004, 0.0, max(a.x, a.y)));
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float px = 1.0 / size.y;
	// The wall is wider than the picture, and the view drifts a little along it.
	vec2 w = p + vec2(0.05 * sin(drive * 0.017), 0.0);

	// The rows: bass bins (y -0.5..-0.08), twin cabinets (-0.08..0.25), horns (0.25..0.5).
	float row_lo;
	float row_hi;
	float cell_w;
	int row;
	if (w.y < -0.08) {
		row = 0;
		row_lo = -0.5;
		row_hi = -0.08;
		cell_w = 0.46;
	} else if (w.y < 0.25) {
		row = 1;
		row_lo = -0.08;
		row_hi = 0.25;
		cell_w = 0.31;
	} else {
		row = 2;
		row_lo = 0.25;
		row_hi = 0.5;
		cell_w = 0.232;
	}
	float shift = row == 1 ? 0.5 : 0.0;
	float gx = w.x / cell_w + shift;
	float id = floor(gx);
	vec2 q = vec2((fract(gx) - 0.5) * cell_w, w.y - (row_lo + row_hi) * 0.5);
	vec2 hs = vec2(cell_w, row_hi - row_lo) * 0.5;
	float n_cells = row == 0 ? 4.0 : (row == 1 ? 6.0 : 8.0);
	float u = clamp((id - shift + n_cells * 0.5 + 0.5) / n_cells, 0.02, 0.98);

	// The cabinet: painted board, a bevel at its edges, steel corners.
	float grain = noise1(vec2(w.x * 30.0, w.y * 220.0)) * 0.5 + noise1(w * 400.0) * 0.5;
	vec2 e = hs - abs(q);
	float edge = min(e.x, e.y);
	vec3 n_cab = vec3(0.0, 0.0, 1.0);
	if (edge < 0.012) {
		n_cab = e.x < e.y ? normalize(vec3(sign(q.x) * 1.2, 0.0, 1.0)) : normalize(vec3(0.0, sign(q.y) * 1.2, 1.0));
	}
	n_cab = normalize(n_cab + vec3(grain - 0.5, noise1(w * 300.0 + 7.0) - 0.5, 0.0) * 0.25);
	vec3 col = lit(n_cab, cabinet.rgb * (0.7 + 0.6 * grain), 0.12, w);
	col *= smoothstep(0.0, 0.004, edge);
	float corner = max(e.x, e.y);
	if (corner < 0.03 && edge < 0.03) {
		vec3 n_c = normalize(vec3(sign(q) * (0.03 - vec2(e.x, e.y)) * 14.0, 1.0));
		col = mix(col, lit(n_c, vec3(0.25, 0.25, 0.27), 0.8, w), smoothstep(0.0, 0.003, edge));
	}

	if (row == 0) {
		float b = band_between(u * 0.16, u * 0.16 + 0.05);
		float x = pump * (b * 1.6 - 0.35 + 0.35 * beat * b);
		col = driver_at(q - vec2(0.0, 0.02), 0.165, clamp(x, -0.5, 1.2), col, w, px);
		// The port: a slot under the cone.
		vec2 pq = abs(q - vec2(0.0, -0.172)) - vec2(0.15, 0.012);
		float port = max(pq.x, pq.y);
		col = mix(col, vec3(0.004), smoothstep(px, -px, port));
		col *= 1.0 - 0.4 * smoothstep(0.008, 0.0, abs(port));
		col = ladder_at(q - vec2(0.2, 0.12), b * 1.3, col, px);
	} else if (row == 1) {
		for (int s = 0; s < 2; s++) {
			float side = s == 0 ? -1.0 : 1.0;
			float bu = 0.22 + 0.45 * clamp(u + side * 0.04, 0.0, 1.0);
			float b = band_between(bu, bu + 0.03);
			float x = pump * (b * 1.5 - 0.3);
			col = driver_at(q - vec2(side * 0.073, -0.012), 0.066, clamp(x, -0.5, 1.2), col, w, px);
		}
		float b = band_between(0.22 + 0.45 * u, 0.26 + 0.45 * u);
		col = ladder_at((q - vec2(0.0, 0.125)).yx * vec2(1.0, 1.0), b * 1.3, col, px);
		// A handle cut in the top of each side.
		vec2 hq = abs(vec2(abs(q.x) - 0.105, q.y - 0.12)) - vec2(0.022, 0.008);
		col = mix(col, vec3(0.006), smoothstep(px, -px, max(hq.x, hq.y)));
	} else {
		float b = band_between(0.68 + 0.28 * u, 0.72 + 0.28 * u);
		col = horn_at(q - vec2(-0.012, 0.0), vec2(0.082, 0.085), b, col, w, px);
		col = ladder_at(q - vec2(0.094, 0.0), b * 1.4, col, px);
	}

	// Haze in the lamps' light, in front of it all.
	float haze = noise1(w * 2.0 + vec2(drive * 0.05, 0.0)) * noise1(w * 3.7 - vec2(0.0, drive * 0.03));
	col += (lamp_a.rgb * smoothstep(1.0, -1.0, w.x) + lamp_b.rgb * smoothstep(-1.0, 1.0, w.x)) * haze * 0.1 * (0.4 + level);
	col = 1.0 - exp(-col * 1.5);
	col *= 1.0 - 0.35 * dot(p, p);
	COLOR = vec4(col, 1.0);
}
