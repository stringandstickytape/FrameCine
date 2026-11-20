// Carousel (visualiser.json): a merry-go-round at a fair at night, seen from the cobbles in front. Twelve horses on
// twisted brass poles go round on the music's clock (drive), each rising and falling with its own part of the spectrum
// (the first horse the low notes), the jewel on its saddle cloth glowing with it. Over them a striped canopy: a
// rounding board of painted panels and mirrors hung with bulbs (glowing with the level, a slow swell running round),
// a scalloped valance, a ceiling of rafters and lamps (the bass). A mirrored centre column; a platform of planks over a
// skirt of mirrors and lamps (the high notes). Behind: a big wheel turning slowly, a helter-skelter, the stalls along
// the horizon; the wet cobbles catch the glow. The horses are drawn back to front, so each covers the one behind.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float spin = 0.4;
uniform float lift = 0.6;
uniform float lamps = 0.7;
uniform vec4 stripe_a : source_color = vec4(0.7, 0.08, 0.12, 1.0);
uniform vec4 stripe_b : source_color = vec4(0.96, 0.9, 0.76, 1.0);
uniform vec4 gilt : source_color = vec4(0.93, 0.7, 0.3, 1.0);
uniform vec4 bulb : source_color = vec4(1.0, 0.8, 0.48, 1.0);
uniform vec4 night : source_color = vec4(0.04, 0.05, 0.13, 1.0);

const int HORSES = 12;
const float HORIZON = 0.42;
// The platform: its centre's height on the screen, how flat its ellipse is, its radius; the skirt under its edge.
const float Y_PLAT = 0.25;
const float E_P = 0.14;
const float R_P = 0.6;
const float SKIRT = 0.045;
// The ring the horses go round on; the centre column.
const float R_H = 0.49;
const float R_C = 0.095;
// The canopy: the bottom of the rounding board (seen from below, so its front is higher), its radius and height.
const float Y_CAN = 0.71;
const float E_C = 0.1;
const float R_B = 0.64;
const float BOARD = 0.085;
const float Y_APEX = 0.95;


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

// Distance to a segment a-b whose thickness goes from ra to rb.
float sd_seg(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - mix(ra, rb, h);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

// A carousel horse in its own frame: facing +x, about 1.3 from nose to tail, the pole through the saddle at x = 0.
// part: 0 coat, 1 mane and tail, 2 saddle, 3 saddle cloth, 4 hooves.
float horse_sd(vec2 q, out int part) {
	float d = (length(q / vec2(0.42, 0.175)) - 1.0) * 0.175;
	d = smin(d, sd_seg(q, vec2(0.27, 0.05), vec2(0.44, 0.33), 0.1, 0.065), 0.05);
	d = smin(d, sd_seg(q, vec2(0.45, 0.37), vec2(0.66, 0.24), 0.07, 0.042), 0.03);
	d = min(d, sd_seg(q, vec2(0.45, 0.43), vec2(0.42, 0.51), 0.02, 0.008));
	// Front legs raised, prancing; hind legs reaching back.
	d = smin(d, sd_seg(q, vec2(0.3, -0.05), vec2(0.46, -0.19), 0.06, 0.033), 0.03);
	d = min(d, sd_seg(q, vec2(0.46, -0.19), vec2(0.43, -0.33), 0.033, 0.026));
	d = smin(d, sd_seg(q, vec2(0.22, -0.08), vec2(0.36, -0.25), 0.055, 0.031), 0.03);
	d = min(d, sd_seg(q, vec2(0.36, -0.25), vec2(0.5, -0.29), 0.031, 0.025));
	d = smin(d, sd_seg(q, vec2(-0.3, -0.04), vec2(-0.35, -0.27), 0.085, 0.038), 0.04);
	d = min(d, sd_seg(q, vec2(-0.35, -0.27), vec2(-0.28, -0.46), 0.038, 0.027));
	d = smin(d, sd_seg(q, vec2(-0.2, -0.08), vec2(-0.42, -0.26), 0.07, 0.036), 0.04);
	d = min(d, sd_seg(q, vec2(-0.42, -0.26), vec2(-0.5, -0.42), 0.036, 0.026));
	// The saddle's pommel and cantle.
	d = min(d, sd_seg(q, vec2(0.1, 0.16), vec2(0.12, 0.21), 0.025, 0.02));
	d = min(d, sd_seg(q, vec2(-0.15, 0.15), vec2(-0.18, 0.21), 0.03, 0.022));
	float mane = sd_seg(q, vec2(0.32, 0.2), vec2(0.47, 0.44), 0.05, 0.028);
	float tail = min(sd_seg(q, vec2(-0.39, 0.07), vec2(-0.55, 0.0), 0.035, 0.05), sd_seg(q, vec2(-0.55, 0.0), vec2(-0.6, -0.24), 0.05, 0.015));
	float hair = min(tail, mane);
	d = min(d, hair);
	part = 0;
	if (hair < 0.004) {
		part = 1;
	} else if (q.y > 0.09 && q.x > -0.21 && q.x < 0.15) {
		part = 2;
	} else if (q.y > -0.08 && abs(q.x + 0.03) < 0.17 && q.y < 0.17) {
		part = 3;
	} else if (q.y < -0.38 || (q.x > 0.38 && q.y < -0.26)) {
		part = 4;
	}
	return d;
}

// The horse's paint, lit from the canopy above (ny: how much the surface here faces up).
vec3 horse_paint(int k, vec2 q, float d, float dup, int part, float b, float glow_k) {
	float fk = float(k);
	float ny = clamp((dup - d) / 0.025, -1.0, 1.0);
	float inner = smoothstep(0.0, 0.08, -d);
	int kind = k % 6;
	vec3 coat = vec3(0.92, 0.88, 0.8);
	vec3 hair = gilt.rgb;
	if (kind == 1) {
		coat = vec3(0.72, 0.73, 0.76) * (0.78 + 0.35 * smoothstep(0.4, 0.7, vnoise(q * 16.0 + fk * 3.0)));
		hair = vec3(0.95);
	} else if (kind == 3) {
		coat = vec3(0.5, 0.26, 0.13);
		hair = vec3(0.2, 0.1, 0.06);
	} else if (kind == 5) {
		coat = vec3(0.1, 0.09, 0.09);
	}
	vec3 cloth = 0.5 + 0.5 * cos(TAU * (fk * 0.29 + vec3(0.0, 0.33, 0.67)));
	cloth = mix(cloth, stripe_a.rgb, 0.45) * 0.85;
	vec3 gold = gilt.rgb * (0.75 + 0.8 * b);
	vec3 c = coat;
	if (part == 1) {
		c = hair;
	} else if (part == 2) {
		c = mix(stripe_a.rgb * 0.7, vec3(0.3, 0.15, 0.08), 0.3);
		c = mix(c, gold, smoothstep(0.02, 0.01, abs(q.y - 0.105)));
	} else if (part == 3) {
		c = cloth;
		float edge = min(abs(abs(q.x + 0.03) - 0.155), abs(q.y + 0.065));
		c = mix(c, gold, smoothstep(0.016, 0.008, edge));
		// The jewel: it glows with this horse's part of the spectrum.
		float jl = length(q - vec2(-0.03, 0.01));
		c = mix(c, gold, smoothstep(0.036, 0.03, jl));
		c = mix(c, mix(cloth, vec3(1.0), 0.45) * (0.6 + 1.6 * b), smoothstep(0.024, 0.018, jl));
	} else if (part == 4) {
		c = gold * 0.8;
	}
	if (part == 0) {
		// Bridle and breast strap.
		float strap = min(abs(sd_seg(q, vec2(0.49, 0.42), vec2(0.6, 0.22), 0.0, 0.0)), abs(sd_seg(q, vec2(0.29, 0.16), vec2(0.42, -0.03), 0.0, 0.0)));
		c = mix(c, gold, smoothstep(0.016, 0.009, strap));
		c = mix(c, vec3(0.05), smoothstep(0.02, 0.013, length(q - vec2(0.575, 0.33))));
		c = mix(c, vec3(0.1), smoothstep(0.013, 0.007, length(q - vec2(0.655, 0.255))));
	}
	float lit = 0.6 + 0.32 * ny;
	float rim = 0.55 + 0.45 * sqrt(inner);
	float spec = smoothstep(0.5, 1.0, ny) * (1.0 - inner) * 0.45;
	return c * lit * rim * bulb.rgb * (0.75 + 0.35 * glow_k) + spec * bulb.rgb * glow_k;
}

// A bulb's light at distance l: the glass and a halo.
float bulb_glow(float l, float r, float px) {
	return 0.8 * smoothstep(r + px, r - px, l) + 0.3 * exp(-l / (r * 1.6));
}

// The light at p from a ring of n bulbs round the carousel (radius R, the ring's front at yc + e R cos), turned with
// it. A slow swell runs round the ring. stretch < 1 draws them out up and down (reflections on the wet cobbles).
float bulb_ring(vec2 p, float cx, float R, float yc, float e, float n, float turn, float r, float px, float stretch) {
	float phi = asin(clamp((p.x - cx) / R, -1.0, 1.0));
	float stp = TAU / n;
	float j0 = floor((phi - turn) / stp);
	float s = 0.0;
	for (int i = -1; i <= 1; i++) {
		float j = j0 + float(i);
		float a = (j + 0.5) * stp + turn;
		float c = cos(a);
		if (c < 0.0) {
			continue;
		}
		vec2 dd = p - vec2(cx + R * sin(a), yc + e * R * c);
		dd.y *= stretch;
		float swell = 0.75 + 0.25 * sin(mod(j, n) * stp * 5.0 - drive * 1.6);
		s += bulb_glow(length(dd), r * (0.7 + 0.3 * c), px) * swell;
	}
	return s;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;
	float cx = aspect * 0.5;
	float dx = p.x - cx;
	float turn = drive * spin * 0.17;
	float glow_k = lamps * (0.55 + 0.45 * level + 0.12 * beat);
	vec3 bc = bulb.rgb;

	// The night sky, lighter towards the fair; a few stars.
	vec3 col = mix(night.rgb, night.rgb * 1.6 + bc * 0.16, smoothstep(HORIZON + 0.55, HORIZON, p.y));
	if (p.y > 0.55) {
		vec2 sc = floor(p * 60.0);
		float h = hash1(sc + vec2(3.0, 9.0));
		if (h > 0.965) {
			vec2 sp = (sc + 0.25 + 0.5 * vec2(fract(h * 37.0), fract(h * 91.0))) / 60.0;
			col += vec3(0.75, 0.8, 1.0) * smoothstep(1.4 * px, 0.2 * px, length(p - sp)) * (h - 0.965) * 18.0 * smoothstep(0.55, 0.75, p.y);
		}
	}

	// The big wheel on the left, far off and hazy: rims, spokes, gondolas, bulbs that change colour round the rim.
	vec2 W = vec2(0.17, 0.67);
	float WR = 0.29;
	vec3 struct_c = mix(night.rgb * 0.45, col, 0.25);
	float legs = min(sd_seg(p, W, vec2(W.x - 0.14, HORIZON), 0.003, 0.006), sd_seg(p, W, vec2(W.x + 0.14, HORIZON), 0.003, 0.006));
	col = mix(col, struct_c, smoothstep(px, -px, legs));
	vec2 wq = p - W;
	float wl = length(wq);
	if (wl < WR + 0.05) {
		float wrot = drive * 0.05;
		float a = atan(wq.y, wq.x) - wrot;
		float rim = min(abs(wl - WR), abs(wl - WR * 0.93)) - 0.0018;
		float spoke = abs(fract(a / TAU * 16.0 + 0.5) - 0.5) * TAU / 16.0 * wl - 0.001;
		float frame_d = min(rim, wl < WR ? spoke : 1.0);
		frame_d = min(frame_d, wl - 0.018);
		col = mix(col, struct_c, smoothstep(px, -px, frame_d));
		// Gondolas hang under the rim's sixteen pivots.
		float gi = floor(atan(wq.y + 0.03, wq.x) / TAU * 16.0 - wrot / TAU * 16.0 + 0.5);
		for (int g = 0; g <= 1; g++) {
			float ga = (gi + float(g)) / 16.0 * TAU + wrot;
			vec2 gp = W + WR * vec2(cos(ga), sin(ga)) - vec2(0.0, 0.026);
			vec2 gq = abs(p - gp) - vec2(0.012, 0.011);
			float gd = length(max(gq, 0.0)) + min(max(gq.x, gq.y), 0.0) - 0.003;
			col = mix(col, struct_c * 1.2, smoothstep(px, -px, gd));
			col += bc * 0.25 * glow_k * smoothstep(px, -px, max(abs(p.x - gp.x) - 0.007, abs(p.y - gp.y - 0.002) - 0.004));
		}
		float ai = floor(a / TAU * 64.0) + 0.5;
		float ab = ai / 64.0 * TAU + wrot;
		vec3 rc = mix(0.5 + 0.5 * cos(TAU * (ai / 64.0 * 2.0 + drive * 0.03 + vec3(0.0, 0.33, 0.67))), vec3(1.0), 0.35);
		col += rc * bulb_glow(length(p - W - WR * vec2(cos(ab), sin(ab))), 0.0034, px) * glow_k * 0.7;
		float si = floor(a / TAU * 16.0 + 0.5);
		float sa = si / 16.0 * TAU + wrot;
		vec2 dir = vec2(cos(sa), sin(sa));
		float k = clamp(floor(dot(wq, dir) / 0.045 + 0.5), 1.0, 6.0);
		col += bc * bulb_glow(length(p - W - dir * k * 0.045), 0.0026, px) * glow_k * 0.5 * (0.55 + 0.45 * sin(k * 1.1 - drive * 2.0) * mid + 0.3 * mid);
	}

	// The helter-skelter on the right: a tower with a striped slide winding round it, a pointed roof and a flag.
	float HX = aspect * 0.915;
	if (p.y > HORIZON - 0.01 && p.y < 0.93 && abs(p.x - HX) < 0.09) {
		float hw = 0.045 - (p.y - HORIZON) * 0.035;
		float lx = (p.x - HX) / hw;
		vec3 hz = mix(night.rgb, col, 0.3);
		if (p.y < 0.79) {
			if (abs(lx) < 1.0) {
				float ph = asin(lx);
				col = mix(hz, stripe_b.rgb * 0.22 * (0.4 + 0.6 * cos(ph)), 0.85);
				col += bc * 0.3 * glow_k * smoothstep(0.012, 0.0, abs(fract((p.y - HORIZON) / 0.06) - 0.5) - 0.38) * step(abs(lx), 0.25);
			}
			if (abs(lx) < 1.45) {
				float phs = asin(clamp(lx / 1.45, -1.0, 1.0));
				for (int sd = 0; sd <= 1; sd++) {
					float ang = sd == 0 ? PI - phs : phs;
					if (sd == 0 && abs(lx) < 1.0) {
						continue;
					}
					float f = fract((p.y - HORIZON) / 0.085 + ang / TAU);
					if (f < 0.26) {
						vec3 slide = mod(floor((ang / TAU + (p.y - HORIZON) / 0.085) * 12.0), 2.0) < 1.0 ? stripe_a.rgb : stripe_b.rgb;
						slide *= (0.25 + 0.3 * abs(cos(ang))) * (sd == 0 ? 0.6 : 1.0);
						col = mix(col, mix(slide, hz, 0.25), 0.9);
						col += bc * 0.5 * glow_k * smoothstep(0.03, 0.0, abs(f - 0.02)) * step(0.5, fract(ang * 6.0));
					}
				}
			}
		} else {
			float t = (p.y - 0.79) / 0.1;
			if (t < 1.0 && abs(p.x - HX) < 0.055 * (1.0 - t)) {
				col = mix(hz, stripe_a.rgb * 0.3 * (0.6 + 0.4 * step(0.5, fract((p.x - HX) / (0.055 * (1.0 - t)) * 2.0 + 0.5))), 0.9);
			}
			float fl = p.x - HX;
			if (fl > 0.0 && fl < 0.035 && abs(p.y - 0.905 - 0.004 * sin(fl * 90.0 - vis_time * 3.0) * fl / 0.035) < 0.009 * (1.0 - fl / 0.035)) {
				col = mix(hz, stripe_a.rgb * 0.45, 0.9);
			}
			col = mix(col, hz * 0.7, smoothstep(px, -px, abs(p.x - HX) - 0.0015) * step(p.y, 0.92));
		}
	}

	// The stalls along the horizon: awnings, lit counters, strings of little lights.
	if (p.y > HORIZON - 0.005 && p.y < HORIZON + 0.09) {
		float cw = 0.13;
		float ci = floor(p.x / cw);
		float h = hash1(vec2(ci, 7.0));
		float sx = fract(p.x / cw);
		float top = HORIZON + 0.028 + 0.035 * h;
		float roof = top + 0.012 * (1.0 - abs(sx - 0.5) * 2.0);
		if (p.y < roof && sx > 0.05 && sx < 0.95) {
			vec3 sc = night.rgb * 0.8;
			if (p.y > top - 0.012) {
				sc = (mod(floor(sx * 12.0), 2.0) < 1.0 ? stripe_a.rgb : stripe_b.rgb) * 0.3;
			} else if (sx > 0.14 && sx < 0.86 && p.y > HORIZON + 0.004) {
				sc = mix(bc, 0.5 + 0.5 * cos(TAU * (h + vec3(0.0, 0.33, 0.67))), 0.3) * 0.42 * glow_k;
			}
			col = mix(col, sc, 0.85);
		}
		float lx = (fract(p.x / 0.024) - 0.5) * 0.024;
		col += mix(bc, vec3(1.0, 0.5, 0.6), step(0.5, fract(floor(p.x / 0.024) * 0.37))) * bulb_glow(length(vec2(lx, p.y - roof - 0.005)), 0.0018, px) * 0.45 * glow_k;
	}

	// The cobbles, wet, in a pool of the carousel's light.
	if (p.y < HORIZON) {
		float z = 0.06 / max(HORIZON - p.y, 0.002);
		vec2 g = vec2(dx * z * 1.4, z) * vec2(24.0, 36.0);
		g.x += floor(g.y) * 0.5;
		vec2 f = fract(g) - 0.5;
		float stone = length(max(abs(f) - vec2(0.26, 0.22), 0.0)) - 0.2;
		float aa = clamp(1.0 - fwidth(g.y) * 2.5, 0.0, 1.0);
		float hs = hash1(floor(g));
		float pool = exp(-length(vec2(dx * 0.9, (Y_PLAT - 0.12 - p.y) * 2.2)) * 2.4) * glow_k;
		vec3 gc = mix(night.rgb, vec3(0.06, 0.05, 0.045), 0.6) * (0.8 + 0.5 * hs);
		float top_lit = smoothstep(0.0, -0.15, stone) * (0.6 + 0.4 * smoothstep(0.3, -0.3, f.y));
		gc = mix(gc * 0.5, gc + bc * pool * 0.5 * top_lit, mix(0.6, 1.0 - smoothstep(-0.02, 0.06, stone) * 0.6, aa));
		gc += bc * pool * 0.12;
		// Each lamp of the skirt drawn out on the wet stones below it.
		gc += bc * bulb_ring(p, cx, R_P, Y_PLAT - SKIRT * 1.5, -E_P, 36.0, turn, 0.0045, px, 0.22) * lamps * (0.35 + 0.6 * treble) * 0.35 * (0.6 + 0.4 * top_lit);
		gc += bc * 0.1 * glow_k * exp(-abs(dx) * 1.8) * smoothstep(0.0, 0.16, p.y) * (0.6 + 0.4 * vnoise(vec2(dx * 40.0, p.y * 6.0)));
		col = gc;
	}

	// The platform: rings of planks turning with it.
	vec2 pu = vec2(dx / R_P, (Y_PLAT - p.y) / (E_P * R_P));
	float pr = length(pu);
	if (pr < 1.0) {
		float th = atan(pu.x, pu.y) - turn;
		float ring = floor(pr * 6.0);
		float cnt = 6.0 + ring * 8.0;
		float m = th / TAU * cnt;
		float joint = min(fract(m), 1.0 - fract(m)) * pr * 6.0 / cnt * TAU;
		float rj = min(fract(pr * 6.0), 1.0 - fract(pr * 6.0));
		vec3 wood = vec3(0.32, 0.2, 0.11) * (0.75 + 0.4 * hash1(vec2(floor(m), ring)));
		wood *= 0.55 + 0.25 * vnoise(vec2(m * 3.0, pr * 80.0));
		wood = mix(wood * 0.4, wood, smoothstep(0.0, 0.05, joint) * smoothstep(0.0, 0.06, rj));
		wood *= (0.35 + 0.65 * smoothstep(-1.0, 1.0, pu.y)) * (0.45 + 0.55 * pr) * bc * (0.7 + 0.5 * glow_k);
		col = mix(col, wood, smoothstep(1.0, 0.985, pr));
	}

	// The ceiling under the canopy: painted panels between gilt rafters, a lamp on each rafter.
	vec2 cu = vec2(dx / R_B, (p.y - Y_CAN) / (E_C * R_B));
	float cr = length(cu);
	if (cr < 1.0) {
		float th = atan(cu.x, cu.y) - turn;
		float m = th / TAU * 24.0;
		vec3 cc = (mod(floor(m), 2.0) < 1.0 ? stripe_a.rgb : stripe_b.rgb) * 0.3;
		cc *= (0.35 + 0.65 * smoothstep(-1.0, 1.0, cu.y)) * (0.6 + 0.4 * cr);
		float raf = abs(fract(m + 0.5) - 0.5) / 24.0 * TAU * cr * R_B;
		cc = mix(cc, gilt.rgb * 0.45, smoothstep(0.0035, 0.0015, raf));
		cc = mix(cc, gilt.rgb * 0.5, smoothstep(0.004, 0.0015, min(abs(cr - 0.42), abs(cr - 0.95)) * E_C * R_B));
		float ra = floor(m + 0.5) / 24.0 * TAU + turn;
		for (int i = 0; i < 2; i++) {
			float rr = i == 0 ? 0.62 : 0.84;
			vec2 lp = vec2(cx + R_B * rr * sin(ra), Y_CAN + E_C * R_B * rr * cos(ra));
			cc += bc * bulb_glow(length(p - lp), 0.004, px) * lamps * (0.35 + 0.9 * bass);
		}
		col = mix(col, cc, smoothstep(1.0, 0.97, cr));
	}

	// The horses and their poles, back to front: those behind the centre column first, then the column, then the rest.
	float dA = TAU / float(HORSES);
	float k0 = floor(-turn / dA + 0.5);
	for (int pass = 0; pass < 2; pass++) {
		for (int mi = 6; mi >= 0; mi--) {
			for (int sg = -1; sg <= 1; sg += 2) {
				if ((mi == 0 || mi == 6) && sg == 1) {
					continue;
				}
				float kk = k0 + float(sg * mi);
				float theta = kk * dA + turn;
				float z = cos(theta);
				if ((pass == 0) != (z < 0.0)) {
					continue;
				}
				int k = int(mod(kk, float(HORSES)));
				float hx = cx + R_H * sin(theta);
				if (abs(p.x - hx) > 0.165) {
					continue;
				}
				float s = 0.2 * (1.0 + 0.13 * z);
				float dim = z < 0.0 ? 0.42 + 0.2 * (1.0 + z) : 0.85 + 0.15 * z;
				float b = band(0.03 + float(k) / float(HORSES - 1) * 0.9);
				float hy = 0.375 - 0.03 * z + lift * 0.12 * b + 0.01 * sin(theta * 3.0 + drive * 1.3);
				// The pole: twisted brass.
				float pw = 0.0045 * (1.0 + 0.13 * z);
				float pdx = p.x - hx;
				if (abs(pdx) < pw + px && p.y > Y_PLAT - E_P * R_H * z && p.y < Y_CAN + E_C * R_H * z) {
					float t = clamp(pdx / pw, -1.0, 1.0);
					float rnd = sqrt(max(1.0 - t * t, 0.0));
					float twist = 0.5 + 0.5 * sin(p.y * 260.0 + t * 2.2);
					vec3 pc = gilt.rgb * (0.3 + 0.7 * rnd) * (0.7 + 0.4 * twist) * (0.6 + 0.5 * glow_k) + bc * pow(rnd, 10.0) * 0.35 * glow_k;
					col = mix(col, pc * dim, smoothstep(pw + px, pw - px, abs(pdx)));
				}
				float fx = max(abs(z), 0.24);
				vec2 q = (p - vec2(hx, hy)) / s;
				if (abs(q.x) < 0.68 * fx + 0.02 && q.y > -0.5 && q.y < 0.54) {
					q.x = q.x / fx * (z >= 0.0 ? 1.0 : -1.0);
					int part = 0;
					float d = horse_sd(q, part);
					float dpx = d * s * mix(fx, 1.0, 0.3);
					if (dpx < px) {
						int pd = 0;
						float dup = horse_sd(q + vec2(0.0, 0.025), pd);
						vec3 hc = horse_paint(k, q, d, dup, part, b, glow_k);
						col = mix(col, hc * dim, smoothstep(px, -px, dpx));
					}
				}
			}
		}
		if (pass == 0 && abs(dx) < R_C + px) {
			// The centre column: mirrors and painted panels in gilt frames, turning with the rest.
			float phi = asin(clamp(dx / R_C, -1.0, 1.0));
			float c = cos(phi);
			float y0 = Y_PLAT - E_P * R_C * c;
			float y1 = Y_CAN + E_C * R_C * c;
			if (p.y > y0 && p.y < y1) {
				float m = (phi - turn) / TAU * 8.0;
				float w = fract(m);
				float v = (p.y - y0) / (y1 - y0);
				vec3 cc;
				if (mod(floor(m), 2.0) < 1.0) {
					vec2 rl = vec2((fract(w * 3.0) - 0.5) * 0.03, (fract(v * 9.0 + floor(w * 3.0) * 0.5) - 0.5) * 0.05);
					cc = mix(night.rgb, bc, 0.25) * 0.6 + bc * bulb_glow(length(rl), 0.003, px) * glow_k * 0.7;
					cc += bc * 0.25 * pow(0.5 + 0.5 * sin(phi * 9.0 + v * 5.0), 12.0);
				} else {
					cc = stripe_a.rgb * 0.55;
					float ov = length(vec2((w - 0.5) / 0.32, (fract(v * 3.0) - 0.5) / 0.4));
					cc = mix(cc, stripe_b.rgb * 0.8, smoothstep(0.82, 0.78, ov));
					cc = mix(cc, gilt.rgb, smoothstep(0.12, 0.05, abs(ov - 0.85)));
					cc = mix(cc, stripe_a.rgb, smoothstep(0.25, 0.15, abs(ov - 0.45 - 0.12 * sin(atan((fract(v * 3.0) - 0.5), (w - 0.5)) * 5.0))));
				}
				float frame_w = min(min(w, 1.0 - w) * 2.0 * PI * R_C / 8.0, min(v, 1.0 - v) * (y1 - y0));
				cc = mix(gilt.rgb * 0.8, cc, smoothstep(0.003, 0.005, frame_w));
				cc *= (0.3 + 0.7 * c) * bc * (0.7 + 0.5 * glow_k);
				col = mix(col, cc, smoothstep(R_C + px, R_C - px, abs(dx)));
			}
		}
	}

	// The skirt under the platform's edge: a brass rail, mirrors and painted panels, a lamp in each.
	if (abs(dx) < R_P) {
		float phi = asin(dx / R_P);
		float c = cos(phi);
		float ye = Y_PLAT - E_P * R_P * c;
		if (p.y < ye && p.y > ye - SKIRT) {
			float v = (ye - p.y) / SKIRT;
			float m = (phi - turn) / TAU * 36.0;
			float w = fract(m);
			vec3 sc = mod(floor(m), 2.0) < 1.0 ? stripe_a.rgb * 0.6 : mix(night.rgb, bc, 0.3) * 0.7;
			sc = mix(sc, gilt.rgb * 0.8, smoothstep(0.12, 0.08, min(w, 1.0 - w)));
			if (v < 0.2) {
				sc = gilt.rgb * (0.5 + 0.5 * sin(v / 0.2 * PI));
			}
			sc *= (0.3 + 0.7 * c) * (0.7 + 0.5 * glow_k);
			col = mix(col, sc, smoothstep(R_P, R_P - 0.003, abs(dx)));
		}
		if (p.y < ye + 0.02 && p.y > ye - SKIRT - 0.03) {
			col += bc * bulb_ring(p, cx, R_P, Y_PLAT - SKIRT * 0.55, -E_P, 36.0, turn, 0.0045, px, 1.0) * lamps * (0.35 + 0.8 * treble);
		}
	}

	// The rounding board: painted panels with mirrors in gilt frames, rows of bulbs; under it the valance.
	if (abs(dx) < R_B) {
		float phi = asin(dx / R_B);
		float c = cos(phi);
		float yb = Y_CAN + E_C * R_B * c;
		if (p.y > yb && p.y < yb + BOARD) {
			float v = (p.y - yb) / BOARD;
			float m = (phi - turn) / TAU * 16.0;
			float w = fract(m);
			float idx = floor(m);
			vec3 pc = stripe_b.rgb * 0.7;
			float scroll = abs(v - 0.5 - 0.2 * sin(w * TAU * 2.0 + idx));
			pc = mix(pc, stripe_a.rgb, smoothstep(0.07, 0.035, scroll) * 0.85);
			vec2 mq = vec2((w - 0.5) * 3.4, (v - 0.5) * 1.9);
			float ml = length(mq);
			if (mod(idx, 2.0) < 1.0) {
				vec3 mirror_c = mix(stripe_b.rgb * 0.35, bc * 0.45, 0.5) + bc * 0.6 * pow(0.5 + 0.5 * sin(phi * 7.0 - v * 3.0 + turn * 2.0), 16.0) * glow_k;
				pc = mix(pc, mirror_c, smoothstep(0.62, 0.58, ml));
			} else {
				pc = mix(pc, stripe_a.rgb * 0.75, smoothstep(0.62, 0.58, ml));
				float star = ml - 0.3 * (0.75 + 0.25 * cos(atan(mq.y, mq.x) * 8.0));
				pc = mix(pc, gilt.rgb, smoothstep(0.03, -0.03, star));
			}
			pc = mix(pc, gilt.rgb, smoothstep(0.07, 0.035, abs(ml - 0.66)));
			pc = mix(pc, gilt.rgb * (0.6 + 0.4 * sin(v * PI)), step(min(w, 1.0 - w), 0.045));
			if (v < 0.18 || v > 0.82) {
				pc = gilt.rgb * (0.5 + 0.25 * sin(v * 70.0));
			}
			pc *= (0.3 + 0.7 * c) * (0.65 + 0.5 * glow_k);
			col = mix(col, pc, smoothstep(R_B, R_B - 0.003, abs(dx)));
		}
		// Valance: a scallop of cloth under each of forty, a gilt fringe at its edge.
		float m2 = (phi - turn) / TAU * 40.0;
		float f = fract(m2);
		float depth = 0.024 * sqrt(max(1.0 - (2.0 * f - 1.0) * (2.0 * f - 1.0), 0.0)) + 0.004;
		if (p.y <= yb && p.y > yb - depth) {
			vec3 vc = mod(floor(m2), 2.0) < 1.0 ? stripe_a.rgb : mix(stripe_b.rgb, stripe_a.rgb, 0.35) * 0.5;
			vc *= 0.55 + 0.45 * sin(f * PI);
			vc = mix(vc, gilt.rgb, smoothstep(0.003, 0.0015, p.y - (yb - depth)));
			vc *= (0.3 + 0.7 * c) * (0.7 + 0.5 * glow_k);
			col = mix(col, vc, smoothstep(px, -px, (yb - depth) - p.y));
		}
		if (p.y > yb - 0.05 && p.y < yb + BOARD + 0.05) {
			float lb = bulb_ring(p, cx, R_B, Y_CAN + BOARD * 0.09, E_C, 64.0, turn, 0.0048, px, 1.0);
			lb += bulb_ring(p, cx, R_B, Y_CAN + BOARD * 0.91, E_C, 64.0, turn + 0.05, 0.0048, px, 1.0);
			col += bc * lb * glow_k * 0.85;
		}
	}

	// The canopy's cone, striped, turning; a gilt ball and a pennant on top.
	float yt = Y_CAN + BOARD;
	if (p.y > yt && abs(dx) < R_B * 1.02) {
		float t = (p.y - yt) / (Y_APEX - yt);
		for (int it = 0; it < 2; it++) {
			float r = R_B * 1.02 * max(1.0 - t, 0.0);
			float c = sqrt(max(1.0 - (dx / max(r, 1e-4)) * (dx / max(r, 1e-4)), 0.0));
			t = (p.y - yt - E_C * r * c) / (Y_APEX - yt);
		}
		float r = R_B * 1.02 * (1.0 - t);
		if (t >= 0.0 && t < 1.0 && abs(dx) < r) {
			float phi = asin(dx / r);
			float c = cos(phi);
			float m = (phi - turn) / TAU * 14.0;
			float sw = fwidth(m) * 1.5;
			float st = smoothstep(0.5 - sw, 0.5 + sw, abs(fract(m) - 0.5) * 2.0);
			vec3 cc = mix(stripe_a.rgb, mix(stripe_b.rgb, stripe_a.rgb, 0.3) * 0.75, st);
			cc *= (0.25 + 0.75 * c) * (0.45 + 0.3 * (1.0 - t)) * (0.7 + 0.4 * glow_k);
			cc = mix(cc, gilt.rgb * 0.7 * (0.3 + 0.7 * c), smoothstep(0.06, 0.03, t));
			col = mix(col, cc, smoothstep(r, r - 0.003, abs(dx)));
		}
	}
	float ball = length(p - vec2(cx, Y_APEX + 0.008)) - 0.013;
	col = mix(col, gilt.rgb * (0.5 + 0.6 * smoothstep(0.013, -0.01, length(p - vec2(cx - 0.004, Y_APEX + 0.013)))), smoothstep(px, -px, ball));
	col = mix(col, gilt.rgb * 0.6, smoothstep(px, -px, max(abs(dx) - 0.0016, Y_APEX - p.y)));
	float fl = dx;
	if (fl > 0.0 && fl < 0.075) {
		float fy = 0.985 + 0.006 * sin(fl * 70.0 - vis_time * 3.5) * fl / 0.075;
		float half_h = 0.011 * (1.0 - fl / 0.075);
		col = mix(col, stripe_a.rgb * (0.7 + 0.3 * sin(fl * 70.0 - vis_time * 3.5)) * (0.6 + 0.4 * glow_k), smoothstep(px, -px, abs(p.y - fy) - half_h));
	}

	// The glow of it all in the damp air.
	col += bc * 0.1 * glow_k * exp(-length((p - vec2(cx, 0.7)) * vec2(0.8, 1.5)) * 2.4);
	col *= 1.0 - 0.3 * pow(length(UV - 0.5) * 1.25, 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
