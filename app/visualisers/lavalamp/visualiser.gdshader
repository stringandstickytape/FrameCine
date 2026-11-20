// Lava lamps (visualiser.json): three lava lamps on a shelf in a dark room, ray-marched. Each lamp is a tapered glass
// vessel between a spun-metal base and cap; in it five blobs of wax rise and sink on the music's clock (drive),
// melting into each other and into the pool at the bottom and the cap of wax at the top (a smooth union). The lamps
// are the low, the middle and the high notes: each blob is a part of its lamp's third of the spectrum and swells as
// its part sounds, and the lamp's glow on the wall and the shelf follows its third.
// A ray first meets the lamp's round bound (exact), then is marched to the metal or the glass, and inside the glass
// marched again through the wax; the liquid glows by how much of it the ray crosses, brightest by the bulb.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float flow = 0.5;
uniform float heat = 0.6;
uniform vec4 wax_a : source_color = vec4(1.0, 0.25, 0.1, 1.0);
uniform vec4 wax_b : source_color = vec4(0.2, 0.9, 0.5, 1.0);
uniform vec4 wax_c : source_color = vec4(0.6, 0.3, 1.0, 1.0);
uniform vec4 liquid : source_color = vec4(0.15, 0.1, 0.35, 1.0);
uniform vec4 metal : source_color = vec4(0.75, 0.75, 0.8, 1.0);

const float GAP = 2.5;

vec3 hash3v(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float vessel_r(float y) {
	return mix(0.62, 0.36, clamp(y / 3.0, 0.0, 1.0));
}

float vessel_sd(vec3 q) {
	return max((length(q.xz) - vessel_r(q.y)) * 0.97, abs(q.y - 1.5) - 1.5);
}

float metal_sd(vec3 q) {
	float l = length(q.xz);
	float base = max((l - 0.42 - 0.5 * abs(q.y + 0.6)) * 0.85, abs(q.y + 0.6) - 0.6);
	float cap = max((l - mix(0.38, 0.2, clamp((q.y - 3.0) * 2.0, 0.0, 1.0))) * 0.93, abs(q.y - 3.25) - 0.25);
	return min(base, cap);
}

// The wax at q in lamp number lamp: the pool, the cap, five blobs.
float wax_sd(vec3 q, float lamp) {
	float d = (length(q * vec3(1.0, 2.6, 1.0)) - 0.6) / 2.6;
	d = smin(d, (length((q - vec3(0.0, 3.0, 0.0)) * vec3(1.0, 2.6, 1.0)) - 0.36) / 2.6, 0.2);
	for (int j = 0; j < 5; j++) {
		float fj = float(j);
		vec3 h = hash3v(vec2(lamp * 7.0 + 1.0, fj * 3.0 + 2.0));
		float ph = drive * flow * 0.09 * (0.5 + h.x) + h.y * TAU;
		float y = 1.5 + 1.3 * sin(ph);
		vec2 xz = (vessel_r(y) - 0.3) * 0.7 * vec2(sin(ph * 0.7 + h.z * 6.0), cos(ph * 0.9 + h.x * 6.0));
		float rad = 0.16 + 0.1 * h.z + 0.13 * band((lamp + (fj + 0.5) / 5.0) / 3.0);
		vec3 e = q - vec3(xz.x, y, xz.y);
		e.y *= 0.8;
		d = smin(d, length(e) - rad, 0.3);
	}
	return d;
}

vec3 wax_col(float lamp) {
	return lamp < 0.5 ? wax_a.rgb : (lamp < 1.5 ? wax_b.rgb : wax_c.rgb);
}

float lamp_level(float lamp) {
	return lamp < 0.5 ? bass : (lamp < 1.5 ? mid : treble);
}

vec3 room_at(vec3 d) {
	vec3 c = vec3(0.02, 0.018, 0.025) + vec3(0.07, 0.07, 0.09) * smoothstep(0.0, 1.0, d.y);
	c += vec3(0.8, 0.85, 1.0) * smoothstep(0.9, 0.98, dot(d, normalize(vec3(-0.5, 0.6, -0.6)))) * 0.8;
	return c;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	vec3 ro = vec3(0.7 * sin(drive * 0.019), 1.5 + 0.15 * sin(drive * 0.013), -8.0);
	vec3 fw = normalize(vec3(0.0, 1.15, 0.0) - ro);
	vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
	vec3 up = cross(fw, rt);
	vec3 rd = normalize(fw * 1.3 + rt * p.x + up * p.y);

	// The wall and the shelf, in the lamps' light.
	vec3 col = vec3(0.0);
	float best = 1e9;
	float tw = (2.2 - ro.z) / rd.z;
	vec3 qw = ro + rd * tw;
	best = tw;
	float paper = 0.8 + 0.2 * step(0.5, fract(qw.x * 1.4)) * step(0.5, fract(qw.y * 1.4 + floor(qw.x * 1.4) * 0.5));
	col = vec3(0.012, 0.01, 0.014) * paper;
	for (int i = 0; i < 3; i++) {
		float fi = float(i);
		vec2 dd = (qw.xy - vec2((fi - 1.0) * GAP, 1.3)) * vec2(1.0, 0.55);
		col += wax_col(fi) * mix(vec3(1.0), liquid.rgb * 3.0, 0.35) * paper * (0.1 + 0.45 * lamp_level(fi) * heat) * exp(-dot(dd, dd) * 0.5);
	}
	if (rd.y < 0.0) {
		float t = (-1.2 - ro.y) / rd.y;
		vec3 q = ro + rd * t;
		if (t < best) {
			best = t;
			col = vec3(0.016, 0.012, 0.01) * (0.8 + 0.2 * sin(q.x * 9.0 + sin(q.z * 3.0)));
			for (int i = 0; i < 3; i++) {
				float fi = float(i);
				vec2 dd = q.xz - vec2((fi - 1.0) * GAP, 0.0);
				float r2 = dot(dd, dd);
				col += wax_col(fi) * (0.08 + 0.3 * lamp_level(fi) * heat) * exp(-r2 * 0.5) * smoothstep(0.5, 0.9, r2 + 0.3);
				col *= 0.4 + 0.6 * smoothstep(0.4, 0.75, r2);
			}
		}
	}

	// The lamp this ray can meet: its round bound, exactly.
	float a = dot(rd.xz, rd.xz);
	for (int i = 0; i < 3; i++) {
		float lamp = float(i);
		vec3 lo = ro - vec3((lamp - 1.0) * GAP, 0.0, 0.0);
		float b = dot(lo.xz, rd.xz);
		float disc = b * b - a * (dot(lo.xz, lo.xz) - 0.7225);
		if (disc < 0.0) {
			continue;
		}
		float t = (-b - sqrt(disc)) / a;
		float t_out = (-b + sqrt(disc)) / a;
		// To the metal or the glass.
		float kind = 0.0;
		for (int s = 0; s < 28; s++) {
			vec3 q = lo + rd * t;
			float dm = metal_sd(q);
			float dv = vessel_sd(q);
			float d = min(dm, dv);
			if (d < 0.003) {
				kind = dm < dv ? 1.0 : 2.0;
				break;
			}
			t += d;
			if (t > t_out) {
				break;
			}
		}
		if (kind < 0.5 || t > best) {
			continue;
		}
		best = t;
		vec3 q = lo + rd * t;
		vec2 k = vec2(0.004, -0.004);
		vec3 wc = wax_col(lamp);
		float loud = lamp_level(lamp);
		if (kind < 1.5) {
			vec3 n = normalize(k.xyy * metal_sd(q + k.xyy) + k.yyx * metal_sd(q + k.yyx) + k.yxy * metal_sd(q + k.yxy) + k.xxx * metal_sd(q + k.xxx));
			vec3 r = reflect(rd, n);
			col = metal.rgb * (0.12 + 0.85 * room_at(r)) * (0.94 + 0.06 * sin(q.y * 36.0));
			col += wc * metal.rgb * (0.1 + 0.3 * loud * heat) * smoothstep(0.5, 0.0, abs(q.y - (q.y < 1.0 ? 0.0 : 3.0)));
		} else {
			float l = max(length(q.xz), 1e-3);
			vec3 ng = normalize(vec3(q.x / l, 0.087, q.z / l));
			// Through the liquid, to the wax or out again.
			float t0 = t;
			float ti = t + 0.01;
			bool hit = false;
			for (int s = 0; s < 36; s++) {
				vec3 w = lo + rd * ti;
				if (vessel_sd(w) > 0.01) {
					break;
				}
				float d = wax_sd(w, lamp);
				if (d < 0.004) {
					hit = true;
					break;
				}
				ti += max(d, 0.01);
			}
			vec3 w = lo + rd * ti;
			float depth = ti - t0;
			float ymid = clamp((q.y + w.y) * 0.5, 0.0, 3.0);
			vec3 liq = mix(liquid.rgb, wc, 0.3) * (0.35 + 0.9 * (1.0 - ymid / 3.0)) * (0.6 + 0.6 * loud * heat);
			vec3 inner;
			if (hit) {
				vec3 n = normalize(k.xyy * wax_sd(w + k.xyy, lamp) + k.yyx * wax_sd(w + k.yyx, lamp) + k.yxy * wax_sd(w + k.yxy, lamp) + k.xxx * wax_sd(w + k.xxx, lamp));
				float below = (0.5 - 0.5 * n.y) * (1.3 - w.y / 3.0);
				float rim = pow(1.0 - max(dot(-rd, n), 0.0), 2.0);
				inner = wc * (0.3 + 1.0 * below + 0.35 * rim) * (0.75 + 0.5 * loud * heat);
				inner = mix(inner, liq, 1.0 - exp(-depth * 0.5));
			} else {
				inner = liq * (1.0 - exp(-depth * 1.4)) * 0.8 + col * 0.25;
			}
			// The bulb's light at the foot of the glass.
			inner += mix(wc, vec3(1.0, 0.9, 0.7), 0.5) * 0.25 * exp(-q.y * 2.5) * (0.6 + 0.5 * loud * heat);
			float facing = max(dot(-rd, ng), 0.0);
			float fres = 0.04 + 0.5 * pow(1.0 - facing, 4.0);
			vec3 rr = reflect(rd, ng);
			col = inner * (1.0 - fres) + room_at(rr) * fres;
			col += vec3(1.0) * pow(max(dot(rr, normalize(vec3(-0.5, 0.6, -0.6))), 0.0), 60.0) * 0.5;
		}
	}
	col *= 1.0 - 0.3 * dot(p, p);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
