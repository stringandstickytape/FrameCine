// Chrome (visualiser.json): a ray-traced scene in the manner of the early ray tracers: a big mirror sphere in the
// middle of a chequered floor, seven coloured metal spheres circling it, each bouncing with its own part of the
// spectrum, under an open sky. Far off round the horizon stands a ring of glowing pillars, a spectrum of 48 bands,
// seen directly and in every reflection. Each ray bounces up to three times; spheres cast soft shadows and darken the
// floor beneath them. The camera circles slowly on the music's clock (drive); the middle sphere lifts with the bass.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float bounce = 0.6;
uniform float speed = 0.5;
uniform float pillars = 0.7;
uniform vec4 tint_a : source_color = vec4(0.95, 0.35, 0.3, 1.0);
uniform vec4 tint_b : source_color = vec4(0.3, 0.55, 0.95, 1.0);
uniform vec4 floor_a : source_color = vec4(0.82, 0.8, 0.76, 1.0);
uniform vec4 floor_b : source_color = vec4(0.2, 0.21, 0.24, 1.0);
uniform vec4 sky_top : source_color = vec4(0.18, 0.32, 0.6, 1.0);
uniform vec4 sky_low : source_color = vec4(0.75, 0.68, 0.62, 1.0);

const int SPHERES = 8;
const vec3 SUN = vec3(0.48, 0.62, -0.62);


vec3 hue(float h) {
	return clamp(abs(fract(h + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
}

// Sphere i: centre and radius. 0 the mirror in the middle; 1-7 the circling ones.
vec4 sphere_at(int i) {
	if (i == 0) {
		return vec4(0.0, 1.05 + 0.25 * bass * bounce, 0.0, 1.0);
	}
	float k = float(i - 1);
	float a = drive * speed * 0.3 + k * TAU / 7.0;
	float r = 0.42;
	float h = 1.6 * bounce * band(0.05 + k / 6.0 * 0.85);
	return vec4(cos(a) * 2.7, r + h, sin(a) * 2.7, r);
}

vec3 sphere_tint(int i) {
	if (i == 0) {
		return vec3(0.92);
	}
	return mix(tint_a.rgb, tint_b.rgb, float(i - 1) / 6.0);
}

float hit_sphere(vec3 ro, vec3 rd, vec4 s) {
	vec3 oc = ro - s.xyz;
	float b = dot(oc, rd);
	float h = b * b - dot(oc, oc) + s.w * s.w;
	if (h < 0.0) {
		return -1.0;
	}
	return -b - sqrt(h);
}

// The sky and the sun.
vec3 sky_base(vec3 d) {
	float e = d.y;
	vec3 c = mix(sky_low.rgb, sky_top.rgb, sqrt(clamp(e, 0.0, 1.0)));
	c *= e < 0.0 ? 0.6 : 1.0;
	float s = max(dot(d, SUN), 0.0);
	return c + vec3(1.0, 0.9, 0.7) * (pow(s, 900.0) * 6.0 + pow(s, 14.0) * 0.25);
}

// The sky with the ring of pillars on the horizon (the spectrum, mirrored so it closes round).
vec3 sky(vec3 d) {
	float e = d.y;
	vec3 c = sky_base(d);
	float az = atan(d.z, d.x) / TAU + 0.5;
	float n = 96.0;
	float idx = floor(az * n);
	float f = fract(az * n);
	float x = 1.0 - abs(2.0 * (idx + 0.5) / n - 1.0);
	float b = band(0.04 + x * 0.9);
	float top = 0.01 + 0.075 * b * (0.4 + pillars);
	float in_col = smoothstep(0.18, 0.28, f) * smoothstep(0.82, 0.72, f);
	float in_h = smoothstep(top + 0.02, top - 0.006, e) * smoothstep(-0.01, 0.0, e);
	vec3 pc = hue(idx / n * 2.0 + 0.55) * 0.85 + 0.15;
	float lit = in_col * in_h * pillars * 0.75;
	c = mix(c, pc * (0.95 + 0.35 * smoothstep(top - 0.03, top, e)), lit);
	c += pc * pillars * 0.25 * exp(-max(e - top, 0.0) * 25.0) * in_col * step(0.0, e) * (1.0 - in_h);
	return c;
}

// A chequered floor, filtered over a pixel's footprint w so the far tiles turn grey instead of flickering.
float checker(vec2 p, float w) {
	vec2 i = 2.0 * (abs(fract((p - 0.5 * w) * 0.5) - 0.5) - abs(fract((p + 0.5 * w) * 0.5) - 0.5)) / w;
	return 0.5 - 0.5 * i.x * i.y;
}

float soft_shadow(vec3 ro, vec3 rd) {
	float res = 1.0;
	for (int i = 0; i < SPHERES; i++) {
		vec4 s = sphere_at(i);
		vec3 oc = ro - s.xyz;
		float b = dot(oc, rd);
		float c = dot(oc, oc) - s.w * s.w;
		float h = b * b - c;
		float d = sqrt(max(0.0, s.w * s.w - h)) - s.w;
		float t = -b - sqrt(max(h, 0.0));
		res = min(res, t < 0.0 ? 1.0 : smoothstep(0.0, 1.0, 2.5 * 6.0 * d / t));
	}
	return res;
}

float occlusion(vec3 pos, vec3 nor) {
	float occ = 0.0;
	for (int i = 0; i < SPHERES; i++) {
		vec4 s = sphere_at(i);
		vec3 r = s.xyz - pos;
		float l = length(r);
		occ += max(dot(nor, r), 0.0) * s.w * s.w / (l * l * l);
	}
	return clamp(1.0 - occ, 0.0, 1.0);
}

void fragment() {
	vec2 p = (UV - 0.5) * size / size.y;
	p.y = -p.y;
	float ca = drive * speed * 0.04 + 0.6;
	vec3 ro = vec3(cos(ca) * 7.6, 2.3, sin(ca) * 7.6);
	vec3 target = vec3(0.0, 0.85, 0.0);
	vec3 fw = normalize(target - ro);
	vec3 rt = normalize(cross(fw, vec3(0.0, 1.0, 0.0)));
	vec3 up = cross(rt, fw);
	vec3 rd = normalize(p.x * rt + p.y * up + 1.55 * fw);
	float pix = 1.0 / (size.y * 1.55);

	vec3 col = vec3(0.0);
	vec3 thr = vec3(1.0);
	float spread = 1.0;
	for (int b = 0; b < 3; b++) {
		float t = 1e9;
		int id = -1;
		if (rd.y < 0.0 && ro.y > 0.0) {
			t = -ro.y / rd.y;
		}
		for (int i = 0; i < SPHERES; i++) {
			float ts = hit_sphere(ro, rd, sphere_at(i));
			if (ts > 0.0 && ts < t) {
				t = ts;
				id = i;
			}
		}
		if (t > 1e8) {
			col += thr * sky(rd);
			break;
		}
		vec3 pos = ro + rd * t;
		vec3 nor = vec3(0.0, 1.0, 0.0);
		vec3 albedo = vec3(0.5);
		float refl = 0.0;
		vec3 rtint = vec3(1.0);
		if (id < 0) {
			nor = vec3(0.0, 1.0, 0.0);
			float w = t * pix * spread / max(abs(rd.y), 0.08) * 1.5;
			float ch = checker(pos.xz, max(w, 0.001));
			albedo = mix(floor_b.rgb, floor_a.rgb, ch);
			float fres = pow(1.0 - max(dot(-rd, nor), 0.0), 5.0);
			refl = 0.1 + 0.3 * fres;
			rtint = vec3(1.0);
		} else {
			vec4 s = sphere_at(id);
			nor = (pos - s.xyz) / s.w;
			albedo = sphere_tint(id);
			refl = id == 0 ? 0.88 : 0.6;
			rtint = albedo;
		}
		float dif = max(dot(nor, SUN), 0.0);
		float sh = dif > 0.0 ? soft_shadow(pos + nor * 0.002, SUN) : 0.0;
		float ao = occlusion(pos, nor);
		float spe = pow(max(dot(reflect(rd, nor), SUN), 0.0), 80.0);
		vec3 amb = mix(sky_low.rgb, sky_top.rgb, 0.5 + 0.5 * nor.y) * 0.45;
		vec3 local = albedo * (dif * sh * vec3(1.0, 0.95, 0.85) + amb * ao) + spe * sh * 1.5;
		// Haze into the distance.
		local = mix(local, sky_base(normalize(vec3(rd.x, 0.0, rd.z) + vec3(0.0, 0.02, 0.0))), 1.0 - exp(-t * 0.025));
		col += thr * local * (1.0 - refl);
		thr *= refl * rtint;
		if (max(thr.r, max(thr.g, thr.b)) < 0.04) {
			break;
		}
		ro = pos + nor * 0.002;
		rd = reflect(rd, nor);
		// Off a curved mirror a pixel covers more of what it sees.
		spread *= id < 0 ? 1.0 : 6.0;
	}
	col = col / (1.0 + col * 0.25);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
