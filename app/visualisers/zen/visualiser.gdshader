// Zen garden (visualiser.json): a dry garden of raked sand and stones under the moon, found exactly (a plane,
// ellipsoids, boxes, a cylinder). The sand is raked in straight furrows, and in rings round each of five stones; the
// low moon behind lights one side of every furrow. Each stone is a part of the spectrum: the rings round it deepen as
// its part sounds, and travel slowly outwards on the music's clock (drive), as if the stone had been dropped in water.
// A stone lantern stands at the left, its fire-box glowing with the sound and lighting the sand about it; at the
// right a stone water basin, its water ringing on every beat. Moss on the stones, fallen maple leaves on the sand,
// a bamboo fence, a maple bough against the sky, leaves drifting down, fireflies with the high notes.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float rake = 0.7;
uniform float glow = 0.6;
uniform vec4 sand : source_color = vec4(0.75, 0.72, 0.65, 1.0);
uniform vec4 rock : source_color = vec4(0.3, 0.31, 0.33, 1.0);
uniform vec4 moss : source_color = vec4(0.2, 0.4, 0.15, 1.0);
uniform vec4 lantern : source_color = vec4(1.0, 0.65, 0.3, 1.0);
uniform vec4 night : source_color = vec4(0.05, 0.08, 0.16, 1.0);
uniform vec4 leaf : source_color = vec4(0.8, 0.15, 0.1, 1.0);

const vec3 MOON = vec3(-0.45, 0.14, 0.882);
const vec3 FILL = vec3(0.3, 0.55, -0.78);
const vec3 LAMP = vec3(-4.2, 1.4, 4.6);
const vec3 BASIN = vec3(3.7, 0.5, -0.6);

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

vec3 stone_r(int i) {
	return i == 0 ? vec3(0.9, 0.75, 0.7) : (i == 1 ? vec3(0.45, 0.3, 0.4) : (i == 2 ? vec3(0.7, 0.45, 0.6) : (i == 3 ? vec3(0.55, 0.95, 0.5) : vec3(1.0, 0.3, 0.7))));
}

vec3 stone_c(int i) {
	vec2 c = i == 0 ? vec2(-2.6, 1.6) : (i == 1 ? vec2(-1.5, 2.6) : (i == 2 ? vec2(1.9, 0.4) : (i == 3 ? vec2(3.3, 3.8) : vec2(0.4, 5.2))));
	return vec3(c.x, stone_r(i).y * 0.6, c.y);
}

float stone_band(int i) {
	return band(0.05 + 0.88 * float(i) / 4.0);
}

// The sky, the moon, the bough and what lies beyond the fence, in direction rd.
vec3 sky_at(vec3 rd) {
	vec3 c = mix(night.rgb * 1.9, night.rgb * 0.6, smoothstep(0.0, 0.5, rd.y));
	float m = dot(rd, MOON);
	c += vec3(1.0, 0.96, 0.85) * (smoothstep(0.9992, 0.9995, m) + 0.3 * pow(max(m, 0.0), 90.0) + 0.12 * pow(max(m, 0.0), 6.0));
	vec2 uv = rd.xy / max(rd.z, 0.2);
	vec2 sp = uv * 45.0;
	vec3 h = hash3v(floor(sp));
	c += vec3(0.9, 0.95, 1.0) * step(0.94, h.z) * smoothstep(0.12, 0.0, length(fract(sp) - 0.2 - 0.6 * h.xy)) * 0.7;
	// Far pines.
	float ridge = 0.05 + 0.04 * vnoise(vec2(uv.x * 5.0, 2.0)) + 0.03 * abs(fract(uv.x * 9.0 + vnoise(vec2(uv.x * 3.0, 7.0))) - 0.5);
	c = mix(c, night.rgb * 0.45, smoothstep(ridge + 0.004, ridge - 0.004, uv.y));
	// The maple bough.
	float canopy = vnoise(uv * 7.0 + 3.0) * 0.6 + vnoise(uv * 19.0) * 0.4 + 0.9 * (uv.x - 0.25) + 1.6 * (uv.y - 0.22);
	c = mix(c, leaf.rgb * 0.1 + night.rgb * 0.15, smoothstep(0.62, 0.7, canopy));
	return c;
}

// The light on a surface at q with normal n: the moon, the lantern, the night.
vec3 light_at(vec3 q, vec3 n) {
	vec3 l = vec3(0.45, 0.55, 0.85) * (max(dot(n, MOON), 0.0) * 2.4 + max(dot(n, FILL), 0.0) * 0.3) + night.rgb * 0.9;
	vec3 tl = LAMP - q;
	float d2 = dot(tl, tl);
	l += lantern.rgb * glow * (0.5 + 0.7 * level) * max(dot(n, tl / sqrt(d2)), 0.0) * 2.2 / (1.0 + 0.35 * d2);
	return l;
}

// A box of half-size h about c: how far along the ray, and its normal; -1 for a miss.
float box_hit(vec3 ro, vec3 rd, vec3 c, vec3 h, out vec3 n) {
	n = vec3(0.0, 1.0, 0.0);
	vec3 inv = 1.0 / rd;
	vec3 t0 = (c - h - ro) * inv;
	vec3 t1 = (c + h - ro) * inv;
	vec3 tn = min(t0, t1);
	vec3 tf = max(t0, t1);
	float te = max(tn.x, max(tn.y, tn.z));
	if (te > min(tf.x, min(tf.y, tf.z)) || te < 0.0) {
		return -1.0;
	}
	n = tn.x > tn.y && tn.x > tn.z ? vec3(-sign(rd.x), 0.0, 0.0) : (tn.y > tn.z ? vec3(0.0, -sign(rd.y), 0.0) : vec3(0.0, 0.0, -sign(rd.z)));
	return te;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	vec3 ro = vec3(0.9 * sin(drive * 0.015), 2.5 + 0.15 * sin(drive * 0.011), -7.4);
	vec3 fw = normalize(vec3(0.0, 0.9, 1.8) - ro);
	vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
	vec3 up = cross(fw, rt);
	vec3 rd = normalize(fw * 1.4 + rt * p.x + up * p.y);

	vec3 col = sky_at(rd);
	float best = 1e9;
	// The bamboo fence.
	float tfc = (9.5 - ro.z) / rd.z;
	vec3 qf = ro + rd * tfc;
	if (qf.y < 1.6) {
		best = tfc;
		float fx = fract(qf.x * 2.5);
		float slat = smoothstep(0.0, 0.12, fx) * smoothstep(1.0, 0.88, fx);
		vec3 fc = vec3(0.1, 0.075, 0.04) * (0.35 + 0.65 * slat) * (0.6 + 0.4 * hash3v(vec2(floor(qf.x * 2.5), 4.0)).x);
		fc *= 1.0 - 0.5 * smoothstep(0.06, 0.03, min(abs(qf.y - 0.4), abs(qf.y - 1.3)));
		fc = fc * (night.rgb * 6.0 + 0.15) + night.rgb * 0.5 * (1.0 - slat);
		col = mix(fc, col, smoothstep(1.57, 1.6, qf.y));
	}
	if (rd.y < 0.0) {
		float t = -ro.y / rd.y;
		vec3 q = ro + rd * t;
		if (t < best) {
			best = t;
			// The sand: straight furrows, rings round each stone.
			vec2 g = vec2(0.0, 1.0);
			float ph = q.z * 15.0;
			float amp = 1.0;
			float shade = 1.0;
			for (int i = 0; i < 5; i++) {
				vec3 c = stone_c(i);
				vec3 r = stone_r(i);
				vec2 dv = q.xz - c.xz;
				float d = length(dv);
				float reach = max(r.x, r.z) + 1.1;
				float w = smoothstep(reach, reach - 0.25, d);
				ph = mix(ph, d * 15.0 - drive * 0.3, w);
				g = mix(g, dv / max(d, 1e-3), w);
				amp = mix(amp, 0.5 + 1.3 * stone_band(i), w);
				// The stone's shadow, away from the moon.
				vec2 sv = (dv + MOON.xz * 2.2 * r.y) / (r.xz * vec2(1.3, 2.4));
				shade *= 1.0 - 0.6 * smoothstep(1.0, 0.4, length(sv));
			}
			float far = smoothstep(26.0, 9.0, t);
			vec2 slope = g * sin(ph) * amp * rake * 0.45 * far;
			vec3 n = normalize(vec3(slope.x, 1.0, slope.y));
			vec3 alb = sand.rgb * (0.9 + 0.1 * hash3v(floor(q.xz * 60.0)).x);
			// Fallen leaves.
			vec2 lg = q.xz * 1.3;
			vec3 lh = hash3v(floor(lg) + 31.0);
			vec2 lf = (fract(lg) - 0.25 - 0.5 * lh.xy) * vec2(1.0, 1.8);
			float fallen = step(0.82, lh.z) * smoothstep(0.07, 0.05, length(lf));
			alb = mix(alb, leaf.rgb * (0.5 + 0.5 * lh.x), fallen);
			col = alb * light_at(q, n) * shade;
			// The basin's and the lantern's own shadows, a little.
			col *= 0.55 + 0.45 * smoothstep(0.5, 1.1, length(q.xz - BASIN.xz - vec2(0.3, -0.45)));
			col *= 0.6 + 0.4 * smoothstep(0.3, 0.9, length(q.xz - LAMP.xz - vec2(0.2, -0.3)));
			col = mix(col, night.rgb * 1.2, 1.0 - exp(-t * 0.018));
		}
	}
	// The stones.
	for (int i = 0; i < 5; i++) {
		vec3 c = stone_c(i);
		vec3 r = stone_r(i);
		vec3 o = (ro - c) / r;
		vec3 d = rd / r;
		float a = dot(d, d);
		float b = dot(o, d);
		float disc = b * b - a * (dot(o, o) - 1.0);
		if (disc > 0.0) {
			float t = (-b - sqrt(disc)) / a;
			vec3 q = ro + rd * t;
			if (t > 0.0 && t < best && q.y > 0.0) {
				best = t;
				vec3 n = normalize((q - c) / (r * r));
				float rough = vnoise(q.xy * 5.0 + q.z * 3.0);
				n = normalize(n + 0.35 * (vec3(vnoise(q.yz * 9.0), rough, vnoise(q.xz * 9.0)) - 0.5));
				vec3 alb = rock.rgb * (0.6 + 0.7 * rough);
				alb = mix(alb, moss.rgb * (0.6 + 0.6 * vnoise(q.xz * 14.0)), smoothstep(0.45, 0.7, n.y + 0.3 * vnoise(q.xz * 4.0) - 0.15));
				col = alb * (light_at(q, n) + vec3(0.1, 0.12, 0.18)) * (0.5 + 0.5 * smoothstep(0.0, 0.3, q.y));
				col += vec3(0.5, 0.6, 0.9) * 0.3 * pow(1.0 - max(dot(-rd, n), 0.0), 3.0) * max(dot(n, MOON) + 0.4, 0.0);
				col = mix(col, night.rgb * 1.2, 1.0 - exp(-t * 0.018));
			}
		}
	}
	// The stone lantern: a post, a table, the fire-box, a roof, a cap, a knob.
	for (int i = 0; i < 6; i++) {
		vec3 c = i == 0 ? vec3(0.0, -0.9, 0.0) : (i == 1 ? vec3(0.0, -0.33, 0.0) : (i == 2 ? vec3(0.0, 0.0, 0.0) : (i == 3 ? vec3(0.0, 0.33, 0.0) : (i == 4 ? vec3(0.0, 0.5, 0.0) : vec3(0.0, 0.68, 0.0)))));
		vec3 h = i == 0 ? vec3(0.14, 0.5, 0.14) : (i == 1 ? vec3(0.4, 0.07, 0.4) : (i == 2 ? vec3(0.27, 0.26, 0.27) : (i == 3 ? vec3(0.55, 0.07, 0.55) : (i == 4 ? vec3(0.3, 0.1, 0.3) : vec3(0.1, 0.08, 0.1)))));
		vec3 n;
		float t = box_hit(ro, rd, LAMP + c, h, n);
		if (t > 0.0 && t < best) {
			best = t;
			vec3 q = ro + rd * t;
			vec3 alb = rock.rgb * (0.7 + 0.5 * vnoise(q.xy * 8.0 + q.z * 5.0));
			col = alb * (vec3(0.45, 0.55, 0.85) * (max(dot(n, MOON), 0.0) * 2.0 + max(dot(n, FILL), 0.0) * 0.35) + night.rgb * 1.2);
			col += alb * lantern.rgb * glow * 0.35 * (0.5 + 0.7 * level) * (i == 1 || i == 3 ? 1.0 : 0.25);
			if (i == 2) {
				vec3 l = q - LAMP;
				vec2 wq = abs(n.x) > 0.5 ? l.zy : l.xy;
				float pane = step(abs(wq.x), 0.15) * step(abs(wq.y), 0.16);
				float bars = smoothstep(0.012, 0.02, abs(wq.x)) * smoothstep(0.012, 0.02, abs(wq.y));
				col = mix(col, lantern.rgb * (0.55 + 0.9 * level) * glow * 1.6 * (0.6 + 0.4 * bars), pane);
			}
		}
	}
	// The water basin: a stone drum, the water in it ringing on the beat.
	vec2 oc = ro.xz - BASIN.xz;
	float qa = dot(rd.xz, rd.xz);
	float qb = dot(oc, rd.xz);
	float qd = qb * qb - qa * (dot(oc, oc) - 0.3025);
	if (qd > 0.0) {
		float t = (-qb - sqrt(qd)) / qa;
		vec3 q = ro + rd * t;
		if (t > 0.0 && t < best && q.y > 0.0 && q.y < BASIN.y) {
			best = t;
			vec3 n = vec3(q.x - BASIN.x, 0.0, q.z - BASIN.z) / 0.55;
			col = rock.rgb * (0.6 + 0.6 * vnoise(vec2(atan(n.z, n.x) * 4.0, q.y * 9.0))) * light_at(q, n);
		}
	}
	if (rd.y < 0.0) {
		float t = (BASIN.y - ro.y) / rd.y;
		vec3 q = ro + rd * t;
		float r = length(q.xz - BASIN.xz);
		if (t < best && r < 0.55) {
			best = t;
			if (r > 0.42) {
				col = rock.rgb * (0.8 + 0.4 * vnoise(q.xz * 12.0)) * light_at(q, vec3(0.0, 1.0, 0.0));
			} else {
				float ring = sin((r - (1.0 - beat) * 0.45) * 70.0) * beat * smoothstep(0.42, 0.3, r);
				vec3 n = normalize(vec3((q.x - BASIN.x) / max(r, 1e-3) * ring * 0.25, 1.0, (q.z - BASIN.z) / max(r, 1e-3) * ring * 0.25));
				col = night.rgb * (1.6 + 1.2 * n.x + 1.2 * n.z) + vec3(0.8, 0.85, 1.0) * max(ring, 0.0) * 0.35;
			}
		}
	}
	// Leaves drifting down, and fireflies.
	for (int k = 0; k < 2; k++) {
		float fk = float(k);
		vec2 uv = p * (5.0 + 3.0 * fk) + vec2(0.4 * sin(drive * 0.11 + p.y * 3.0 + fk), drive * (0.05 + 0.02 * fk)) + fk * 7.3;
		vec3 h = hash3v(floor(uv) + fk * 11.0);
		vec2 f = fract(uv) - 0.3 - 0.4 * h.xy;
		float ang = h.x * 6.0 + drive * 0.2 * (h.y - 0.5);
		f = vec2(cos(ang) * f.x - sin(ang) * f.y, sin(ang) * f.x + cos(ang) * f.y) * vec2(1.0, 2.0);
		col = mix(col, leaf.rgb * (0.25 + 0.3 * h.y), step(0.88, h.z) * smoothstep(0.11, 0.08, length(f)));
	}
	for (int k = 0; k < 9; k++) {
		vec3 h = hash3v(vec2(float(k) * 5.0 + 1.0, 8.0));
		vec2 fp = vec2((h.x - 0.5) * 1.6 + 0.08 * sin(drive * (0.07 + 0.05 * h.y) + h.z * 9.0), -0.3 + 0.4 * h.y + 0.05 * sin(drive * (0.09 + 0.04 * h.x) + h.x * 7.0));
		float d2 = dot(p - fp, p - fp);
		float blink = (0.25 + 0.75 * treble) * (0.5 + 0.5 * sin(drive * (0.5 + h.z) + h.y * 20.0));
		col += vec3(0.8, 1.0, 0.4) * blink * (exp(-d2 * 30000.0) + 0.15 * exp(-d2 * 1500.0));
	}
	col *= 1.0 - 0.3 * dot(p, p);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
