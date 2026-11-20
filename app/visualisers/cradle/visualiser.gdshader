// Newton's cradle (visualiser.json): five chrome balls hanging in a row from a chrome frame on a polished desk, in
// front of a wall of soft light; all of it ray-traced exactly (spheres, cylinders, planes), each ray followed through
// up to four reflections, so the balls show each other, the frame, the desk and the wall, and the desk shows them.
// The end balls swing in turn on the music's clock (drive), wider with the bass: one flies out and falls back, the
// row stands still, the other flies out. The wall behind is the spectrum as tall soft columns of light, low notes
// on the left, and every chrome surface carries it, bent. The threads that hold the balls are drawn by the nearest
// each comes to the ray.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float swing = 0.6;
uniform float wall = 0.6;
uniform vec4 chrome : source_color = vec4(0.9, 0.92, 0.95, 1.0);
uniform vec4 glow_a : source_color = vec4(1.0, 0.3, 0.5, 1.0);
uniform vec4 glow_b : source_color = vec4(0.2, 0.6, 1.0, 1.0);
uniform vec4 desk : source_color = vec4(0.08, 0.06, 0.05, 1.0);

const float R = 0.5;
const float LEN = 2.7;
const float TOP = 3.4;
const float RAIL = 0.95;

vec3 ball_c(int i, float th_l, float th_r) {
	float th = i == 0 ? th_l : (i == 4 ? th_r : 0.0);
	return vec3(float(i) - 2.0 + LEN * sin(th), TOP - LEN * cos(th), 0.0);
}

// The nearest thing along a ray: how far, its normal, and what (0 nothing, 1 ball, 2 desk, 3 wall, 4 frame).
float trace(vec3 ro, vec3 rd, float th_l, float th_r, out vec3 n, out int m) {
	float best = 1e9;
	m = 0;
	n = vec3(0.0, 1.0, 0.0);
	for (int i = 0; i < 5; i++) {
		vec3 c = ball_c(i, th_l, th_r);
		vec3 oc = ro - c;
		float b = dot(oc, rd);
		float h = b * b - (dot(oc, oc) - R * R);
		if (h > 0.0) {
			float t = -b - sqrt(h);
			if (t > 0.002 && t < best) {
				best = t;
				n = (oc + rd * t) / R;
				m = 1;
			}
		}
	}
	// The two rails along the top.
	float a_r = dot(rd.yz, rd.yz);
	for (int s = 0; s < 2; s++) {
		float zc = s == 0 ? -RAIL : RAIL;
		vec2 o2 = vec2(ro.y - TOP, ro.z - zc);
		float b = dot(o2, rd.yz);
		float h = b * b - a_r * (dot(o2, o2) - 0.0049);
		if (h > 0.0 && a_r > 1e-6) {
			float t = (-b - sqrt(h)) / a_r;
			vec3 q = ro + rd * t;
			if (t > 0.002 && t < best && abs(q.x) < 3.1) {
				best = t;
				n = vec3(0.0, q.y - TOP, q.z - zc) / 0.07;
				m = 4;
			}
		}
	}
	// The four posts.
	float a_p = dot(rd.xz, rd.xz);
	for (int s = 0; s < 4; s++) {
		vec2 pc = vec2(s % 2 == 0 ? -3.1 : 3.1, s < 2 ? -RAIL : RAIL);
		vec2 o2 = ro.xz - pc;
		float b = dot(o2, rd.xz);
		float h = b * b - a_p * (dot(o2, o2) - 0.0049);
		if (h > 0.0 && a_p > 1e-6) {
			float t = (-b - sqrt(h)) / a_p;
			vec3 q = ro + rd * t;
			if (t > 0.002 && t < best && q.y > 0.0 && q.y < TOP + 0.07) {
				best = t;
				n = vec3(q.x - pc.x, 0.0, q.z - pc.y) / 0.07;
				m = 4;
			}
		}
	}
	if (rd.y < 0.0) {
		float t = -ro.y / rd.y;
		if (t > 0.002 && t < best) {
			best = t;
			n = vec3(0.0, 1.0, 0.0);
			m = 2;
		}
	}
	if (rd.z > 0.0) {
		float t = (7.0 - ro.z) / rd.z;
		if (t > 0.002 && t < best) {
			best = t;
			n = vec3(0.0, 0.0, -1.0);
			m = 3;
		}
	}
	return best;
}

// The wall of light at q: the spectrum as soft columns.
vec3 wall_at(vec2 q) {
	float gx = (q.x + 9.0) / 18.0 * 30.0;
	float k = clamp(floor(gx), 0.0, 29.0);
	float b = band(0.03 + 0.94 * k / 29.0);
	float top = 0.5 + 5.0 * b;
	float column = smoothstep(0.5, 0.15, abs(fract(gx) - 0.5)) * smoothstep(top + 0.6, top - 0.6, q.y) * smoothstep(-0.1, 0.4, q.y);
	vec3 c = mix(glow_a.rgb, glow_b.rgb, k / 29.0) * column * (0.35 + 0.65 * clamp(q.y / max(top, 0.6), 0.0, 1.0)) * wall;
	return c + vec3(0.012, 0.012, 0.016);
}

// The rest of the room: dark, a long lamp overhead, a window behind.
vec3 room_at(vec3 d) {
	vec3 c = mix(vec3(0.03, 0.03, 0.035), vec3(0.3, 0.28, 0.27), smoothstep(-0.3, 0.9, d.y) * smoothstep(0.6, -0.4, d.z));
	c += vec3(0.02, 0.02, 0.025);
	c += vec3(1.0, 0.97, 0.9) * smoothstep(0.7, 0.85, d.y) * smoothstep(0.6, 0.35, abs(d.x)) * 1.6;
	vec2 wq = abs(d.xy / max(-d.z, 0.05) - vec2(-0.9, 0.5)) - vec2(0.3, 0.4);
	c += vec3(0.6, 0.7, 0.9) * smoothstep(0.05, 0.0, max(wq.x, wq.y)) * step(d.z, 0.0);
	vec2 wq2 = abs(d.xy / max(-d.z, 0.05) - vec2(1.1, 0.35)) - vec2(0.45, 0.3);
	c += vec3(0.9, 0.7, 0.5) * 0.6 * smoothstep(0.08, 0.0, max(wq2.x, wq2.y)) * step(d.z, 0.0);
	return c;
}

// The nearest a segment a..b comes to a ray; tr is how far along the ray that is.
float seg_ray(vec3 ro, vec3 rd, vec3 a, vec3 b, out float tr) {
	vec3 u = b - a;
	vec3 w = ro - a;
	float ud = dot(u, rd);
	float s = clamp((dot(u, w) - ud * dot(rd, w)) / max(dot(u, u) - ud * ud, 1e-5), 0.0, 1.0);
	vec3 pt = a + u * s - ro;
	tr = max(dot(pt, rd), 0.0);
	return length(pt - rd * tr);
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	vec3 ro = vec3(1.8 * sin(drive * 0.021), 2.3 + 0.3 * sin(drive * 0.013), -7.6);
	vec3 fw = normalize(vec3(0.0, 1.7, 0.0) - ro);
	vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
	vec3 up = cross(fw, rt);
	vec3 rd = normalize(fw * 1.5 + rt * p.x + up * p.y);

	float sw = sin(drive * 1.5);
	float amp = swing * (0.3 + 0.5 * bass);
	float th_r = amp * max(sw, 0.0);
	float th_l = -amp * max(-sw, 0.0);

	vec3 col = vec3(0.0);
	vec3 thr = vec3(1.0);
	vec3 o = ro;
	vec3 d = rd;
	float first = 1e9;
	bool open = true;
	for (int bnc = 0; bnc < 4; bnc++) {
		vec3 n;
		int m;
		float t = trace(o, d, th_l, th_r, n, m);
		if (bnc == 0) {
			first = t;
		}
		if (m == 0) {
			col += thr * room_at(d);
			open = false;
			break;
		}
		vec3 q = o + d * t;
		if (m == 3) {
			col += thr * wall_at(q.xy);
			open = false;
			break;
		}
		if (m == 2) {
			// The desk: its own colour in the wall's light, the balls' shadows, and a share of what it mirrors.
			float shade = 1.0;
			for (int i = 0; i < 5; i++) {
				vec3 c = ball_c(i, th_l, th_r);
				vec2 dd = q.xz - c.xz;
				shade *= 1.0 - 0.6 * exp(-dot(dd, dd) * 4.0) / (1.0 + 2.0 * (c.y - 0.7));
			}
			float grain = 0.8 + 0.2 * sin(q.z * 14.0 + 3.0 * sin(q.x * 1.1));
			vec3 lit = mix(glow_a.rgb, glow_b.rgb, clamp(q.x / 14.0 + 0.5, 0.0, 1.0)) * (0.25 + 0.7 * level) * wall + 0.25;
			col += thr * desk.rgb * grain * lit * shade * 0.9;
			thr *= 0.16 + 0.6 * pow(1.0 - max(dot(-d, n), 0.0), 3.0);
		} else if (m == 1) {
			thr *= chrome.rgb * 0.9;
		} else {
			thr *= chrome.rgb * 0.75;
		}
		o = q + n * 0.002;
		d = reflect(d, n);
	}
	if (open) {
		col += thr * room_at(d) * 0.5;
	}
	// The threads: two to each ball, one from each rail.
	for (int i = 0; i < 5; i++) {
		vec3 c = ball_c(i, th_l, th_r);
		vec3 pivot = vec3(float(i) - 2.0, TOP, 0.0);
		vec3 hook = c + normalize(pivot - c) * R;
		for (int s = 0; s < 2; s++) {
			float tr;
			float dist = seg_ray(ro, rd, hook, pivot + vec3(0.0, 0.0, s == 0 ? -RAIL : RAIL), tr);
			if (tr < first) {
				col = mix(col, vec3(0.55, 0.57, 0.6), smoothstep(0.016, 0.006, dist) * 0.8);
			}
		}
	}
	col = 1.0 - exp(-col * 1.4);
	col *= 1.0 - 0.3 * dot(p, p);
	COLOR = vec4(col, 1.0);
}
