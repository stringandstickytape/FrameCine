// Engine (visualiser.json): a straight-six engine cut open along its length, drawn flat and exact, running on the
// music's clock (drive). The crankshaft turns in its bearings, its six throws at their true angles; the rods and
// pistons follow it; over each cylinder two valves open in their turn under the lobes of a camshaft that turns at
// half the speed, their springs closing up; a toothed belt at one end drives the camshaft and a flywheel turns at
// the other. Each cylinder goes through its four strokes in the true firing order (1-5-3-6-2-4): it draws in mist,
// squeezes it, a spark fires it, and it pushes out the smoke. Each cylinder is a part of the spectrum, the low notes
// on the left, and it fires as bright as its part sounds; its exhaust port glows with it too. The oil in the sump
// takes the shape of the waveform, and two gauges show the level and the bass.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float revs = 0.5;
uniform float fire = 0.7;
uniform vec4 iron : source_color = vec4(0.2, 0.22, 0.25, 1.0);
uniform vec4 alloy : source_color = vec4(0.72, 0.73, 0.75, 1.0);
uniform vec4 flame : source_color = vec4(1.0, 0.5, 0.12, 1.0);
uniform vec4 fuel : source_color = vec4(0.3, 0.6, 0.9, 1.0);
uniform vec4 oil : source_color = vec4(0.75, 0.5, 0.1, 1.0);
uniform vec4 wall : source_color = vec4(0.04, 0.06, 0.1, 1.0);

const float PITCH = 0.19;
const float BORE = 0.07;
const float YC = -0.24;
const float THROW = 0.055;
const float ROD = 0.19;
const float DECK = 0.065;
const float CAM_Y = 0.262;

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

// A box from lo to hi.
float span_sd(vec2 q, vec2 lo, vec2 hi) {
	vec2 d = abs(q - (lo + hi) * 0.5) - (hi - lo) * 0.5;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Paint c over col where the distance d is under 0, with a dark line round it.
void over(inout vec3 col, vec3 c, float d, float px) {
	col = mix(col, c, smoothstep(px, -px, d));
	col *= 1.0 - 0.45 * smoothstep(2.5 * px, 0.0, abs(d));
}

// How far a lobe that starts to lift at start has lifted at c (0..1).
float lobe(float c, float start) {
	float t = mod(c - start, 2.0 * TAU);
	return t < PI ? pow(sin(t), 0.8) : 0.0;
}

// Round steel seen from the side: light along the middle. t: -1..1 across.
vec3 turned(vec3 base, float t) {
	return base * (0.45 + 0.65 * sqrt(max(1.0 - t * t, 0.0)));
}

// A gauge at q from its middle, its needle at v.
void gauge(inout vec3 col, vec2 q, float v, float px) {
	float r = length(q);
	if (r > 0.1) {
		return;
	}
	over(col, turned(alloy.rgb, r / 0.085 * 0.7), r - 0.085, px);
	over(col, vec3(0.025, 0.025, 0.03), r - 0.073, px);
	float a = atan(q.y, q.x);
	float t = (3.927 - (a < -1.571 ? a + TAU : a)) / 4.712;
	if (t > -0.02 && t < 1.02) {
		float tick = abs(fract(t * 10.0 + 0.5) - 0.5) / 10.0 * 4.712 * r;
		float m = smoothstep(0.003 + px, 0.003 - px, tick) * step(0.052, r) * step(r, 0.066);
		col = mix(col, t > 0.78 ? vec3(0.9, 0.15, 0.1) : vec3(0.8), m);
	}
	float na = mix(3.927, -0.785, clamp(v, 0.0, 1.0));
	float nd = seg_sd(q, vec2(0.0), vec2(cos(na), sin(na)) * 0.06);
	col = mix(col, flame.rgb, smoothstep(0.004 + px, 0.004 - px, nd));
	col = mix(col, vec3(0.3), smoothstep(0.012 + px, 0.012 - px, r));
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	p.y -= 0.07;
	float px = 1.0 / size.y;
	float th = drive * (0.4 + 3.0 * revs);

	// The wall behind: squared paper, dimly.
	vec2 gq = abs(fract(p * 10.0) - 0.5);
	vec3 col = wall.rgb * (0.7 + 0.5 * smoothstep(0.9, 0.0, length(p)));
	col += wall.rgb * 0.5 * smoothstep(0.5 - 12.0 * px, 0.5, max(gq.x, gq.y));

	// Which cylinder this is, and where it is in its four strokes.
	float fi = clamp(floor(p.x / PITCH + 3.0), 0.0, 5.0);
	int ci = int(fi);
	float lx = p.x - (fi - 2.5) * PITCH;
	float order_k = ci == 0 ? 0.0 : (ci == 1 ? 4.0 : (ci == 2 ? 2.0 : (ci == 3 ? 5.0 : (ci == 4 ? 1.0 : 3.0))));
	float cyc = mod(th - order_k * TAU / 3.0, 2.0 * TAU);
	float b = band_between(fi / 6.0 + 0.02, (fi + 1.0) / 6.0 - 0.02);
	float y_pin = YC + THROW * cos(cyc);
	float sn = THROW * sin(cyc);
	float y_w = y_pin + sqrt(ROD * ROD - sn * sn);
	float roof = DECK + 0.02 * (1.0 - lx * lx / (BORE * BORE));
	float burn = cyc < PI ? smoothstep(0.0, 0.5, cyc) * exp(-cyc * 0.9) : 0.0;

	// The sump and the block, cut: hatched iron.
	float hatch = 0.88 + 0.12 * smoothstep(0.4, 0.5, abs(fract((p.x + p.y) * 70.0) - 0.5));
	over(col, iron.rgb * 0.75 * hatch, span_sd(p, vec2(-0.5, -0.46), vec2(0.5, -0.3)) - 0.012, px);
	over(col, iron.rgb * hatch, span_sd(p, vec2(-0.64, -0.33), vec2(0.64, DECK)), px);
	over(col, alloy.rgb * 0.45 * hatch, span_sd(p, vec2(-0.64, DECK), vec2(0.64, 0.2)), px);
	// The cover over the camshaft, a thin shell.
	float cover_d = span_sd(p, vec2(-0.62, 0.2), vec2(0.62, 0.3)) - 0.02;
	over(col, alloy.rgb * 0.6, cover_d, px);
	over(col, vec3(0.03, 0.03, 0.035), cover_d + 0.012, px);
	// The hollow of the crankcase and the sump, and the oil.
	over(col, vec3(0.02, 0.02, 0.024), span_sd(p, vec2(-0.6, -0.325), vec2(0.6, -0.13)) - 0.004, px);
	float sump_d = span_sd(p, vec2(-0.49, -0.45), vec2(0.49, -0.31));
	over(col, vec3(0.02, 0.02, 0.024), sump_d, px);
	float oil_y = -0.385 + 0.004 * sin(p.x * 18.0 + drive * 2.0) + 0.012 * wave_at(0.5 + p.x * 0.5) * (0.3 + level);
	if (sump_d < 0.0) {
		float under = smoothstep(px, -px, p.y - oil_y);
		vec3 oc = oil.rgb * (0.25 + 0.5 * smoothstep(-0.45, -0.38, p.y)) + vec3(1.0, 0.9, 0.7) * 0.35 * smoothstep(0.006, 0.0, abs(p.y - oil_y));
		col = mix(col, oc, under * smoothstep(0.0, -2.0 * px, sump_d));
	}

	// The bore, and what is in it above the piston.
	float bore_d = max(max(abs(lx) - BORE, p.y - roof), -0.14 - p.y);
	if (bore_d < px) {
		float swirl = noise1(vec2(lx * 45.0 + fi * 7.0, p.y * 45.0 - drive * 1.3));
		vec3 gas;
		if (cyc < PI) {
			vec3 hot = flame.rgb * (0.25 + 1.7 * burn * (0.35 + 0.9 * b) * fire) * (0.7 + 0.6 * swirl) + vec3(1.0, 0.95, 0.8) * burn * burn * (0.3 + b) * fire;
			gas = mix(fuel.rgb * 0.75 * (0.5 + swirl), hot, smoothstep(0.0, 0.4, cyc));
		} else if (cyc < TAU) {
			gas = mix(flame.rgb * 0.25, vec3(0.13, 0.12, 0.11), (cyc - PI) / PI) * (0.6 + 0.7 * swirl);
		} else if (cyc < 3.0 * PI) {
			gas = fuel.rgb * 0.3 * ((cyc - TAU) / PI) * (0.5 + swirl);
		} else {
			gas = fuel.rgb * (0.3 + 0.45 * (cyc - 3.0 * PI) / PI) * (0.5 + swirl);
		}
		vec3 inside = p.y > y_w ? gas : iron.rgb * 0.3;
		// The liner: a pale edge down each side of the bore.
		inside = mix(inside, alloy.rgb * 0.5, smoothstep(BORE - 0.006, BORE - 0.003, abs(lx)) * 0.6);
		over(col, inside, bore_d, px);
	}
	// The fire shows through the iron about it.
	vec2 fq = vec2(lx, p.y - (roof + y_w + 0.045) * 0.5);
	col += flame.rgb * burn * (0.3 + b) * fire * 0.25 * exp(-dot(fq, fq) * 90.0);

	// Water between the bores.
	float xb = clamp(floor(p.x / PITCH + 0.5), -3.0, 3.0) * PITCH;
	float wd = span_sd(p, vec2(xb - 0.011, -0.09), vec2(xb + 0.011, 0.04)) - 0.004;
	over(col, vec3(0.1, 0.35, 0.5) * (0.6 + 0.4 * noise1(vec2(p.x * 80.0, p.y * 30.0 - drive * 0.6))), wd, px);

	// The crankshaft: the main journals, the block's bearings round them, then the throws.
	float jt = (p.y - YC) / 0.018;
	over(col, turned(alloy.rgb, jt), span_sd(p, vec2(-0.7, YC - 0.018), vec2(0.7, YC + 0.018)), px);
	float bd = min(span_sd(p, vec2(xb - 0.015, YC), vec2(xb + 0.015, -0.128)), length(p - vec2(xb, YC)) - 0.032);
	bd = max(bd, 0.019 - length(p - vec2(xb, YC)));
	over(col, iron.rgb * 1.15 * hatch, bd, px);
	float y_far = YC - 0.85 * (y_pin - YC);
	float w_lo = min(y_pin, y_far) - 0.022;
	float w_hi = max(y_pin, y_far) + 0.022;
	float ax = abs(lx);
	over(col, turned(alloy.rgb * 0.85, (ax - 0.047) / 0.012), span_sd(vec2(ax, p.y), vec2(0.036, w_lo), vec2(0.058, w_hi)) - 0.003, px);
	over(col, turned(alloy.rgb, (p.y - y_pin) / 0.015), span_sd(vec2(ax, p.y), vec2(0.0, y_pin - 0.015), vec2(0.036, y_pin + 0.015)), px);

	// The rod.
	vec2 lq = vec2(lx, p.y);
	float taper = mix(0.017, 0.011, clamp((p.y - y_pin) / ROD, 0.0, 1.0));
	float rod_d = min(seg_sd(lq, vec2(0.0, y_pin), vec2(0.0, y_w)) - taper, min(length(lq - vec2(0.0, y_pin)) - 0.03, length(lq - vec2(0.0, y_w)) - 0.021));
	over(col, turned(iron.rgb * 1.9 + 0.08, lx / 0.03), rod_d, px);
	over(col, turned(alloy.rgb, 0.3), length(lq - vec2(0.0, y_pin)) - 0.015, px);

	// The piston: its crown, three rings, the pin.
	float pis_d = span_sd(lq, vec2(-BORE + 0.003, y_w - 0.04), vec2(BORE - 0.003, y_w + 0.045)) - 0.002;
	if (pis_d < 3.0 * px) {
		vec3 pc = turned(alloy.rgb * 0.82, lx / BORE * 0.92);
		float ry = y_w + 0.045 - p.y;
		pc *= 1.0 - 0.6 * (smoothstep(0.003, 0.0015, abs(ry - 0.01)) + smoothstep(0.003, 0.0015, abs(ry - 0.02)) + smoothstep(0.003, 0.0015, abs(ry - 0.03)));
		pc += flame.rgb * burn * (0.3 + b) * fire * 0.5 * smoothstep(0.03, 0.0, ry);
		over(col, pc, pis_d, px);
		over(col, turned(iron.rgb * 2.2, 0.2), length(lq - vec2(0.0, y_w)) - 0.013, px);
	}

	// The head: for each valve its port, the valve, its spring and its lobe; then the plug.
	if (p.y > 0.03 && p.y < 0.31) {
		float side = lx < 0.0 ? -1.0 : 1.0;
		float lift_n = side < 0.0 ? lobe(cyc, TAU) : lobe(cyc, PI);
		float up_n = side < 0.0 ? lobe(cyc, 0.0) : lobe(cyc, 3.0 * PI);
		float lift = 0.017 * lift_n;
		float vx = side * 0.034;
		float seat = DECK + 0.0153;
		// The port, up and out to a round pipe cut across.
		vec2 port_end = vec2(side * 0.068, 0.15);
		float port_d = min(seg_sd(lq, vec2(vx, seat + 0.012), port_end) - 0.009, length(lq - port_end) - 0.02);
		vec3 port_c = side < 0.0 ? fuel.rgb * (0.12 + 0.35 * lift_n) : mix(vec3(0.05, 0.04, 0.04), flame.rgb, 0.12 + 0.75 * b * fire) * (0.5 + 0.5 * b + 0.5 * lift_n);
		over(col, port_c, port_d, px);
		// The spring, the stem and the valve.
		float top = 0.236 - lift;
		float st = clamp((p.y - 0.2) / (top - 0.2), 0.0, 1.0);
		float coil = abs(fract(st * 4.0 + (lx - vx) / 0.026 * 0.5) - 0.5);
		float spring_d = max(span_sd(lq, vec2(vx - 0.013, 0.2), vec2(vx + 0.013, top)), (coil - 0.25) * 0.009);
		over(col, turned(alloy.rgb, (lx - vx) / 0.013), spring_d, px);
		over(col, turned(alloy.rgb * 0.9, 0.0), span_sd(lq, vec2(vx - 0.0035, seat - lift), vec2(vx + 0.0035, top)), px);
		over(col, turned(alloy.rgb, 0.4), span_sd(lq, vec2(vx - 0.015, top - 0.003), vec2(vx + 0.015, top + 0.004)), px);
		float head_d = span_sd(lq, vec2(vx - 0.022 + (p.y - seat + lift) * 1.2, seat - lift - 0.009), vec2(vx + 0.022 - (p.y - seat + lift) * 1.2, seat - lift)) - 0.002;
		over(col, turned(alloy.rgb * 0.95, (lx - vx) / 0.03), head_d, px);
		// The lobe over it, seen edge on: its nose comes down, then goes up the far side.
		float lobe_d = span_sd(lq, vec2(vx - 0.011, CAM_Y - 0.016 - 0.01 * lift_n), vec2(vx + 0.011, CAM_Y + 0.016 + 0.01 * up_n)) - 0.003;
		over(col, turned(iron.rgb * 2.4, (lx - vx) / 0.014), lobe_d, px);
		// The plug: white, with a steel nut, and its spark.
		over(col, vec3(0.85, 0.84, 0.8) * (0.6 + 0.4 * sqrt(max(1.0 - lx * lx / 0.000049, 0.0))), span_sd(lq, vec2(-0.007, roof + 0.004), vec2(0.007, 0.2)), px);
		over(col, turned(alloy.rgb, lx / 0.012), span_sd(lq, vec2(-0.011, 0.185), vec2(0.011, 0.2)), px);
		over(col, turned(alloy.rgb * 0.8, 0.0), span_sd(lq, vec2(-0.003, roof - 0.008), vec2(0.003, roof + 0.004)), px);
		float spark = max(smoothstep(0.35, 0.0, cyc), smoothstep(2.0 * TAU - 0.25, 2.0 * TAU, cyc));
		vec2 sq = lq - vec2(0.0, roof - 0.012);
		col += vec3(0.8, 0.9, 1.0) * spark * (0.4 + b) * fire * smoothstep(0.02, 0.0, length(sq)) * 1.2;
	}
	// The camshaft itself, between the lobes.
	if (abs(p.y - CAM_Y) < 0.012 && abs(p.x) < 0.7 && abs(abs(lx) - 0.034) > 0.014) {
		over(col, turned(alloy.rgb * 0.9, (p.y - CAM_Y) / 0.008), abs(p.y - CAM_Y) - 0.008, px);
	}

	// The flywheel, edge on, with its ring of teeth going by.
	vec2 fwq = p - vec2(-0.7, YC);
	if (abs(fwq.x) < 0.04 && abs(fwq.y) < 0.21) {
		float t = fwq.y / 0.2;
		float beta = asin(clamp(t, -1.0, 1.0));
		float teeth = smoothstep(0.35, 0.45, abs(fract((beta + th) * 48.0 / TAU) - 0.5));
		vec3 fc = turned(iron.rgb * 2.0 + 0.05, t) * (0.7 + 0.3 * teeth * step(abs(fwq.x), 0.022));
		fc *= 1.0 - 0.3 * smoothstep(0.003, 0.0, abs(abs(fwq.x) - 0.022));
		over(col, fc, span_sd(fwq, vec2(-0.034, -0.2), vec2(0.034, 0.2)) - 0.002, px);
	}
	// The belt and its two wheels, edge on: the camshaft's wheel is twice the crankshaft's.
	vec2 bq = p - vec2(0.68, 0.0);
	if (abs(bq.x) < 0.03) {
		over(col, turned(iron.rgb * 1.8, (p.y - YC) / 0.05), span_sd(bq, vec2(-0.022, YC - 0.05), vec2(0.022, YC + 0.05)), px);
		over(col, turned(iron.rgb * 1.8, (p.y - CAM_Y) / 0.1), span_sd(bq, vec2(-0.022, CAM_Y - 0.1), vec2(0.022, CAM_Y + 0.1)), px);
		float cogs = smoothstep(0.3, 0.4, abs(fract((p.y - 0.05 * th) * 70.0) - 0.5));
		over(col, vec3(0.035) * (1.0 + 0.8 * cogs) * (0.6 + 0.4 * sqrt(max(1.0 - bq.x * bq.x / 0.000196, 0.0))), span_sd(bq, vec2(-0.014, YC - 0.054), vec2(0.014, CAM_Y + 0.104)) - 0.002, px);
	}

	gauge(col, p - vec2(-0.78, 0.31), level * 1.2, px);
	gauge(col, p - vec2(0.79, 0.31) + vec2(0.0, 0.0), bass, px);
	col = 1.0 - exp(-col * 1.5);
	col *= 1.0 - 0.3 * dot(p, p);
	COLOR = vec4(col, 1.0);
}
