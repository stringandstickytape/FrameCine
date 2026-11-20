// Dew web (visualiser.json): an orb web strung between two stems in a meadow at dawn, the low sun behind it. Thirty
// spokes; a capture spiral climbing round them, each turn a chord between two spokes, sagging a little; hundreds of dew
// drops strung along it, each a tiny lens: the meadow upside down in it, the sky's highlight, the sun focused to a
// point (brighter with the high notes). The silk shines where it lies across the sun's light, with colours along it
// (the middle notes). Each sector of the web is a part of the spectrum (the bass at the bottom, the high notes at the
// top): its threads shiver with it. A stabilimentum of white silk zigzags below the hub, where the spider waits. The
// meadow behind is out of focus: grass, glints of other dew as soft discs, mist, rays. frost turns the dew to ice.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float shiver = 0.5;
uniform float dew = 0.7;
uniform float frost = 0.0;
uniform vec4 sky : source_color = vec4(0.95, 0.78, 0.55, 1.0);
uniform vec4 meadow : source_color = vec4(0.3, 0.36, 0.2, 1.0);
uniform vec4 silk : source_color = vec4(1.0, 0.97, 0.92, 1.0);
uniform vec4 sun : source_color = vec4(1.0, 0.92, 0.72, 1.0);

const float SPOKES = 30.0;
const float SPACING = 0.0158;
const float R_IN = 0.072;
const float DROP_GAP = 0.013;


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

vec3 hash3(vec3 c) {
	uint h = hash_u(uint(int(c.x) + 1000) * 73856093u ^ uint(int(c.y) + 1000) * 19349663u ^ uint(int(c.z) + 100000) * 83492791u);
	uint h2 = hash_u(h);
	return vec3(float(h & 65535u), float(h >> 16u), float(h2 & 65535u)) / 65535.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x), mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

float sd_seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// The meadow behind, out of focus. simple: without the soft discs (for the views inside the drops).
vec3 backdrop(vec2 p, vec2 S, bool simple) {
	vec3 c = mix(sky.rgb, sky.rgb * vec3(0.75, 0.8, 0.95), smoothstep(0.75, 1.0, p.y));
	float top = 0.68 + 0.07 * vnoise(vec2(p.x * 2.5, 0.5)) + 0.03 * sin(p.x * 4.0);
	float hedge = smoothstep(top + 0.08, top - 0.08, p.y);
	float stems = vnoise(vec2(p.x * 24.0, p.y * 1.3)) * 0.55 + vnoise(vec2(p.x * 6.0, p.y * 0.9 + 3.0)) * 0.45;
	vec3 mc = meadow.rgb * (0.35 + 0.65 * stems) * mix(0.55, 1.0, smoothstep(0.0, 0.6, p.y));
	c = mix(c, mc, hedge);
	float sl = length(p - S);
	float sunk = 0.75 + 0.35 * level;
	c += sun.rgb * (0.55 * exp(-sl * 10.0) + 0.22 * exp(-sl * 2.6)) * sunk;
	c += sun.rgb * 0.1 * smoothstep(0.45, 0.05, abs(p.y - 0.25)) * (1.0 - hedge * 0.4);
	if (!simple) {
		// Rays through the mist.
		float ang = atan(p.y - S.y, p.x - S.x);
		float rays = vnoise(vec2(ang * 9.0, vis_time * 0.04)) * vnoise(vec2(ang * 23.0 + 5.0, vis_time * 0.03));
		c += sun.rgb * 0.18 * rays * exp(-sl * 1.6) * sunk;
		// Dew on the grass behind, as soft discs.
		for (int i = 0; i < 12; i++) {
			float fi = float(i);
			vec2 bc = vec2(fract(fi * 0.618 + 0.13 + vis_time * 0.002) * 1.9 - 0.05, 0.12 + 0.6 * fract(fi * 0.382 + 0.4));
			float br = 0.025 + 0.035 * fract(fi * 0.73);
			float bl = length(p - bc) / br;
			if (bl < 1.0) {
				float disc = smoothstep(1.0, 0.85, bl) * (0.75 + 0.25 * smoothstep(0.6, 0.95, bl));
				c += mix(sun.rgb, sky.rgb, fract(fi * 0.37)) * disc * (0.08 + 0.1 * fract(fi * 0.91)) * (0.8 + 0.2 * bass);
			}
		}
	}
	return c;
}

// The web's outline: the frame thread's distance from the hub at angle a.
float rim_r(float a) {
	return 0.4 * (1.0 + 0.07 * sin(a * 2.0 + 1.0) + 0.05 * sin(a * 3.0 + 2.0)) * (1.0 + 0.12 * max(-sin(a), 0.0));
}

// Spoke k's angle (jittered), -PI at k = 0.
float spoke_a(float k) {
	return (k + 0.32 * (hash1(vec2(mod(k, SPOKES), 5.0)) - 0.5)) * TAU / SPOKES - PI;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y);
	float px = 1.0 / size.y;
	vec2 S = vec2(aspect * 0.84, 0.84);
	vec3 col = backdrop(p, S, false);

	vec2 C = vec2(aspect * 0.45, 0.54) + vec2(0.006 * sin(vis_time * 0.5), 0.004 * sin(vis_time * 0.37));
	vec2 q = p - C;
	float r = length(q);
	float a = atan(q.y, q.x);
	float ro = rim_r(a);

	// The stems, in focus with the web: a grass blade on the left, a seed stalk on the right, lit at the edge.
	for (int i = 0; i < 2; i++) {
		float xc = i == 0 ? 0.13 + 0.06 * p.y * p.y + 0.004 * sin(vis_time * 0.6) : aspect * 0.8 - 0.04 * p.y + 0.003 * sin(vis_time * 0.5 + 1.0);
		float w = i == 0 ? 0.0065 * (1.0 - p.y * 0.55) : 0.0042;
		float top = i == 0 ? 1.1 : 0.84;
		float d = abs(p.x - xc) - w;
		if (i == 1) {
			vec2 hq = (p - vec2(xc, top + 0.03)) / vec2(0.016, 0.034);
			float head = (length(hq) - 1.0) * 0.016;
			float spikes = abs(sin(atan(hq.y, hq.x) * 14.0)) * 0.006;
			d = min(max(d, p.y - top), head - spikes * smoothstep(0.6, 1.0, length(hq)));
		}
		if (d < px) {
			float side = (p.x - xc) / max(w, 0.001);
			vec3 sc = meadow.rgb * 0.22 + sun.rgb * 0.5 * smoothstep(0.3, 1.0, side) * (0.6 + 0.3 * level);
			col = mix(col, sc, smoothstep(px, -px, d));
		}
	}

	// Mooring threads from the frame to the stems and up out of the picture.
	float moor = 1.0;
	moor = min(moor, sd_seg(p, C + rim_r(PI - 0.05) * vec2(cos(PI - 0.05), sin(PI - 0.05)), vec2(0.13 + 0.06 * 0.6 * 0.6, 0.6)));
	moor = min(moor, sd_seg(p, C + rim_r(-2.3) * vec2(cos(-2.3), sin(-2.3)), vec2(0.13 + 0.06 * 0.12 * 0.12, 0.12)));
	moor = min(moor, sd_seg(p, C + rim_r(0.1) * vec2(cos(0.1), sin(0.1)), vec2(aspect * 0.8 - 0.04 * 0.58, 0.58)));
	moor = min(moor, sd_seg(p, C + rim_r(-0.7) * vec2(cos(-0.7), sin(-0.7)), vec2(aspect * 0.8 - 0.04 * 0.2, 0.2)));
	moor = min(moor, sd_seg(p, C + rim_r(1.45) * vec2(cos(1.45), sin(1.45)), C + vec2(0.07, 0.6)));
	col += silk.rgb * 0.45 * smoothstep(1.1 * px, 0.2 * px, moor);

	if (r < ro + 0.01) {
		// Which sector: between spoke k and k + 1.
		float dA = TAU / SPOKES;
		float k = floor((a + PI) / dA);
		float a0 = spoke_a(k);
		if (a < a0) {
			k -= 1.0;
			a0 = spoke_a(k);
		}
		float a1 = spoke_a(k + 1.0);
		if (a > a1) {
			k += 1.0;
			a0 = a1;
			a1 = spoke_a(k + 1.0);
		}
		float km = mod(k, SPOKES);
		float s = clamp((a - a0) / (a1 - a0), 0.0, 1.0);
		float mid_a = 0.5 * (a0 + a1);
		float from_bottom = abs(mod(mid_a + PI * 0.5 + PI, TAU) - PI) / PI;
		float b = band(0.04 + 0.86 * from_bottom);
		vec2 e0 = vec2(cos(a0), sin(a0));
		vec2 e1 = vec2(cos(a1), sin(a1));
		vec2 n = normalize(e0 + e1);
		float h = dot(e0, n);
		vec2 td = normalize(e1 - e0);
		vec2 to_sun = normalize(p - S);

		// Spokes.
		float sp_d = min(r * abs(sin(a - a0)), r * abs(sin(a1 - a)));
		float wob = shiver * 0.0008 * b * sin(vis_time * 5.0 + k * 1.3) * sin(PI * clamp(r / ro, 0.0, 1.0));
		sp_d = abs(sp_d - abs(wob) * 0.5);
		float spoke = smoothstep(1.0 * px, 0.15 * px, sp_d) * step(0.012, r) * step(r, ro);
		float sp_glint = smoothstep(0.4, 0.0, abs(dot(normalize(q), to_sun)));
		col += silk.rgb * spoke * (0.3 + 0.7 * sp_glint);

		// The spiral: chord j of this sector, sagging and shivering.
		float sag = 0.0022 * (r / 0.4) * max(-n.y, -0.3) * sin(PI * s);
		float climb = (km + s) / SPOKES;
		float dn0 = dot(q, n);
		float j = floor(((dn0 - sag) / h - R_IN) / SPACING - climb + 0.5);
		float rlim = min(rim_r(a0), rim_r(a1)) - 0.008;
		float best = 1.0;
		vec3 drop_col = vec3(0.0);
		float drop_a = 0.0;
		float halo = 0.0;
		for (int c = 0; c < 2; c++) {
			float jj = j;
			if (c == 1) {
				float Rj0 = R_IN + (j + climb) * SPACING;
				jj = j + ((dn0 - sag) / h > Rj0 ? 1.0 : -1.0);
			}
			float Rj = R_IN + (jj + climb) * SPACING;
			if (Rj < R_IN - 0.001 || Rj > rlim) {
				continue;
			}
			float vib = shiver * 0.0016 * b * sin(PI * s) * sin(vis_time * 5.0 + jj * 0.9 + k * 1.7);
			float off = dn0 - Rj * h - sag - vib;
			if (c == 0) {
				best = abs(off);
			}
			// The drops on this chord: three slots round the pixel.
			float tau = dot(q, td);
			float half_len = Rj * sin(0.5 * (a1 - a0));
			float m0 = floor(tau / DROP_GAP);
			for (int mi = -1; mi <= 1; mi++) {
				float m = m0 + float(mi);
				vec3 hh = hash3(vec3(km * 7.0 + jj * 131.0, m + 500.0, 3.0));
				if (hh.x > 0.78 * dew + 0.05) {
					continue;
				}
				float rd = (0.0022 + 0.0068 * pow(hh.z, 2.2)) * (0.6 + 0.6 * dew);
				float tm = (m + 0.5 + 0.35 * (hh.y - 0.5)) * DROP_GAP;
				if (abs(tm) > half_len - rd) {
					continue;
				}
				vec2 dc = tm * td + (Rj * h + sag + vib) * n - vec2(0.0, 0.45 * rd);
				vec2 uv = (q - dc) / rd;
				float ul = length(uv);
				if (ul > 2.6) {
					continue;
				}
				vec2 sun_uv = -normalize(S - C - dc) * 0.5;
				float caustic = smoothstep(0.24, 0.04, length(uv - sun_uv));
				halo += exp(-length(uv - sun_uv) * 2.2) * 0.12 * rd / 0.004 * step(1.0, ul);
				if (ul < 1.0) {
					float z = sqrt(1.0 - ul * ul);
					vec3 dcol = backdrop(C + dc - vec2(uv.x, uv.y) * 0.3, S, true) * 1.15 + sky.rgb * 0.15 * (1.0 - z);
					dcol = mix(dcol, vec3(0.02), smoothstep(0.78, 1.0, ul) * 0.85);
					float fringe = smoothstep(0.7, 0.88, ul) * smoothstep(1.0, 0.9, ul) * (0.15 + 0.35 * mid);
					dcol += 0.5 * cos(TAU * (ul * 1.6 + vec3(0.0, 0.33, 0.67))) * fringe;
					dcol += sky.rgb * 0.9 * smoothstep(0.3, 0.1, length(uv - vec2(-0.38, 0.42)));
					dcol += sun.rgb * caustic * (1.3 + 0.7 * treble);
					// Ice: white and faceted.
					float facet = 0.6 + 0.4 * step(0.5, fract(atan(uv.y, uv.x) / TAU * 5.0 + ul * 0.6));
					vec3 ice = mix(silk.rgb * 0.75 * facet, sun.rgb, caustic * 0.8) * (0.7 + 0.3 * z);
					dcol = mix(dcol, ice, frost);
					float da = smoothstep(1.0, 1.0 - 1.5 * px / rd, ul);
					if (da > drop_a) {
						drop_a = da;
						drop_col = dcol;
					}
				}
			}
		}
		// The thread itself, where no drop covers it.
		float thread = smoothstep(1.0 * px, 0.1 * px, best) * step(R_IN - 0.001, R_IN + (j + climb) * SPACING) * step(R_IN + (j + climb) * SPACING, rlim);
		float glint = smoothstep(0.45, 0.0, abs(dot(td, to_sun)));
		vec3 irid = 0.5 + 0.5 * cos(TAU * (dot(q, td) * 25.0 + r * 6.0 + vec3(0.0, 0.33, 0.67)));
		vec3 tc = silk.rgb * (0.3 + 0.75 * glint) + irid * glint * (0.12 + 0.4 * mid);
		tc = mix(tc, silk.rgb * 0.9, frost * 0.5);
		col += tc * thread * (1.0 + frost * 0.6);
		col += sun.rgb * halo * (0.7 + 0.5 * treble);
		col = mix(col, drop_col, drop_a);

		// The frame thread.
		col += silk.rgb * 0.6 * smoothstep(1.3 * px, 0.2 * px, abs(r - ro));

		// The hub: a tangle of silk; below it the stabilimentum, a zigzag ribbon of white.
		if (r < 0.034) {
			float tangle = abs(sin(a * 7.0 + r * 160.0 + 3.0 * sin(a * 3.0 + 1.0)));
			col += silk.rgb * 0.5 * smoothstep(0.12, 0.0, tangle) * smoothstep(0.034, 0.02, r);
		}
		float ys = -q.y;
		if (abs(q.x) < 0.02 && ((ys > 0.03 && ys < 0.16) || (ys < -0.03 && ys > -0.08))) {
			float span = ys > 0.0 ? (ys - 0.03) / 0.13 : (-ys - 0.03) / 0.05;
			float zig = 0.0075 * (abs(fract(ys * 42.0) - 0.5) * 4.0 - 1.0) * (1.0 - 0.4 * span);
			float sd = abs(q.x - zig) - 0.0022 * (1.0 - 0.5 * span);
			col = mix(col, silk.rgb * (0.85 + 0.25 * vnoise(q * 400.0)) * (0.8 + 0.2 * level), smoothstep(px, -px, sd) * 0.9);
		}
	}

	// The spider at the hub, head down: amber where the light comes through its edges.
	vec2 sq = q - vec2(0.0, 0.004);
	if (dot(sq, sq) < 0.003) {
		float body = min(length(sq / vec2(1.0, 1.25) - vec2(0.0, 0.013)) - 0.012, length(sq + vec2(0.0, 0.004)) - 0.0075);
		float legs = 1.0;
		for (int i = 0; i < 4; i++) {
			float fi = float(i);
			for (int sd = -1; sd <= 1; sd += 2) {
				float sx = float(sd);
				vec2 root = vec2(sx * 0.004, -0.001 - fi * 0.0025);
				float ang = (-0.9 + fi * 0.55) + 0.05 * sin(vis_time * 0.7 + fi) + 0.04 * beat;
				vec2 knee = root + vec2(sx * cos(ang), -sin(ang) * 1.0 + 0.6) * 0.014;
				vec2 tip = knee + vec2(sx * cos(ang * 0.6 - 0.3), -sin(ang * 1.2) - 0.2) * 0.016;
				legs = min(legs, min(sd_seg(sq, root, knee), sd_seg(sq, knee, tip)) - 0.0011);
			}
		}
		float sd_ = min(body, legs);
		vec3 spc = vec3(0.12, 0.07, 0.04) + sun.rgb * vec3(0.5, 0.28, 0.1) * smoothstep(-0.004, 0.0, body) * step(body, 0.0);
		col = mix(col, spc, smoothstep(px, -px, sd_));
	}

	col *= 1.0 - 0.32 * pow(length(UV - 0.5) * 1.25, 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
