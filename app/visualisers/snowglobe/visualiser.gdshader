// Snow globe (visualiser.json): a snow globe on a table in a dark room, a string of coloured lamps out of focus behind.
// The glass is a true sphere: the ray is bent as it goes in, the little scene inside is ray-marched from there (a
// winter village: two houses, a church with a tower and spire, five firs, a snowman, on drifted snow), and a ray that
// meets nothing is bent again on the way out, so the room shows through the top of the glass upside down, as it does.
// The glass also mirrors the room: a window behind the viewer, a highlight.
// The music: the windows of the first house glow with the bass, the second's with the middle, the church's with the
// top, and their light lies on the snow; the star on the spire shines with the high notes; the snow in the water
// (seven sheets of flakes at different depths, hidden by whatever stands in front) falls and sways on the music's
// clock (drive); each lamp on the string behind is a part of the spectrum.
// The stand is a turned wooden drum with brass bands and a plate (an exact cylinder). No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float snow = 0.6;
uniform float swirl = 0.5;
uniform vec4 window : source_color = vec4(1.0, 0.72, 0.35, 1.0);
uniform vec4 walls : source_color = vec4(0.6, 0.2, 0.15, 1.0);
uniform vec4 pine : source_color = vec4(0.1, 0.3, 0.18, 1.0);
uniform vec4 stand : source_color = vec4(0.3, 0.14, 0.07, 1.0);
uniform vec4 room : source_color = vec4(0.1, 0.06, 0.05, 1.0);

const vec3 G = vec3(0.0, 0.15, 0.0);
const float GROUND = -0.5;
const vec3 MOON = vec3(-0.43, 0.75, -0.5);

vec3 hash3v(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float box_sd(vec3 q, vec3 h) {
	vec3 d = abs(q) - h;
	return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
}

// A house standing on y = 0, half-size h, its ridge along z; roof is 1 when the nearest part is the roof.
float house_sd(vec3 q, vec3 h, out float roof) {
	float w = box_sd(q - vec3(0.0, h.y, 0.0), h);
	float y = q.y - 2.0 * h.y;
	float r = max(max((abs(q.x) + y - 1.16 * h.x) * 0.7071, abs(q.z) - h.z - 0.02), -y);
	roof = step(r, w);
	return min(w, r);
}

float cone_sd(vec3 q, float apex, float foot, float rad) {
	vec2 n = normalize(vec2(apex - foot, rad));
	return max(dot(vec2(length(q.xz), q.y - apex), n), foot - q.y);
}

vec2 tree_place(int i) {
	return i == 0 ? vec2(-0.62, -0.12) : (i == 1 ? vec2(0.62, 0.28) : (i == 2 ? vec2(-0.15, -0.4) : (i == 3 ? vec2(-0.25, 0.58) : vec2(0.42, -0.38))));
}

vec3 house_a(vec3 l) {
	vec3 a = l - vec3(-0.36, 0.0, 0.08);
	a.xz = rot(a.xz, 0.35);
	return a;
}

vec3 house_b(vec3 l) {
	vec3 b = l - vec3(0.36, 0.0, -0.02);
	b.xz = rot(b.xz, -0.4);
	return b;
}

// The village at q (from the globe's middle): the distance, and what it is (0 snow, 1 2 house, 3 4 second house,
// 5 6 church, 7 tower, 8 spire, 9 fir, 10 snowman; the even ones of each pair the roofs).
vec2 map(vec3 q) {
	float d = (q.y - GROUND - 0.04 * sin(q.x * 5.0 + 1.0) * sin(q.z * 4.3 + 2.0)) * 0.9;
	float m = 0.0;
	vec3 l = q - vec3(0.0, GROUND, 0.0);
	float rf;
	float da = house_sd(house_a(l), vec3(0.15, 0.1, 0.12), rf);
	if (da < d) {
		d = da;
		m = 1.0 + rf;
	}
	float db = house_sd(house_b(l), vec3(0.12, 0.085, 0.1), rf);
	if (db < d) {
		d = db;
		m = 3.0 + rf;
	}
	vec3 c = l - vec3(0.02, 0.0, 0.3);
	float dc = house_sd((c - vec3(0.12, 0.0, 0.0)).zyx, vec3(0.09, 0.11, 0.16), rf);
	if (dc < d) {
		d = dc;
		m = 5.0 + rf;
	}
	float dtw = box_sd(c - vec3(-0.1, 0.2, 0.0), vec3(0.06, 0.2, 0.06));
	if (dtw < d) {
		d = dtw;
		m = 7.0;
	}
	float dsp = cone_sd(c - vec3(-0.1, 0.0, 0.0), 0.68, 0.4, 0.078);
	if (dsp < d) {
		d = dsp;
		m = 8.0;
	}
	for (int i = 0; i < 5; i++) {
		vec2 tp = tree_place(i);
		vec3 t = l - vec3(tp.x, 0.0, tp.y);
		float hgt = 0.25 + 0.04 * float(i % 3);
		float dt = min(cone_sd(t, hgt, 0.07, 0.1), cone_sd(t, hgt * 0.7, 0.03, 0.13));
		if (dt < d) {
			d = dt;
			m = 9.0;
		}
	}
	vec3 s = l - vec3(0.1, 0.0, -0.44);
	float dm = min(length(s - vec3(0.0, 0.055, 0.0)) - 0.065, length(s - vec3(0.0, 0.15, 0.0)) - 0.045);
	if (dm < d) {
		d = dm;
		m = 10.0;
	}
	return vec2(d, m);
}

// A wall's windows at l (the house's own frame, the ground at 0), n the wall's normal there: 1 in a lit pane.
float panes(vec3 l, vec3 n, float sill, float top) {
	float along = abs(n.x) > abs(n.z) ? l.z : l.x;
	float g = along / 0.085 + 0.5;
	vec2 f = vec2(fract(g) - 0.5, (l.y - sill) / (top - sill) - 0.5);
	float inside = step(abs(f.x), 0.27) * step(abs(f.y), 0.5) * step(abs(n.y), 0.5);
	return inside * (0.55 + 0.45 * step(0.035, abs(f.x)) * step(0.06, abs(f.y)));
}

// The room in direction rd: dark and warm, a string of lamps out of focus ahead, a window behind.
vec3 room_at(vec3 rd) {
	vec3 c = room.rgb * (0.3 + 0.55 * smoothstep(-0.3, 0.6, rd.y));
	if (rd.z > 0.15) {
		vec2 uv = rd.xy / rd.z;
		for (int row = 0; row < 3; row++) {
			float fr = float(row);
			float yy = 0.5 - 0.27 * fr + 0.06 * cos(uv.x * 4.0 + fr * 2.0);
			float gx = uv.x / 0.21 + fr * 0.37;
			vec3 h = hash3v(vec2(floor(gx), fr * 9.0 + 2.0));
			float d = length(vec2((fract(gx) - 0.5) * 0.21, uv.y - yy));
			vec3 lc = 0.55 + 0.45 * cos(TAU * (floor(h.x * 5.0) / 5.0 + vec3(0.0, 0.33, 0.67)));
			lc = mix(lc, vec3(1.0, 0.8, 0.5), 0.35);
			float disc = smoothstep(0.056, 0.046, d) * (0.75 + 0.25 * smoothstep(0.02, 0.05, d));
			c += lc * disc * (0.2 + 0.45 * band(0.03 + 0.92 * h.y));
		}
	} else if (rd.z < -0.2) {
		vec2 uv = rd.xy / -rd.z - vec2(-0.7, 0.55);
		vec2 dd = abs(uv) - vec2(0.3, 0.42);
		float pane = smoothstep(0.06, 0.0, max(dd.x, dd.y)) * smoothstep(0.0, 0.03, abs(uv.x)) * smoothstep(0.0, 0.03, abs(uv.y));
		c += vec3(0.55, 0.65, 0.9) * pane * 0.9;
	}
	return c;
}

// What the bent ray meets inside the glass, from e (on the sphere) along rin.
vec3 inside_at(vec3 e, vec3 rin) {
	float chord = -2.0 * dot(e, rin);
	float t = 0.01;
	float m = -1.0;
	for (int i = 0; i < 44; i++) {
		vec2 r = map(e + rin * t);
		if (r.x < 0.002) {
			m = r.y;
			break;
		}
		t += r.x * 0.9;
		if (t > chord) {
			break;
		}
	}
	vec3 col;
	if (m < 0.0) {
		// Nothing: out through the far side of the glass, bent again.
		t = chord;
		vec3 x = e + rin * chord;
		vec3 rout = refract(rin, -x, 1.2);
		if (dot(rout, rout) < 0.01) {
			rout = reflect(rin, -x);
		}
		col = room_at(rout) * 0.85;
	} else {
		vec3 q = e + rin * t;
		vec2 k = vec2(0.003, -0.003);
		vec3 n = normalize(k.xyy * map(q + k.xyy).x + k.yyx * map(q + k.yyx).x + k.yxy * map(q + k.yxy).x + k.xxx * map(q + k.xxx).x);
		vec3 l = q - vec3(0.0, GROUND, 0.0);
		float dif = clamp(dot(n, MOON), 0.0, 1.0);
		vec3 lit = vec3(0.7, 0.8, 1.0) * dif * 0.75 + vec3(0.14, 0.18, 0.3);
		vec3 white = vec3(0.92, 0.95, 1.0);
		vec3 alb = white;
		vec3 glow = vec3(0.0);
		// How loud each building is, and its light on what is near.
		float la = 0.3 + 1.2 * bass;
		float lb = 0.3 + 1.2 * mid;
		float lc = 0.3 + 1.2 * treble;
		vec3 pa = house_a(l);
		vec3 pb = house_b(l);
		vec3 pc = l - vec3(0.14, 0.0, 0.3);
		if (m < 0.5) {
			alb = white * (0.9 + 0.1 * hash3v(floor(q.xz * 300.0)).x);
			glow = window.rgb * 0.5 * (la * exp(-dot(pa.xz, pa.xz) * 22.0) + lb * exp(-dot(pb.xz, pb.xz) * 26.0) + lc * exp(-dot(pc.xz, pc.xz) * 18.0));
		} else if (m < 1.5) {
			alb = walls.rgb;
			glow = window.rgb * la * panes(pa, n, 0.06, 0.15);
		} else if (m < 2.5 || (m > 3.5 && m < 4.5) || (m > 5.5 && m < 6.5)) {
			alb = mix(vec3(0.25, 0.12, 0.1), white, smoothstep(0.2, 0.6, n.y));
		} else if (m < 3.5) {
			alb = mix(walls.rgb, vec3(0.8, 0.75, 0.6), 0.6);
			glow = window.rgb * lb * panes(pb, n, 0.05, 0.13);
		} else if (m < 5.5) {
			alb = vec3(0.6, 0.58, 0.55);
			glow = window.rgb * lc * panes(pc.zyx, n.zyx, 0.06, 0.18);
		} else if (m < 7.5) {
			alb = vec3(0.55, 0.53, 0.5);
			glow = window.rgb * lc * panes(vec3(pc.x + 0.24, pc.y, pc.z) * vec3(2.4, 1.0, 2.4), n, 0.26, 0.36) * step(l.y, 0.37) * step(0.25, l.y);
		} else if (m < 8.5) {
			alb = vec3(0.2, 0.22, 0.3);
		} else if (m < 9.5) {
			alb = mix(pine.rgb, white, 0.55 * smoothstep(0.45, 0.75, fract(l.y * 16.0 + 0.3 * sin(atan(n.z, n.x) * 5.0))));
		}
		col = alb * lit + glow + alb * window.rgb * 0.0;
		col = mix(col, vec3(0.2, 0.25, 0.4), 0.25 * smoothstep(0.3, 1.8, t));
	}
	// The star on the spire.
	vec3 tip = vec3(-0.08, GROUND + 0.7, 0.3);
	vec3 tc = cross(tip - e, rin);
	float along = dot(tip - e, rin);
	if (along < t + 0.02) {
		float d2 = dot(tc, tc);
		col += window.rgb * (0.25 + 1.1 * treble) * (exp(-d2 * 1500.0) + 0.3 * exp(-d2 * 150.0));
	}
	// The snow in the water.
	float flakes = 0.0;
	float clock = drive * (0.4 + swirl);
	for (int k = 0; k < 7; k++) {
		float fk = float(k);
		float ts = (-0.75 + 0.25 * fk - e.z) / rin.z;
		if (ts < 0.0 || ts > t) {
			continue;
		}
		vec3 s = e + rin * ts;
		if (dot(s, s) > 0.9) {
			continue;
		}
		vec2 uv = s.xy * (9.0 + fk) + vec2(sin(clock * 0.13 + fk * 1.3) * 1.5 * swirl + fk * 3.7, clock * (0.1 + 0.03 * fk));
		vec3 h = hash3v(floor(uv) + fk * 17.0);
		float rad = 0.06 + 0.06 * h.x;
		flakes += step(h.z, 0.2 + 0.6 * snow) * smoothstep(rad, rad * 0.3, length(fract(uv) - 0.25 - 0.5 * h.xy));
	}
	col += vec3(0.9, 0.93, 1.0) * min(flakes, 1.0) * 0.6;
	return col;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	vec3 ro = vec3(0.4 * sin(drive * 0.02), 0.45 + 0.08 * sin(drive * 0.013), -4.4);
	vec3 fw = normalize(vec3(0.0, -0.05, 0.0) - ro);
	vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
	vec3 up = cross(fw, rt);
	vec3 rd = normalize(fw * 1.55 + rt * p.x + up * p.y);

	vec3 col = room_at(rd);
	float best = 1e9;
	if (rd.y < 0.0) {
		// The table.
		float t = (-1.25 - ro.y) / rd.y;
		vec3 q = ro + rd * t;
		best = t;
		float grain = 0.75 + 0.25 * sin(q.z * 3.0 + 6.0 * hash3v(floor(vec2(q.x * 2.0, 0.0))).x + sin(q.x * 40.0) * 0.3);
		vec3 wood = stand.rgb * 0.55 * grain;
		float r = length(q.xz);
		wood *= 0.3 + 0.7 * smoothstep(0.75, 1.5, length(q.xz - vec2(0.15, 0.12)));
		wood += window.rgb * 0.05 * (0.4 + level) * exp(-(r - 0.8) * (r - 0.8) * 5.0);
		col = wood + room_at(reflect(rd, vec3(0.0, 1.0, 0.0))) * 0.22;
		col *= exp(-t * 0.04);
	}
	// The stand: a wooden drum, brass bands, a plate at the front.
	float qa = dot(rd.xz, rd.xz);
	float qb = dot(ro.xz, rd.xz);
	float qd = qb * qb - qa * (dot(ro.xz, ro.xz) - 0.64);
	if (qd > 0.0) {
		float t = (-qb - sqrt(qd)) / qa;
		vec3 q = ro + rd * t;
		if (t > 0.0 && t < best && q.y > -1.25 && q.y < -0.62) {
			best = t;
			vec3 n = vec3(q.x, 0.0, q.z) / 0.8;
			float ang = atan(q.x, -q.z);
			float dif = 0.25 + 0.75 * clamp(dot(n, normalize(vec3(-0.6, 0.3, -0.7))), 0.0, 1.0);
			vec3 c = stand.rgb * (0.85 + 0.15 * sin(ang * 60.0 + 4.0 * sin(q.y * 9.0))) * dif;
			float bandy = min(abs(q.y + 0.68), abs(q.y + 1.19));
			vec3 br = vec3(0.85, 0.62, 0.25) * (0.25 + 0.9 * pow(dif, 3.0));
			c = mix(c, br, smoothstep(0.045, 0.035, bandy));
			vec2 pl = abs(vec2(ang * 0.8, q.y + 0.94)) - vec2(0.26, 0.09);
			float pd = max(pl.x, pl.y);
			c = mix(c, br * (0.8 + 0.2 * step(0.02, abs(fract((q.y + 0.94) * 14.0) - 0.5))), smoothstep(0.01, 0.0, pd));
			col = c;
		}
	}
	if (rd.y < 0.0) {
		float t = (-0.62 - ro.y) / rd.y;
		vec3 q = ro + rd * t;
		if (t < best && dot(q.xz, q.xz) < 0.64) {
			best = t;
			col = stand.rgb * 0.5 * (0.5 + 0.5 * smoothstep(0.62, 0.8, length(q.xz)));
		}
	}
	// The globe.
	vec3 oc = ro - G;
	float b = dot(oc, rd);
	float disc = b * b - (dot(oc, oc) - 1.0);
	if (disc > 0.0) {
		float t = -b - sqrt(disc);
		vec3 e = oc + rd * t;
		if (t > 0.0 && t < best && e.y > -0.77) {
			vec3 inner = inside_at(e, refract(rd, e, 1.0 / 1.2));
			float facing = max(dot(-rd, e), 0.0);
			float fres = 0.03 + 0.55 * pow(1.0 - facing, 4.0);
			vec3 rr = reflect(rd, e);
			col = inner * (1.0 - fres) * (0.7 + 0.3 * smoothstep(0.0, 0.35, facing)) + room_at(rr) * fres * 1.3;
			col += vec3(1.0) * pow(max(dot(rr, normalize(vec3(-0.5, 0.62, -0.6))), 0.0), 150.0) * 0.8;
		}
	}
	col *= 1.0 - 0.3 * dot(p, p);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
