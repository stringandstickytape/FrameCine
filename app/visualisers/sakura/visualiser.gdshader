// Sakura (visualiser.json): a night sky with the moon, far hills, and a branch of cherry blossom across the top;
// petals drift past in four layers (the far ones small, slow and faded into the sky, the near ones large, in front of
// the branch). The wind is the music's clock (drive), so loud bass blows the petals along and they never jump back;
// the middle notes sway them and the branch; the high notes make the blossom glint; the moon glows with the level.
// Each petal is worked out from its cell and the clocks, so the shader needs no memory and costs one petal per layer.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float petals = 0.55;
uniform float wind = 1.0;
uniform float glow = 0.6;
uniform vec4 petal : source_color = vec4(0.96, 0.7, 0.78, 1.0);
uniform vec4 sky : source_color = vec4(0.05, 0.07, 0.2, 1.0);


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

vec3 hash3(vec2 cell, float salt) {
	uint h = hash_u(uint(int(cell.x) + 100000) * 73856093u ^ uint(int(cell.y) + 100000) * 19349663u
			^ uint(int(salt)) * 83492791u);
	uint h2 = hash_u(h);
	uint h3 = hash_u(h2);
	return vec3(float(h & 65535u), float(h2 & 65535u), float(h3 & 65535u)) / 65535.0;
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Distance to a segment from a to b whose radius goes from ra to rb.
float limb(vec2 p, vec2 a, vec2 b, float ra, float rb) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t) - mix(ra, rb, t);
}

// The branch's limbs, as a, b (xy, zw) and the two radii.
vec4 seg_ab(int i) {
	return i == 0 ? vec4(-0.05, 0.07, 0.36, 0.2) : i == 1 ? vec4(0.36, 0.2, 0.78, 0.14)
			: i == 2 ? vec4(0.78, 0.14, 1.12, 0.24) : i == 3 ? vec4(0.36, 0.2, 0.5, 0.37)
			: i == 4 ? vec4(0.56, 0.17, 0.64, 0.05) : i == 5 ? vec4(0.78, 0.14, 0.88, 0.32)
			: vec4(0.14, 0.13, 0.22, 0.3);
}

vec2 seg_r(int i) {
	return i == 0 ? vec2(0.034, 0.024) : i == 1 ? vec2(0.024, 0.014) : i == 2 ? vec2(0.014, 0.006)
			: vec2(0.011, 0.004);
}

// One layer of petals at p (in heights): their colour and cover at this pixel.
vec4 petal_layer(vec2 p, float layer) {
	float n = 4.5 + layer * 3.0;
	float near = 1.0 - layer / 3.0;
	float fall = vis_time * (0.035 + 0.06 * near);
	float drift = drive * wind * (0.05 + 0.1 * near);
	vec2 q = (p - vec2(drift, fall)) * n;
	vec2 cell = floor(q);
	vec3 h = hash3(cell, layer);
	if (h.x > petals) {
		return vec4(0.0);
	}
	vec3 h2 = hash3(cell, layer + 10.0);
	vec2 sway = vec2(sin(vis_time * (0.9 + h2.x) + h2.y * 6.28), cos(vis_time * (0.7 + h2.z) + h.y * 6.28))
			* 0.07 * (0.4 + mid);
	vec2 l = fract(q) - 0.5 - (h.yz - 0.5) * 0.4 - sway;
	l = rot(l, drive * wind * (0.8 + h2.z) * 1.6 + h.y * 6.28);
	// Tumbling: the petal turns edge on and back.
	l.x /= max(0.2, abs(cos(vis_time * (0.6 + h2.x * 0.8) + h2.y * 9.0)));
	// An oval with a notch at its tip.
	float d = length(l / vec2(0.13, 0.085)) - 1.0;
	float notch = length((l - vec2(0.13, 0.0)) / vec2(0.04, 0.03)) - 1.0;
	d = max(d, -notch) * 0.085;
	float px = size.y / n;
	float cover_here = clamp(0.5 - d * px, 0.0, 1.0);
	vec3 c = petal.rgb * (0.8 + 0.25 * h2.x) * (0.85 + 0.15 * (l.y / 0.085));
	c = mix(c, sky.rgb + vec3(0.06), (1.0 - near) * 0.55);
	return vec4(c, cover_here * mix(0.55, 1.0, near));
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = UV * vec2(aspect, 1.0);

	// The sky, lighter at the horizon, and a few stars.
	vec3 col = mix(sky.rgb, sky.rgb * 1.6 + vec3(0.08, 0.04, 0.1), smoothstep(0.0, 1.0, p.y));
	vec2 sc = floor(p * 90.0);
	vec3 sh = hash3(sc, 99.0);
	if (sh.x > 0.985 && p.y < 0.7) {
		float star = smoothstep(0.12, 0.0, length(fract(p * 90.0) - 0.5 - (sh.yz - 0.5) * 0.5));
		col += vec3(0.6, 0.65, 0.8) * star * (0.4 + 0.4 * sh.y);
	}
	// The moon, glowing with the level.
	vec2 moon = vec2(aspect * 0.8, 0.3);
	float md = length(p - moon);
	float mr = 0.12;
	col += vec3(0.75, 0.7, 0.6) * exp(-max(md - mr, 0.0) * 9.0) * glow * (0.25 + 0.35 * level);
	if (md < mr) {
		// Soft grey seas on its face.
		vec2 mq = (p - moon) / mr;
		float seas = smoothstep(0.55, 0.0, length(mq - vec2(-0.25, -0.2))) * 0.5
				+ smoothstep(0.4, 0.0, length(mq - vec2(0.3, 0.25))) * 0.4
				+ smoothstep(0.3, 0.0, length(mq - vec2(0.1, -0.45))) * 0.3;
		vec3 face = vec3(0.93, 0.91, 0.84) * (1.0 - 0.1 * seas);
		col = mix(col, face, clamp((mr - md) * size.y, 0.0, 1.0));
	}
	// Two ranges of hills.
	float far_hill = 0.8 + 0.04 * sin(p.x * 2.3 + 1.0) + 0.025 * sin(p.x * 5.1);
	col = mix(col, sky.rgb * 0.75 + vec3(0.03, 0.03, 0.06), clamp((p.y - far_hill) * size.y, 0.0, 1.0));
	float near_hill = 0.88 + 0.05 * sin(p.x * 1.7 + 3.0) + 0.02 * sin(p.x * 4.3 + 0.5);
	col = mix(col, sky.rgb * 0.4, clamp((p.y - near_hill) * size.y, 0.0, 1.0));

	// The far petals.
	for (int i = 3; i >= 2; i--) {
		vec4 pl = petal_layer(p, float(i));
		col = mix(col, pl.rgb, pl.a);
	}

	// The branch, swaying a little about where it enters, and its blossom.
	vec2 root = vec2(-0.05, 0.07);
	vec2 bp = root + rot(p - root, 0.012 * sin(drive * 0.9) * (0.6 + mid));
	float branch = 1e5;
	for (int i = 0; i < 7; i++) {
		vec4 s = seg_ab(i);
		vec2 r = seg_r(i);
		branch = min(branch, limb(bp, s.xy, s.zw, r.x, r.y));
	}
	col = mix(col, vec3(0.06, 0.035, 0.04), clamp(0.5 - branch * size.y, 0.0, 1.0));
	if (branch < 0.08) {
		for (int i = 0; i < 7; i++) {
			vec4 s = seg_ab(i);
			for (int j = 0; j < 5; j++) {
				vec3 h = hash3(vec2(float(i), float(j)), 3.0);
				float t = (float(j) + 0.2 + 0.6 * h.x) / 5.0;
				vec2 a = mix(s.xy, s.zw, t);
				vec2 nrm = normalize(vec2(s.y - s.w, s.z - s.x));
				vec2 c = a + nrm * (h.y - 0.5) * 0.07;
				vec2 l = bp - c;
				float rad = (0.018 + 0.014 * h.z) * (1.0 + 0.15 * band(h.x));
				float ang = atan(l.y, l.x) + h.y * 6.28;
				float shape = length(l) - rad * (0.78 + 0.22 * cos(ang * 5.0));
				if (shape < 0.004) {
					float a_in = clamp(0.5 - shape * size.y, 0.0, 1.0);
					float glint = treble * 0.55 * (0.5 + 0.5 * sin(vis_time * (1.5 + h.z) + h.x * 30.0));
					vec3 bc = mix(petal.rgb * 1.05, vec3(0.85, 0.35, 0.5), smoothstep(rad * 0.6, 0.0, length(l)));
					col = mix(col, bc * (0.85 + glint), a_in);
				}
			}
		}
	}

	// The near petals, in front of the branch.
	for (int i = 1; i >= 0; i--) {
		vec4 pl = petal_layer(p, float(i));
		col = mix(col, pl.rgb, pl.a);
	}
	COLOR = vec4(col, 1.0);
}
