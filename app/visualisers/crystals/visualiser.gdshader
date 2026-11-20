// Crystal cave (visualiser.json): a walk through a cave of glowing crystals, ray-marched. Six-sided crystals with
// pointed tips grow from the floor and hang from the roof, leaning each its own way, its height and thickness its
// own, shorter along the path the camera follows on the music's clock (drive). They come in four kinds, each kind a
// quarter of the spectrum (the low notes the first colour, the high notes the last), and each crystal glows from
// inside as loud as its quarter. Their light falls on the rock round them (worked out at the point hit from the
// crystals of the cells about it) and hangs in the air (gathered along the ray, per kind, while it marches, and
// coloured at the end). Facets catch a lamp carried with the camera.
// For speed each crystal keeps inside its own cell of a grid, so a point looks at one cell only; two grids half a
// cell apart on the floor (and one on the roof) hide the grid. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float speed = 0.5;
uniform float glow = 0.6;
uniform float growth = 0.6;
uniform vec4 crystal_low : source_color = vec4(1.0, 0.25, 0.5, 1.0);
uniform vec4 crystal_high : source_color = vec4(0.25, 0.8, 1.0, 1.0);
uniform vec4 rock : source_color = vec4(0.2, 0.18, 0.22, 1.0);

const float CELL = 0.8;


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

vec4 hash4(vec2 c) {
	uint h = hash_u(uint(int(c.x) + 100000) * 73856093u ^ uint(int(c.y) + 100000) * 19349663u);
	uint h2 = h * 2654435761u + 12345u;
	h2 ^= h2 >> 15u;
	return vec4(float(h & 65535u), float(h >> 16u), float(h2 & 65535u), float(h2 >> 16u)) / 65535.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash4(i).x, hash4(i + vec2(1.0, 0.0)).x, f.x), mix(hash4(i + vec2(0.0, 1.0)).x, hash4(i + vec2(1.0, 1.0)).x, f.x), f.y);
}

// The path through the cave: the camera's x at z.
float path_x(float z) {
	return 1.1 * sin(z * 0.23);
}

// The crystal of the cell that p is in, on grid g (0, 1 on the floor; 2 on the roof), q.y up its length from its
// root; off: how far the cell is from the path. Its distance; who: its kind and how far up it p is.
float crystal(vec2 pxz, float y, float g, float off, out vec2 who) {
	vec2 shift = vec2(g * 0.5, g * 0.5 + g * g * 0.13);
	vec2 c = floor(pxz / CELL + shift);
	vec4 h = hash4(c + vec2(g * 31.0, 7.0));
	who = vec2(floor(h.w * 3.999), 0.0);
	if (h.x > (g < 1.5 ? 0.7 : 0.5)) {
		return 9.0;
	}
	vec2 base = (c - shift + 0.36 + 0.28 * h.yz) * CELL;
	float tall = (0.3 + 1.5 * h.z * h.z * growth) * (0.3 + 0.7 * smoothstep(0.3, 1.7, abs(off))) * (g < 1.5 ? 1.0 : 0.8);
	float rad = 0.05 + 0.075 * fract(h.y * 7.0) * (0.5 + 0.5 * tall);
	vec3 q = vec3(pxz.x - base.x, y + 0.12, pxz.y - base.y);
	q.xz -= (h.wx - 0.5) * 0.3 * q.y / (0.5 + tall);
	vec2 a = abs(q.xz);
	float hex = max(a.x * 0.866 + a.y * 0.5, a.y);
	who.y = clamp(q.y / tall, 0.0, 1.0);
	return max(hex - rad * clamp((tall - q.y) / (rad * 2.6), 0.0, 1.0), q.y - tall) * 0.7;
}

// The cave at p: x the distance to rock, y to the nearest crystal; who: that crystal's kind and height.
vec2 map(vec3 p, out vec2 who) {
	float off = p.x - path_x(p.z);
	float fy = p.y - 0.2 * sin(p.x * 0.7) * sin(p.z * 0.6);
	float ry = 3.0 - 0.2 * off * off - p.y;
	// Only the crystals that can reach this height: those of the floor low down, those of the roof high up. In
	// between, the distance to the tallest's tip is near enough.
	vec2 w = vec2(0.0);
	float reach = 0.4 + 1.5 * growth;
	float dc = min(fy - reach, ry - reach * 0.8);
	who = vec2(0.0);
	if (fy < reach + 0.3) {
		dc = crystal(p.xz, fy, 0.0, off, who);
		float d = crystal(p.xz, fy, 1.0, off, w);
		if (d < dc) {
			dc = d;
			who = w;
		}
	} else if (ry < reach * 0.8 + 0.3) {
		dc = crystal(p.xz, ry, 2.0, off, who);
	}
	return vec2(min(fy, ry), dc);
}

vec3 kind_colour(float k) {
	return mix(crystal_low.rgb, crystal_high.rgb, k / 3.0);
}

vec4 one_hot(float k) {
	return vec4(float(k < 0.5), float(k > 0.5 && k < 1.5), float(k > 1.5 && k < 2.5), float(k > 2.5));
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 uv = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float z0 = drive * speed * 0.3;
	vec3 ro = vec3(path_x(z0), 1.2 + 0.05 * sin(z0 * 2.4), z0);
	vec3 ta = vec3(path_x(z0 + 2.5), 1.1 + 0.15 * sin(z0 * 0.3), z0 + 2.5);
	vec3 cw = normalize(ta - ro);
	vec3 cu = normalize(cross(cw, vec3(0.03 * sin(z0 * 0.5), 1.0, 0.0)));
	vec3 cv = cross(cu, cw);
	vec3 rd = normalize(uv.x * cu + uv.y * cv + 1.0 * cw);
	vec4 bands = vec4(band_between(0.02, 0.2), band_between(0.2, 0.45), band_between(0.45, 0.7), band_between(0.7, 0.96));
	vec4 power = 0.3 + 1.3 * bands;

	float tt = 0.05;
	vec4 air = vec4(0.0);
	vec2 who = vec2(0.0);
	float hit = 0.0;
	for (int i = 0; i < 36; i++) {
		vec2 d = map(ro + rd * tt, who);
		air += one_hot(who.x) * exp(-max(d.y, 0.0) * 6.0) * 1.15;
		float dm = min(d.x, d.y);
		if (dm < 0.002 * tt) {
			hit = d.y < d.x ? 2.0 : 1.0;
			break;
		}
		tt += min(dm, 0.32) + 0.006 * tt;
		if (tt > 11.5) {
			break;
		}
	}

	vec3 col = vec3(0.0);
	if (hit > 0.0) {
		vec3 pos = ro + rd * tt;
		vec2 tmp = vec2(0.0);
		float e = 0.002 + 0.001 * tt;
		vec2 m0 = map(pos, tmp);
		vec2 mx = map(pos + vec3(e, 0.0, 0.0), tmp);
		vec2 my = map(pos + vec3(0.0, e, 0.0), tmp);
		vec2 mz = map(pos + vec3(0.0, 0.0, e), tmp);
		vec3 n = normalize(vec3(min(mx.x, mx.y), min(my.x, my.y), min(mz.x, mz.y)) - min(m0.x, m0.y));
		float lamp_l = max(dot(n, -rd), 0.0) / (1.0 + 0.06 * tt * tt);
		if (hit > 1.5) {
			// A crystal: lit from inside, brightest up its length; its facets catch the lamp.
			vec3 kc = kind_colour(who.x);
			float p = dot(power, one_hot(who.x));
			float fres = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
			float facet = 0.55 + 0.45 * abs(dot(n, vec3(0.3, 0.8, 0.5)));
			col = kc * p * (0.45 + 0.75 * who.y) * glow * 1.5 * facet;
			col += mix(kc, vec3(1.0), 0.65) * (fres * (0.2 + 0.5 * p) + pow(lamp_l, 24.0) * 1.2 + lamp_l * 0.2);
		} else {
			// Rock: lit by the crystals of the cells round it, and by the lamp.
			float rn = vnoise(pos.xz * 5.0 + pos.y * 3.0) * 0.6 + vnoise(pos.xz * 17.0 + pos.y * 9.0) * 0.4;
			vec3 alb = rock.rgb * (0.5 + 1.0 * rn);
			vec3 light = vec3(0.9, 0.85, 0.8) * lamp_l * 0.9;
			float roof = step(1.6, pos.y);
			for (int j = -1; j <= 1; j++) {
				for (int i = -1; i <= 1; i++) {
					float g = roof > 0.5 ? 2.0 : 0.0;
					vec2 shift = vec2(g * 0.5, g * 0.5 + g * g * 0.13);
					vec2 c = floor(pos.xz / CELL + shift) + vec2(float(i), float(j));
					vec4 h = hash4(c + vec2(g * 31.0, 7.0));
					if (h.x > (g < 1.5 ? 0.7 : 0.5)) {
						continue;
					}
					vec2 base = (c - shift + 0.36 + 0.28 * h.yz) * CELL;
					vec3 lp = vec3(base.x, pos.y + (roof > 0.5 ? -1.0 : 1.0) * (0.15 + 0.5 * h.z * h.z * growth), base.y);
					vec3 to_l = lp - pos;
					float k = floor(h.w * 3.999);
					light += kind_colour(k) * dot(power, one_hot(k)) * glow * max(dot(n, normalize(to_l)), 0.0) * 0.5 / (dot(to_l, to_l) + 0.1);
				}
			}
			col = alb * light;
			col += rock.rgb * pow(lamp_l, 10.0) * step(0.62, rn);
		}
		col = mix(col, rock.rgb * 0.1, 1.0 - exp(-0.11 * tt));
	}
	// The glow in the air, each kind with its quarter of the spectrum.
	for (int k = 0; k < 4; k++) {
		vec4 oh = one_hot(float(k));
		col += kind_colour(float(k)) * dot(air, oh) * dot(power, oh) * glow * 0.045;
	}

	col *= 1.0 - 0.35 * pow(length(UV - 0.5) * 1.25, 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
