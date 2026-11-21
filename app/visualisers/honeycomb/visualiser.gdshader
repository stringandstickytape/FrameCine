// Honeycomb (visualiser.json): a comb seen close from straight in front, lit from the upper left with more light
// coming through the wax from behind. Every six-sided cell holds honey to its own height, and the comb is the
// spectrum: the low notes on the left, and in each column the cells fill from the bottom as that part of the sound
// rises and drain as it falls. An empty cell is deep: its rim throws a shadow down into it and the three-part floor
// shows; a full one is level with the rim, bright, with the lamp's glint on it. Some cells are capped with wax and
// some packed with pollen. Bees walk over the comb on the music's clock (drive), their legs stepping; they waggle
// with the bass and their wings blur with the high notes.
// All flat: the depth is in the shadows and the slopes.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float glow = 0.6;
uniform float bees = 0.8;
uniform vec4 honey : source_color = vec4(1.0, 0.6, 0.08, 1.0);
uniform vec4 wax : source_color = vec4(0.9, 0.75, 0.4, 1.0);
uniform vec4 stripe : source_color = vec4(0.95, 0.65, 0.15, 1.0);
uniform vec4 pollen : source_color = vec4(0.85, 0.4, 0.1, 1.0);

const float CELLS = 8.0;
const vec3 LAMP = vec3(-0.46, 0.55, 0.7);

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

// The cell at g: xy from its middle, zw which cell.
vec4 hex_at(vec2 g) {
	vec2 s = vec2(1.0, 1.7320508);
	vec4 hc = floor(vec4(g, g - vec2(0.5, 1.0)) / s.xyxy) + 0.5;
	vec4 h = vec4(g - hc.xy * s, g - (hc.zw + 0.5) * s);
	return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, hc.xy) : vec4(h.zw, hc.zw + 0.5);
}

// 0 at a cell's middle, 0.5 at its edge.
float hex_d(vec2 q) {
	vec2 a = abs(q);
	return max(dot(a, vec2(0.5, 0.8660254)), a.x);
}

// A bee at l (its length about 2, its head towards +x): paints over col.
void bee(inout vec3 col, vec2 l, float step_ph, float buzz, float px) {
	// Its shadow on the comb.
	vec2 sl = l - vec2(0.1, -0.14);
	float sh = min(length((sl - vec2(-0.55, 0.0)) / vec2(0.66, 0.38)), length((sl - vec2(0.3, 0.0)) / vec2(0.5, 0.36)));
	col *= 1.0 - 0.5 * smoothstep(1.25, 0.7, sh);
	// Legs: three a side, stepping.
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		float sw = 0.1 * sin(step_ph + fk * 2.1);
		for (int s = 0; s < 2; s++) {
			float sd = s == 0 ? 1.0 : -1.0;
			vec2 hip = vec2(0.36 - 0.2 * fk, 0.2 * sd);
			vec2 knee = vec2(0.52 - 0.42 * fk + sw * sd, 0.5 * sd);
			vec2 foot = vec2(0.62 - 0.6 * fk + 1.6 * sw * sd, 0.74 * sd);
			float d = min(seg_sd(l, hip, knee), seg_sd(l, knee, foot)) - 0.028;
			col = mix(col, vec3(0.05, 0.035, 0.02), smoothstep(px, -px, d));
		}
	}
	// Feelers.
	float fd = min(seg_sd(vec2(l.x, abs(l.y)), vec2(0.78, 0.08), vec2(0.98, 0.2)), seg_sd(vec2(l.x, abs(l.y)), vec2(0.98, 0.2), vec2(1.2, 0.16))) - 0.02;
	col = mix(col, vec3(0.05, 0.035, 0.02), smoothstep(px, -px, fd));
	// The back end: striped, coming to a point.
	vec2 aq = (l - vec2(-0.55, 0.0)) / vec2(0.64 - 0.1 * step(l.x, -0.55), 0.35);
	aq.y /= 1.0 - 0.35 * smoothstep(0.0, -1.0, aq.x);
	float ad = length(aq);
	if (ad < 1.05) {
		float bandm = smoothstep(-0.25, 0.25, sin((l.x - 0.02 * aq.y * aq.y) * 15.0 + 1.0));
		vec3 ac = mix(vec3(0.06, 0.04, 0.02), stripe.rgb, bandm);
		ac *= 0.45 + 0.75 * sqrt(max(1.0 - aq.y * aq.y, 0.0)) * (0.8 + 0.3 * smoothstep(0.5, -0.5, aq.y));
		col = mix(col, ac, smoothstep(1.0 + px * 3.0, 1.0 - px * 3.0, ad));
	}
	// The middle: round and furry.
	vec2 tq = (l - vec2(0.2, 0.0)) / 0.31;
	float td = length(tq);
	if (td < 1.1) {
		float fur = noise1(l * 38.0) * 0.6 + noise1(l * 90.0) * 0.4;
		vec3 tc = mix(stripe.rgb * 0.75, vec3(0.2, 0.13, 0.05), 0.35) * (0.5 + 0.8 * fur) * (0.55 + 0.6 * (1.0 - td * td));
		col = mix(col, tc, smoothstep(1.05, 0.9 - 0.1 * fur, td));
	}
	// The head and its two eyes.
	vec2 hq = (l - vec2(0.64, 0.0)) / vec2(0.2, 0.25);
	float hd = length(hq);
	if (hd < 1.05) {
		vec3 hcol = vec3(0.1, 0.07, 0.03) * (0.7 + 0.8 * (1.0 - hd));
		hcol = mix(hcol, vec3(0.02) + vec3(0.25) * smoothstep(0.25, 0.0, length(vec2(hq.x - 0.25, abs(hq.y) - 0.5))), smoothstep(0.42, 0.34, length(vec2(hq.x - 0.15, abs(hq.y) - 0.62))));
		col = mix(col, hcol, smoothstep(1.0 + px * 4.0, 1.0 - px * 4.0, hd));
	}
	// The wings: clear, veined, held back over the body; they open and blur with the high notes.
	float spread = 0.38 + 0.25 * buzz;
	vec2 wl = vec2(l.x - 0.15, abs(l.y));
	vec2 wr = vec2(cos(spread) * wl.x - sin(spread) * wl.y, sin(spread) * wl.x + cos(spread) * wl.y);
	vec2 wq = (wr - vec2(-0.62, 0.0)) / vec2(0.62, 0.2);
	float wd = length(wq);
	if (wd < 1.0 + 0.3 * buzz) {
		float vein = smoothstep(0.03, 0.0, abs(wq.y - 0.3 * wq.x * wq.x + 0.1)) + smoothstep(0.03, 0.0, abs(wq.y + 0.25 + 0.2 * wq.x));
		float wm = smoothstep(1.0 + 0.3 * buzz, 1.0 - 0.1 - 0.2 * buzz, wd) * (0.42 - 0.2 * buzz);
		col = mix(col, vec3(0.9, 0.92, 0.95) * (0.75 + 0.25 * vein) + col * 0.25, wm);
		col += vec3(1.0, 0.95, 0.85) * 0.35 * wm * smoothstep(0.2, 0.0, abs(wq.y - 0.35)) * smoothstep(1.0, 0.0, abs(wq.x));
	}
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float px = 1.0 / size.y;
	vec3 lamp_dir = normalize(LAMP);
	vec2 g = p * CELLS + vec2(0.25, 0.4);
	vec4 hx = hex_at(g);
	vec2 q = hx.xy;
	vec2 id = hx.zw;
	float e = hex_d(q);
	float h1 = hash1(id * 7.0 + 1.0);
	float h2 = hash1(id * 3.0 + 19.0);
	vec2 centre = (g - q - vec2(0.25, 0.4)) / CELLS;
	float u = clamp(centre.x / aspect + 0.5, 0.0, 1.0);
	float v = clamp(centre.y + 0.5, 0.0, 1.0);
	float b = band(0.03 + 0.94 * u);
	float fill = 0.18 + 0.82 * smoothstep(v - 0.5, v + 0.2, b * 1.25 + (h1 - 0.5) * 0.3);
	float old = noise1(p * 1.7 + 3.0);
	vec3 wax_c = wax.rgb * (0.7 + 0.4 * old) * (0.9 + 0.2 * h2);
	float through = glow * (0.5 + 0.7 * level);

	vec3 col;
	float rim_in = 0.405;
	if (e > rim_in) {
		// The wall between cells: a rounded ridge of wax.
		vec2 a = abs(q);
		vec2 dir = dot(a, vec2(0.5, 0.8660254)) > a.x ? sign(q) * vec2(0.5, 0.8660254) : vec2(sign(q.x), 0.0);
		float t = (e - rim_in) / (0.5 - rim_in);
		vec3 n = normalize(vec3(-dir * cos(t * 1.5708) * 1.3, 1.0));
		float rough = noise1(g * 22.0);
		n = normalize(n + vec3(rough - 0.5, noise1(g * 22.0 + 5.0) - 0.5, 0.0) * 0.3);
		col = wax_c * (0.3 + 0.75 * max(dot(n, lamp_dir), 0.0)) + honey.rgb * 0.16 * through;
		col += vec3(1.0, 0.95, 0.8) * 0.25 * pow(max(dot(n, normalize(lamp_dir + vec3(0.0, 0.0, 1.0))), 0.0), 30.0);
		col *= 0.75 + 0.25 * smoothstep(0.0, 0.25, t);
	} else if (h2 < 0.07) {
		// Capped: a lid of wax, a little domed and dimpled.
		float dim = noise1(g * 9.0 + id);
		vec3 n = normalize(vec3(-q * 1.2 + (vec2(dim, noise1(g * 9.0 - id)) - 0.5) * 0.9, 1.0));
		col = wax_c * 1.1 * (0.35 + 0.75 * max(dot(n, lamp_dir), 0.0)) + honey.rgb * 0.1 * through;
	} else {
		// Open: the floor far down, the honey over it, the rim's shadow on whichever shows.
		float depth = (1.0 - fill) * 0.85;
		float lit_m = smoothstep(rim_in + 0.03, rim_in - 0.05, hex_d(q + lamp_dir.xy * depth * 0.75));
		float r = length(q);
		float ang = atan(q.y, q.x);
		float crease = r * abs(sin(1.5 * ang + 0.5236));
		vec3 floor_c = wax_c * 0.62 * (1.0 - 0.35 * smoothstep(0.035, 0.0, crease)) * (0.25 + 0.75 * lit_m);
		vec3 stuff = honey.rgb;
		float thick = 1.0 - exp(-fill * 3.0);
		if (h2 < 0.15) {
			// Pollen: packed, dull, of three colours.
			stuff = (h1 < 0.33 ? pollen.rgb : (h1 < 0.66 ? mix(pollen.rgb, vec3(0.95, 0.8, 0.25), 0.7) : pollen.rgb * vec3(0.55, 0.45, 0.6))) * (0.7 + 0.5 * noise1(g * 30.0));
			thick = 1.0;
			lit_m = smoothstep(rim_in + 0.03, rim_in - 0.05, hex_d(q + lamp_dir.xy * 0.2));
			col = stuff * (0.2 + 0.7 * lit_m);
		} else {
			vec3 hc = stuff * (0.24 + 0.4 * lit_m + 0.42 * through * (0.5 + 0.5 * fill));
			col = mix(floor_c + honey.rgb * 0.08 * through, hc, thick);
			// The lamp's glint on the honey, and the bright edge where it climbs the wall.
			vec2 gl = q - vec2(-0.13, 0.15) - 0.03 * vec2(sin(drive * 2.3 + h1 * 6.0), cos(drive * 1.9 + h2 * 6.0)) * b;
			float glint = exp(-dot(gl, gl) * 140.0) + 0.35 * exp(-dot(gl - vec2(0.09, -0.02), gl - vec2(0.09, -0.02)) * 500.0);
			float edge = smoothstep(rim_in - 0.07, rim_in, e) * smoothstep(-0.2, 0.9, dot(normalize(q + 1e-4), -lamp_dir.xy));
			col += (vec3(1.0, 0.97, 0.9) * glint * 0.6 + honey.rgb * edge * 0.45) * lit_m * smoothstep(0.03, 0.3, fill);
		}
		col *= 1.0 - 0.3 * smoothstep(rim_in - 0.04, rim_in, e) * (1.0 - fill);
	}

	// The bees.
	int count = int(bees * 5.0 + 0.5);
	for (int i = 0; i < count; i++) {
		float fi = float(i);
		float t = drive * (0.1 + 0.02 * fi) + fi * 4.1;
		vec2 fa = vec2(0.9 + 0.23 * fi, 1.3 - 0.17 * fi);
		vec2 amp = vec2(0.55 + 0.05 * fi, 0.22 + 0.03 * fi);
		vec2 mid_at = vec2(0.28 * sin(fi * 2.4), 0.2 * cos(fi * 1.7));
		vec2 at = mid_at + amp * sin(fa * t + vec2(fi * 1.3, fi * 2.9));
		vec2 vel = amp * fa * cos(fa * t + vec2(fi * 1.3, fi * 2.9));
		float sc = 0.062 + 0.006 * fi;
		vec2 dq = p - at;
		if (dot(dq, dq) > sc * sc * 3.2) {
			continue;
		}
		float head = atan(vel.y, vel.x) + 0.22 * sin(vis_time * 17.0 + fi) * bass;
		vec2 l = vec2(cos(head) * dq.x + sin(head) * dq.y, -sin(head) * dq.x + cos(head) * dq.y) / sc;
		bee(col, l, drive * 9.0 + fi * 2.0, clamp(treble * 1.4, 0.0, 1.0), px / sc);
	}
	col = 1.0 - exp(-col * 1.35);
	col *= 1.0 - 0.3 * dot(p, p);
	COLOR = vec4(col, 1.0);
}
