// Fountains (visualiser.json): a musical fountain in a round pool at night, in a garden. Sixteen jets stand in a ring,
// each a part of the spectrum, each as tall as its part is loud; a great jet in the middle rises with the bass; eight
// arcs of water leap from the rim towards the middle, higher with the middle of the sound. Coloured lamps under the
// water light each jet, the colours moving slowly round the ring.
// Each upright jet is found by the nearest the ray comes to its line, each arc by where the ray crosses the arc's
// own upright plane. The water is a plane that sends the ray back up, bent by ripples, and the jets are found again
// along it: so the whole display stands doubled in the pool. Round the pool a stone rim (two cylinders and a ring);
// beyond, paving, a line of trees and cypresses, lanterns, stars and the moon; a mist hangs in the lamps' light.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float reach = 0.7;
uniform float mist = 0.5;
uniform vec4 lamp_a : source_color = vec4(1.0, 0.75, 0.4, 1.0);
uniform vec4 lamp_b : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform vec4 lamp_c : source_color = vec4(1.0, 0.35, 0.6, 1.0);
uniform vec4 night : source_color = vec4(0.03, 0.05, 0.12, 1.0);

const vec3 C = vec3(0.0, 0.0, 6.0);
const float POOL = 8.0;

vec3 hash3v(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash3v(i).x, hash3v(i + vec2(1.0, 0.0)).x, f.x), mix(hash3v(i + vec2(0.0, 1.0)).x, hash3v(i + vec2(1.0, 1.0)).x, f.x), f.y);
}

// The lamps' colour at k round the ring (it repeats each 1).
vec3 jet_col(float k) {
	float x = fract(k) * 3.0;
	vec3 a = x < 1.0 ? lamp_a.rgb : (x < 2.0 ? lamp_b.rgb : lamp_c.rgb);
	vec3 b = x < 1.0 ? lamp_b.rgb : (x < 2.0 ? lamp_c.rgb : lamp_a.rgb);
	return mix(a, b, smoothstep(0.0, 1.0, fract(x)));
}

vec2 jet_place(int i) {
	float a = float(i) / 16.0 * TAU + 0.2;
	return C.xz + 5.0 * vec2(cos(a), sin(a));
}

// The light of all the water in the air along a ray, as far as tmax.
vec3 jets_at(vec3 ro, vec3 rd, float tmax) {
	vec3 sum = vec3(0.0);
	float hxz = max(dot(rd.xz, rd.xz), 1e-4);
	float turn = drive * 0.008;
	for (int i = 0; i < 17; i++) {
		float k = float(i) / 15.0;
		vec2 c = C.xz;
		float h = 2.0 + 8.0 * bass * reach;
		float wj = 0.15;
		if (i < 16) {
			c = jet_place(i);
			h = 0.5 + 5.0 * band(0.03 + 0.9 * k) * reach;
			wj = 0.075;
		} else {
			k = 0.5;
		}
		vec2 w = ro.xz - c;
		float t = -dot(w, rd.xz) / hxz;
		if (t < 0.0 || t > tmax) {
			continue;
		}
		float d = length(w + rd.xz * t);
		float y = ro.y + rd.y * t;
		if (y < 0.0 || y > h + 0.7 || d > 0.9) {
			continue;
		}
		float u = y / h;
		float wid = wj * (0.7 + 1.3 * u * u);
		float core = exp(-d * d / (wid * wid)) * smoothstep(1.05, 0.85, u);
		float flow = 0.75 + 0.25 * sin(y * 7.0 - vis_time * 5.0 + float(i) * 1.7);
		float crown = exp(-(y - h) * (y - h) / 0.12) * exp(-d * d / 0.09) * 0.45;
		vec3 lc = jet_col(k + turn);
		sum += mix(lc, vec3(1.0), 0.2 + 0.4 * u) * (core * flow + crown) * (1.0 - 0.45 * min(u, 1.0));
	}
	for (int j = 0; j < 8; j++) {
		float a = (float(j) + 0.5) / 8.0 * TAU;
		vec2 dir = vec2(cos(a), sin(a));
		vec2 nrm = vec2(-dir.y, dir.x);
		float dn = dot(rd.xz, nrm);
		if (abs(dn) < 0.03) {
			continue;
		}
		float t = dot(C.xz - ro.xz, nrm) / dn;
		if (t < 0.0 || t > tmax) {
			continue;
		}
		vec3 q = ro + rd * t;
		float u = (6.6 - dot(q.xz - C.xz, dir)) / 5.2;
		if (u < 0.0 || u > 1.0 || q.y < 0.0) {
			continue;
		}
		float top = 1.2 + 3.2 * mid * reach;
		float yp = 4.0 * top * u * (1.0 - u);
		float slope = 4.0 * top * (1.0 - 2.0 * u) / 5.2;
		float d = abs(q.y - yp) / sqrt(1.0 + slope * slope);
		vec3 lc = mix(jet_col(float(j) / 8.0 + 0.4 + turn), vec3(1.0), 0.4);
		sum += lc * exp(-d * d / 0.004) * 0.5 * (0.75 + 0.25 * sin(u * 30.0 - vis_time * 6.0));
	}
	return sum;
}

// The garden and the sky in direction rd.
vec3 bg_at(vec3 rd) {
	float y = max(rd.y, 0.0);
	vec3 c = mix(night.rgb * 2.2, night.rgb * 0.5, smoothstep(0.0, 0.6, y));
	float rz = max(rd.z, 0.2);
	vec2 sp = rd.xy / rz * 40.0;
	vec3 h = hash3v(floor(sp));
	c += vec3(0.9, 0.95, 1.0) * step(0.93, h.z) * smoothstep(0.12, 0.0, length(fract(sp) - 0.2 - 0.6 * h.xy)) * smoothstep(0.05, 0.3, rd.y) * 0.8;
	float m = dot(rd, normalize(vec3(-0.45, 0.42, 0.8)));
	c += vec3(1.0, 0.97, 0.88) * (smoothstep(0.9993, 0.9996, m) + 0.2 * pow(max(m, 0.0), 60.0));
	float az = rd.x / rz;
	float tl = 0.05 + 0.05 * vnoise(vec2(az * 7.0, 1.0)) + 0.025 * vnoise(vec2(az * 40.0, 3.0)) + 0.11 * pow(0.5 + 0.5 * sin(az * 34.0 + 3.0 * vnoise(vec2(az * 3.0, 5.0))), 9.0) * (0.5 + vnoise(vec2(az * 5.0, 9.0)));
	c = mix(c, night.rgb * 0.25 + vec3(0.0, 0.012, 0.005), smoothstep(tl + 0.004, tl - 0.004, rd.y));
	float ld = length(vec2((fract(az * 9.0) - 0.5) / 9.0, rd.y - 0.012));
	c += lamp_a.rgb * (smoothstep(0.006, 0.0, ld) * 0.9 + 0.08 * exp(-ld * ld * 2500.0));
	return c;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	vec3 ro = vec3(2.5 * sin(drive * 0.015), 2.6, -10.0);
	vec3 fw = normalize(vec3(0.0, 3.2, 6.0) - ro);
	vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
	vec3 up = cross(fw, rt);
	vec3 rd = normalize(fw * 1.3 + rt * p.x + up * p.y);

	vec3 col = bg_at(rd);
	float best = 1e9;
	float turn = drive * 0.008;
	if (rd.y < 0.0) {
		float t = -ro.y / rd.y;
		vec3 q = ro + rd * t;
		vec2 rel = q.xz - C.xz;
		float r = length(rel);
		best = t;
		if (r < POOL) {
			// The water: ripples, the display doubled in it, the lamps under it.
			vec3 n = normalize(vec3(0.03 * sin(q.x * 3.1 + vis_time * 1.3 + sin(q.z * 2.0)) + 0.02 * sin(r * 9.0 - vis_time * 3.0),
				1.0, 0.03 * sin(q.z * 2.7 - vis_time * 1.1 + sin(q.x * 1.6))));
			vec3 rr = reflect(rd, n);
			float fres = 0.25 + 0.75 * pow(1.0 - max(-rd.y, 0.0), 4.0);
			vec3 calm = reflect(rd, normalize(vec3(n.x * 0.25, 1.0, n.z * 0.25)));
			calm.y = max(calm.y, 0.32);
			col = night.rgb * 0.25 + (bg_at(calm) + jets_at(q, rr, 1e9)) * fres;
			for (int i = 0; i < 16; i++) {
				vec2 dd = q.xz - jet_place(i);
				float k = float(i) / 15.0;
				col += jet_col(k + turn) * (0.12 + 0.5 * band(0.03 + 0.9 * k)) * exp(-dot(dd, dd) * 1.6) * 0.5;
			}
			col += jet_col(0.5 + turn) * (0.15 + 0.6 * bass) * exp(-dot(rel, rel) * 0.6) * 0.5;
		} else {
			// The paving, in the fountain's light.
			vec2 g = fract(q.xz * 0.5);
			float joint = smoothstep(0.0, 0.04, min(g.x, g.y));
			vec3 lit = (lamp_a.rgb + lamp_b.rgb + lamp_c.rgb) * 0.33 * (0.2 + 0.6 * level) / (1.0 + 0.08 * (r - POOL) * (r - POOL));
			col = vec3(0.3, 0.29, 0.27) * (0.5 + 0.5 * joint) * (0.8 + 0.2 * hash3v(floor(q.xz * 0.5)).x) * (night.rgb * 1.6 + lit * 0.9);
			col = mix(col, bg_at(vec3(rd.x, 0.001, rd.z)) * 0.6, smoothstep(30.0, 70.0, t));
		}
	}
	// The stone rim: its outer wall, its top, its inner wall on the far side.
	vec2 oc = ro.xz - C.xz;
	float qa = dot(rd.xz, rd.xz);
	float qb = dot(oc, rd.xz);
	vec3 lit_rim = (lamp_a.rgb + lamp_b.rgb + lamp_c.rgb) * 0.33 * (0.25 + 0.6 * level);
	float d_out = qb * qb - qa * (dot(oc, oc) - (POOL + 0.7) * (POOL + 0.7));
	if (d_out > 0.0) {
		float t = (-qb - sqrt(d_out)) / qa;
		float y = ro.y + rd.y * t;
		if (t > 0.0 && t < best && y > 0.0 && y < 0.4) {
			best = t;
			col = vec3(0.32, 0.3, 0.28) * (night.rgb * 2.2 + 0.04) * (0.6 + 0.4 * y / 0.4);
		}
	}
	if (rd.y < 0.0) {
		float t = (0.4 - ro.y) / rd.y;
		vec3 q = ro + rd * t;
		float r = length(q.xz - C.xz);
		if (t < best && r > POOL && r < POOL + 0.7) {
			best = t;
			col = vec3(0.4, 0.38, 0.35) * (night.rgb * 1.5 + lit_rim * 0.35) * (0.85 + 0.15 * vnoise(q.xz * 6.0));
		}
	}
	float d_in = qb * qb - qa * (dot(oc, oc) - POOL * POOL);
	if (d_in > 0.0) {
		float t = (-qb + sqrt(d_in)) / qa;
		float y = ro.y + rd.y * t;
		if (t > 0.0 && t < best && y > 0.0 && y < 0.4) {
			best = t;
			col = vec3(0.4, 0.38, 0.35) * (night.rgb + lit_rim * 0.7);
		}
	}
	col += jets_at(ro, rd, best);
	// The mist in the lamps' light.
	float hxz = max(dot(rd.xz, rd.xz), 1e-4);
	float tm = clamp(-dot(oc, rd.xz) / hxz, 0.0, best);
	vec3 mp = ro + rd * tm;
	float md = length(mp.xz - C.xz);
	col += jet_col(0.2 + turn * 2.0) * mist * (0.05 + 0.2 * level) * exp(-md * md * 0.03) * exp(-max(mp.y, 0.0) * 0.22);
	col = 1.0 - exp(-col * 1.3);
	col *= 1.0 - 0.3 * dot(p, p);
	COLOR = vec4(col, 1.0);
}
