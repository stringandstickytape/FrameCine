// Planet (visualiser.json): a ringed gas giant in space, ray traced: the sphere, the ring plane and three moons, with
// the planet's shadow on the rings, the rings' and the moons' shadows on the planet, and a thin lit atmosphere at the
// edge. The cloud bands flow in zonal winds (each latitude its own way, as on the real ones); the sound sets how
// turbulent they are, low notes at the equator and high notes at the poles. The rings are a spectrum: low notes
// light the inner edge, high notes the outer. A storm turns in the south; on a beat, lightning on the night side;
// with the high notes, aurora round the poles. Everything moves on the music's clock (drive).
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float storms = 0.5;
uniform float speed = 0.5;
uniform float ring_glow = 0.6;
uniform bool show_rings = true;
uniform vec4 zone : source_color = vec4(0.92, 0.84, 0.68, 1.0);
uniform vec4 belt : source_color = vec4(0.6, 0.36, 0.22, 1.0);
uniform vec4 spot : source_color = vec4(0.83, 0.35, 0.2, 1.0);
uniform vec4 ice : source_color = vec4(0.86, 0.8, 0.7, 1.0);

const float TILT = 0.36;
const float ROLL = -0.3;
const float R_IN = 1.3;
const float R_OUT = 2.35;


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float h3(vec3 c) {
	uvec3 u = uvec3(ivec3(c) + ivec3(100000));
	return float(hash_u(u.x * 73856093u ^ u.y * 19349663u ^ u.z * 83492791u) & 65535u) / 65535.0;
}

vec3 hash3(vec2 cell, float salt) {
	uint h = hash_u(uint(int(cell.x) + 100000) * 73856093u ^ uint(int(cell.y) + 100000) * 19349663u
			^ uint(int(salt)) * 83492791u);
	uint h2 = hash_u(h);
	uint h3u = hash_u(h2);
	return vec3(float(h & 65535u), float(h2 & 65535u), float(h3u & 65535u)) / 65535.0;
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(h3(vec3(i, 0.0, 0.0)), h3(vec3(i + 1.0, 0.0, 0.0)), f);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h3(i);
	float b = h3(i + vec3(1.0, 0.0, 0.0));
	float c = h3(i + vec3(0.0, 1.0, 0.0));
	float d = h3(i + vec3(1.0, 1.0, 0.0));
	float e = h3(i + vec3(0.0, 0.0, 1.0));
	float g = h3(i + vec3(1.0, 0.0, 1.0));
	float h = h3(i + vec3(0.0, 1.0, 1.0));
	float k = h3(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(a, b, f.x), mix(c, d, f.x), f.y), mix(mix(e, g, f.x), mix(h, k, f.x), f.y), f.z);
}

float fbm3(vec3 p, int octaves) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		if (i >= octaves) {
			break;
		}
		s += a * noise3(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

float wrap_a(float a) {
	return mod(a + PI, TAU) - PI;
}

vec3 rot_y(vec3 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * v.x - s * v.z, v.y, s * v.x + c * v.z);
}

// World (camera looks along +z, y up) to the planet's frame: its axis is y, its rings lie in y = 0.
vec3 to_planet(vec3 v) {
	float cr = cos(ROLL);
	float sr = sin(ROLL);
	v = vec3(cr * v.x - sr * v.y, sr * v.x + cr * v.y, v.z);
	float ct = cos(TILT);
	float st = sin(TILT);
	return vec3(v.x, ct * v.y - st * v.z, st * v.y + ct * v.z);
}

// The nearest hit of a ray with a sphere, or -1.
float sphere(vec3 ro, vec3 rd, vec3 c, float r) {
	vec3 oc = ro - c;
	float b = dot(oc, rd);
	float h = b * b - dot(oc, oc) + r * r;
	return h < 0.0 ? -1.0 : -b - sqrt(h);
}

// A moon: centre (planet frame) and radius.
vec4 moon(int i) {
	float R = i == 0 ? 2.75 : i == 1 ? 3.3 : 4.2;
	float r = i == 0 ? 0.07 : i == 1 ? 0.12 : 0.05;
	float rate = i == 0 ? 0.22 : i == 1 ? 0.14 : 0.09;
	float a = drive * speed * rate + float(i) * 2.1;
	return vec4(cos(a) * R, sin(a) * R * 0.03 * float(i), sin(a) * R, r);
}

// How much of the light the rings stop at radius r (0..1): faint inner ring, dense middle, a wide gap, the outer ring
// with a narrow gap, all finely grooved.
float ring_density(float r) {
	float x = (r - R_IN) / (R_OUT - R_IN);
	if (x <= 0.0 || x >= 1.0) {
		return 0.0;
	}
	float d = 0.22 + 0.73 * smoothstep(0.2, 0.24, x) - 0.89 * smoothstep(0.59, 0.61, x)
			+ 0.56 * smoothstep(0.645, 0.665, x);
	d *= 1.0 - 0.85 * exp(-pow((x - 0.87) / 0.006, 2.0));
	d *= smoothstep(0.0, 0.03, x) * smoothstep(1.0, 0.985, x);
	d *= 0.62 + 0.38 * noise1(r * 90.0);
	d *= 0.8 + 0.2 * noise1(r * 31.0 + 5.0);
	return clamp(d, 0.0, 1.0);
}

// The cloud bands at q (planet frame, turned by the spin and by this latitude's wind).
vec3 bands_at(vec3 q, float lat, float turb, float salt) {
	vec3 P = vec3(q.x * 2.2, q.y * 12.0, q.z * 2.2) + salt;
	float w = fbm3(P, 3);
	float lat2 = lat + (w - 0.47) * 0.24 * turb;
	float d = fbm3(P * vec3(1.6, 2.2, 1.6) + vec3(w * 3.0), 4);
	float s = sin(lat2 * 15.0 + 1.6 * sin(lat2 * 5.0 + 1.0)) + 0.35 * sin(lat2 * 37.0);
	float zb = smoothstep(-0.4, 0.4, s);
	vec3 col = mix(belt.rgb, zone.rgb, zb);
	col *= 0.74 + 0.5 * d;
	// Darker, redder knots in the belts; pale streaks in the zones.
	col = mix(col, col * vec3(1.05, 0.82, 0.7), smoothstep(0.5, 0.72, d) * (1.0 - zb));
	col = mix(col, vec3(0.97, 0.95, 0.9), smoothstep(0.62, 0.8, d) * zb * 0.5);
	return col;
}

// The planet's colour at normal n (planet frame), before light.
vec3 surface(vec3 n, out float lat_out, out vec2 ll) {
	vec3 q = rot_y(n, drive * speed * 0.05);
	float lat = asin(clamp(q.y, -1.0, 1.0));
	float lon = atan(q.z, q.x);
	lat_out = lat;
	ll = vec2(lon, lat);
	float x = abs(lat) / (PI * 0.5);
	float b = band(0.04 + x * 0.8);
	float turb = 0.2 + storms * (0.4 + 1.6 * b);
	// Zonal winds, each latitude its own speed and way. Flowing noise forever would shear it into streaks, so two
	// copies take turns: each flows for a while and fades out as the other fades in.
	float wind = sin(lat * 6.5) * 0.7 + 0.3;
	float ph = drive * speed * 0.035;
	float f1 = fract(ph);
	float f2 = fract(ph + 0.5);
	float w1 = 1.0 - abs(2.0 * f1 - 1.0);
	vec3 c1 = bands_at(rot_y(q, wind * f1 * 1.3), lat, turb, 0.0);
	vec3 c2 = bands_at(rot_y(q, wind * f2 * 1.3), lat, turb, 31.0);
	vec3 col = mix(c2, c1, w1);
	// The great storm: a turning spiral in an oval, with a pale rim.
	float lat0 = -0.36;
	float lon0 = drive * speed * 0.012;
	vec2 d = vec2(wrap_a(lon - lon0) * cos(lat0), lat - lat0) / vec2(0.2, 0.085);
	float r = length(d);
	if (r < 2.0) {
		float sw = sin(atan(d.y, d.x) * 2.0 - r * 4.5 + drive * 0.9) * 0.5 + 0.5;
		vec3 sc = mix(spot.rgb * 0.7, spot.rgb * 1.15 + 0.06, sw * smoothstep(0.0, 0.7, r));
		sc *= 1.0 + 0.25 * band(0.15);
		col = mix(col, sc, smoothstep(1.1, 0.75, r));
		col = mix(col, zone.rgb * 1.08, smoothstep(0.14, 0.0, abs(r - 1.05)) * 0.55);
	}
	// A string of small white ovals further south.
	for (int i = 0; i < 4; i++) {
		float lo = float(i) * 1.6 + drive * speed * 0.02 * (1.0 + 0.2 * float(i));
		vec2 e = vec2(wrap_a(lon - lo) * cos(-0.62), lat + 0.62) / vec2(0.06, 0.035);
		col = mix(col, vec3(0.96, 0.94, 0.9), smoothstep(1.0, 0.5, length(e)) * 0.85);
	}
	return col;
}

vec3 background(vec2 p) {
	vec3 col = vec3(0.012, 0.014, 0.03);
	// Faint nebula.
	vec3 np = vec3(p * 1.4 + vec2(drive * 0.004, 0.0), 3.7);
	float n1 = fbm3(np, 3);
	float n2 = fbm3(np * 1.7 + vec3(4.0), 3);
	col += vec3(0.3, 0.12, 0.42) * smoothstep(0.42, 0.8, n1) * 0.22;
	col += vec3(0.05, 0.22, 0.32) * smoothstep(0.48, 0.85, n2) * 0.18;
	// Stars: a fine layer and a sparse bright one.
	for (int l = 0; l < 2; l++) {
		float cs = l == 0 ? 0.017 : 0.05;
		vec2 c = floor(p / cs);
		vec3 hh = hash3(c, float(l));
		if (hh.z < (l == 0 ? 0.4 : 0.3)) {
			vec2 sp = (c + 0.2 + 0.6 * hh.xy) * cs;
			float dpx = length(p - sp) * size.y;
			vec3 h2 = hash3(c, float(l) + 7.0);
			float br = l == 0 ? 0.15 + 0.5 * h2.x * h2.x : 0.5 + 0.9 * h2.x;
			br *= 0.8 + 0.2 * sin(vis_time * (1.5 + 4.0 * h2.y) + h2.z * 6.28) * (0.4 + treble);
			vec3 tint = mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.85, 1.0), h2.z);
			float r2 = l == 0 ? 0.8 : 1.6;
			col += tint * br * exp(-dpx * dpx / r2);
			if (l == 1) {
				vec2 dd = abs(p - sp) * size.y;
				col += tint * br * 0.25 * (exp(-dd.x * 0.6 - dd.y * dd.y * 2.0) + exp(-dd.y * 0.6 - dd.x * dd.x * 2.0));
			}
		}
	}
	// The sun's glare from off the left edge.
	col += vec3(1.0, 0.85, 0.6) * 0.1 * exp(-length(p - vec2(-1.25, 0.42)) * 1.8);
	return col;
}

void fragment() {
	vec2 p = (UV - 0.5) * size / size.y;
	p.y = -p.y;
	vec2 s = p - vec2(0.24, -0.02);
	vec3 ro = to_planet(vec3(0.0, 0.0, -7.4));
	vec3 rd = to_planet(normalize(vec3(s, 2.0)));
	vec3 L = to_planet(normalize(vec3(-1.0, 0.32, -0.6)));

	vec3 col = background(p);
	// The atmosphere seen past the edge: a thin glow, lit on the day side.
	float bb = dot(ro, rd);
	vec3 closest = ro - rd * bb;
	float dmin = length(closest);
	vec3 haze = mix(zone.rgb, vec3(0.62, 0.76, 1.0), 0.55);
	if (dmin > 1.0) {
		float day = smoothstep(-0.25, 0.4, dot(closest / dmin, L));
		col += haze * exp(-(dmin - 1.0) * 28.0) * day * 0.75;
	}

	float t_near = 1e9;
	// The planet.
	float t_pl = sphere(ro, rd, vec3(0.0), 1.0);
	if (t_pl > 0.0) {
		t_near = t_pl;
		vec3 n = ro + rd * t_pl;
		float lat = 0.0;
		vec2 ll = vec2(0.0);
		vec3 base = surface(n, lat, ll);
		float ndl = dot(n, L);
		float lit = smoothstep(-0.12, 0.25, ndl) * mix(0.5, 1.08, clamp(ndl, 0.0, 1.0));
		// Shadows: the rings', and the moons' (small black dots crossing the clouds).
		float shade = 1.0;
		if (show_rings && abs(L.y) > 0.001) {
			float tr = -n.y / L.y;
			if (tr > 0.0) {
				vec3 hp = n + L * tr;
				shade *= 1.0 - 0.85 * ring_density(length(hp.xz));
			}
		}
		for (int i = 0; i < 3; i++) {
			vec4 m = moon(i);
			vec3 oc = n - m.xyz;
			float b = dot(oc, L);
			if (b < 0.0) {
				float miss = length(oc - L * b) / m.w;
				shade *= mix(0.08, 1.0, smoothstep(0.85, 1.1, miss));
			}
		}
		float mu = clamp(dot(n, -rd), 0.0, 1.0);
		base *= mix(0.55, 1.0, sqrt(mu));
		vec3 c = base * lit * shade;
		c = mix(c, haze * lit * 0.9, pow(1.0 - mu, 4.0) * 0.55);
		// The night side: a little light from the rings, lightning on a beat, aurora at the poles.
		float night = 1.0 - smoothstep(-0.1, 0.15, ndl);
		c += base * 0.025;
		vec2 lc = floor(ll / vec2(0.22, 0.1));
		vec3 hl = hash3(lc, beats);
		if (hl.z < 0.03 + 0.06 * storms) {
			vec2 lp = (lc + 0.25 + 0.5 * hl.xy) * vec2(0.22, 0.1);
			vec2 dl = vec2(wrap_a(ll.x - lp.x) * cos(ll.y), ll.y - lp.y) / 0.025;
			c += vec3(0.6, 0.72, 1.0) * beat * exp(-dot(dl, dl) * 0.35) * night * 0.5;
		}
		float aur = exp(-pow((abs(lat) - 1.25) / 0.035, 2.0)) * (0.55 + 0.45 * sin(ll.x * 7.0 + drive * 1.3));
		c += vec3(0.25, 1.0, 0.65) * aur * (0.1 + 0.9 * treble) * (0.25 + 0.75 * night) * 0.6;
		col = c;
	}
	// The moons.
	for (int i = 0; i < 3; i++) {
		vec4 m = moon(i);
		float t = sphere(ro, rd, m.xyz, m.w);
		if (t > 0.0 && t < t_near) {
			t_near = t;
			vec3 P = ro + rd * t;
			vec3 n = (P - m.xyz) / m.w;
			float cr = noise3(n * 5.0 + float(i) * 7.0);
			vec3 mc = mix(vec3(0.55, 0.52, 0.5), vec3(0.75, 0.68, 0.58), float(i) * 0.5) * (0.65 + 0.55 * cr);
			float ml = clamp(dot(n, L), 0.0, 1.0);
			// The planet's shadow (an eclipse) on the moon.
			float b = dot(P, L);
			if (b < 0.0) {
				ml *= smoothstep(0.97, 1.03, length(P - L * b));
			}
			col = mc * (0.03 + ml);
		}
	}
	// The rings, in front of whatever is behind them.
	if (show_rings && abs(rd.y) > 0.0001) {
		float tr = -ro.y / rd.y;
		if (tr > 0.0 && tr < t_near) {
			vec3 hp = ro + rd * tr;
			float rr = length(hp.xz);
			float dens = ring_density(rr);
			if (dens > 0.0) {
				float x = (rr - R_IN) / (R_OUT - R_IN);
				float b = dot(hp, L);
				float sh = b < 0.0 ? smoothstep(0.97, 1.03, length(hp - L * b)) : 1.0;
				vec3 rc = ice.rgb * mix(0.75, 1.12, noise1(rr * 13.0)) * mix(vec3(1.0), vec3(1.05, 0.95, 0.85),
						noise1(rr * 5.0 + 3.0));
				rc *= 0.5 + ring_glow * 1.5 * band(x);
				rc *= 0.08 + 0.95 * sh;
				col = mix(col, rc, dens * 0.92);
			}
		}
	}
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
