// Music box (visualiser.json): the works of a music box in its open wooden case, every surface found exactly (a
// cylinder, planes, boxes). A brass cylinder set with steel pins turns on the music's clock (drive); in front of it
// lies the steel comb, twenty-four teeth, the long ones the low notes. Each tooth is a part of the spectrum: it
// glows towards its tip as its part sounds, and the pins in its column glow as they come round to pluck it.
// Under them a brass bedplate, engine-turned, with the shadows of the works; round them the lined case; at the far
// end of the cylinder its toothed wheel. Behind, the lid stands open with a mirror inside it: a ray that meets the
// glass is sent back and the whole scene found again, so the works show from the other side.
// No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float speed = 0.5;
uniform float shine = 0.6;
uniform vec4 brass : source_color = vec4(0.85, 0.62, 0.25, 1.0);
uniform vec4 steel : source_color = vec4(0.62, 0.68, 0.75, 1.0);
uniform vec4 wood : source_color = vec4(0.36, 0.18, 0.08, 1.0);
uniform vec4 lining : source_color = vec4(0.45, 0.05, 0.1, 1.0);
uniform vec4 tone : source_color = vec4(1.0, 0.75, 0.35, 1.0);

const vec3 KEY = vec3(-0.47, 0.78, -0.41);
const float TEETH = 24.0;

float hash1(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x), mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The room as polished metal sees it: dark below, warm above, a window high on the left.
vec3 env_at(vec3 d) {
	float up = clamp(d.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 c = mix(vec3(0.05, 0.035, 0.03), vec3(0.5, 0.42, 0.32), up * up);
	c += vec3(1.0, 0.95, 0.85) * smoothstep(0.8, 0.97, dot(d, KEY)) * 1.5;
	return c;
}

vec3 wood_at(vec2 q, float shade) {
	float g = vnoise(vec2(q.x * 1.5, q.y * 22.0)) * 0.6 + vnoise(vec2(q.x * 4.0 + 7.0, q.y * 60.0)) * 0.4;
	return wood.rgb * (0.5 + 0.8 * g) * shade;
}

// The cylinder's skin at q: brass, and the pins.
vec3 cyl_shade(vec3 q, vec3 rd, float rot) {
	vec3 n = vec3(0.0, q.y, q.z);
	float th0 = atan(q.z, q.y);
	float th = th0 + rot;
	vec2 g = vec2((q.x + 3.0) / 6.0 * TEETH, th / TAU * 44.0);
	vec2 id = floor(g);
	vec2 fm = (fract(g) - 0.5) * vec2(0.25, 0.143);
	id.y = mod(id.y, 44.0);
	float has = step(0.7, hash1(id));
	float pin = has * smoothstep(0.045, 0.03, length(fm));
	float pin_sh = has * smoothstep(0.08, 0.03, length(fm - vec2(0.025, -0.02)));
	vec3 base = brass.rgb * (0.16 + 0.95 * env_at(reflect(rd, n)));
	base *= 0.88 + 0.12 * vnoise(vec2(q.x * 3.0, th * 20.0));
	base *= 1.0 - 0.45 * pin_sh;
	float b = band(0.04 + 0.9 * id.x / (TEETH - 1.0));
	vec3 pc = steel.rgb * (0.45 + 0.9 * smoothstep(0.03, 0.0, length(fm - vec2(-0.012, 0.01))));
	float reach = smoothstep(0.6, 0.0, abs(th0 + PI * 0.5));
	pc += tone.rgb * b * reach * shine * 1.6;
	base += tone.rgb * b * reach * shine * 0.12;
	return mix(base, pc, pin);
}

// What a ray that has come in through the open top of the case meets.
vec3 inside_at(vec3 ro, vec3 rd, float rot) {
	vec3 inv = 1.0 / rd;
	vec3 tf = max((vec3(-4.2, -1.25, -4.0) - ro) * inv, (vec3(4.2, 1.0, 2.4) - ro) * inv);
	float best = min(tf.x, min(tf.y, tf.z));
	vec3 q = ro + rd * best;
	vec3 col;
	if (tf.y < tf.x && tf.y < tf.z) {
		// The bedplate: engine-turned brass, with the shadows of the cylinder and the comb.
		float turned = 0.5 + 0.5 * sin(length(fract(q.xz * 2.2) - 0.5) * 38.0);
		col = brass.rgb * (0.28 + 0.2 * turned) * (0.45 + 0.9 * env_at(reflect(rd, vec3(0.0, 1.0, 0.0))));
		float sc = max(abs(q.z - 0.35) - 1.0, abs(q.x - 0.2) - 3.1);
		col *= 0.35 + 0.65 * smoothstep(0.0, 0.6, sc);
		float cm = max(abs(q.x - 0.3) - 3.0, abs(q.z + 1.9) - 1.25);
		col *= 0.45 + 0.55 * smoothstep(0.0, 0.3, cm);
		vec2 sq = abs(q.xz - vec2(0.0, -0.8)) - vec2(3.75, 2.75);
		float sd = length(sq) - 0.14;
		vec3 screw = steel.rgb * (0.5 + 0.4 * step(0.02, abs(sq.x + sq.y)));
		col = mix(col, screw, smoothstep(0.01, -0.01, sd));
		// The glow of the sounding comb on the plate.
		col += tone.rgb * brass.rgb * shine * 0.25 * level * exp(-(q.z + 1.2) * (q.z + 1.2) * 1.5) * step(abs(q.x), 3.2);
	} else {
		// The lined walls.
		float face = tf.x < tf.z ? 0.55 + 0.25 * sign(rd.x) : (rd.z > 0.0 ? 0.8 : 0.35);
		float nap = vnoise(q.xy * 30.0 + q.z * 30.0);
		col = lining.rgb * face * (0.3 + 0.5 * smoothstep(-1.25, 1.0, q.y)) * (0.8 + 0.4 * nap);
	}

	// The cylinder.
	float a = dot(rd.yz, rd.yz);
	float b = dot(ro.yz, rd.yz);
	float c = dot(ro.yz, ro.yz) - 1.0;
	float disc = b * b - a * c;
	if (disc > 0.0) {
		float t = (-b - sqrt(disc)) / a;
		vec3 h = ro + rd * t;
		if (t > 0.0 && t < best && abs(h.x) < 3.0) {
			best = t;
			col = cyl_shade(h, rd, rot);
		}
	}
	// Its ends: a plain cap on the left, the toothed wheel on the right; and the bearings that carry it.
	for (int s = 0; s < 2; s++) {
		float px = s == 0 ? -3.0 : 3.0;
		float t = (px - ro.x) / rd.x;
		vec3 h = ro + rd * t;
		float r = length(h.yz);
		float ang = atan(h.z, h.y) + rot;
		float rim = s == 0 ? 1.0 : 1.24 + 0.07 * smoothstep(-0.3, 0.3, sin(ang * 40.0));
		if (t > 0.0 && t < best && r < rim) {
			best = t;
			float spokes = smoothstep(0.1, 0.2, abs(sin(ang * 3.0))) * step(0.3, r) * step(r, 0.85);
			vec3 m = brass.rgb * (0.3 + 0.35 * (1.0 - spokes * 0.6)) * (0.6 + 0.5 * vnoise(vec2(r * 30.0, 1.0)));
			m = mix(m, steel.rgb * 0.8, step(r, 0.14));
			col = m * (0.5 + 0.3 * abs(rd.x));
		}
	}

	// The comb.
	if (rd.y < 0.0) {
		float t = (0.06 - ro.y) / rd.y;
		vec3 h = ro + rd * t;
		if (t > 0.0 && t < best && abs(h.x) < 3.0 && h.z > -3.4 && h.z < -1.03) {
			float gx = (h.x + 3.0) / 6.0 * TEETH;
			float k = floor(gx);
			float fx = fract(gx);
			float root = mix(-3.05, -1.75, k / (TEETH - 1.0));
			float gap = 0.08 + 0.2 * smoothstep(-1.16, -1.03, h.z);
			bool slit = (fx < gap || fx > 1.0 - gap) && h.z > root;
			if (!slit) {
				best = t;
				float nb = band(0.04 + 0.9 * k / (TEETH - 1.0));
				float free = step(root, h.z);
				vec3 n = normalize(vec3((fx - 0.5) * 0.3 * free, 1.0, 0.0));
				vec3 m = steel.rgb * (0.1 + 0.9 * env_at(reflect(rd, n)));
				m *= 0.92 + 0.08 * vnoise(vec2(h.x * 8.0, h.z * 1.5));
				float along = clamp((h.z - root) / (-1.03 - root), 0.0, 1.0) * free;
				m += tone.rgb * nb * shine * along * 1.7;
				vec2 sq = vec2((fract(h.x / 1.2 + 0.5) - 0.5) * 1.2, h.z + 3.24);
				float sd = length(sq) - 0.09;
				m = mix(m, steel.rgb * (0.25 + 0.3 * step(0.015, abs(sq.x - sq.y))), smoothstep(0.01, -0.01, sd));
				col = m;
			}
		}
	}
	return col;
}

// What a ray meets; glass is 1 when it is the mirror in the lid.
vec3 scene(vec3 ro, vec3 rd, float rot, out float glass) {
	glass = 0.0;
	float best = 1e9;
	vec3 col = env_at(rd) * 0.1;
	if (rd.y < 0.0) {
		// The table.
		float t = (-1.6 - ro.y) / rd.y;
		vec3 q = ro + rd * t;
		best = t;
		float d = length(max(vec2(abs(q.x) - 4.5, abs(q.z + 0.8) - 3.5), 0.0));
		col = wood_at(q.zx * 0.3 + 3.0, 0.45) * (0.3 + 0.7 * smoothstep(0.0, 2.5, d)) * exp(-t * 0.03);
	}
	if (rd.z > 0.0) {
		// The lid, and the mirror in it.
		float t = (2.7 - ro.z) / rd.z;
		vec3 q = ro + rd * t;
		if (t > 0.0 && t < best && abs(q.x) < 4.5 && q.y > 1.0 && q.y < 5.6) {
			best = t;
			float inset = min(4.5 - abs(q.x), min(q.y - 1.0, 5.6 - q.y));
			if (inset > 0.4) {
				glass = 1.0;
			}
			col = wood_at(q.xy * 0.5, 0.7);
			col = mix(col, brass.rgb * 0.8, smoothstep(0.03, 0.01, abs(inset - 0.32)));
		}
	}
	vec3 inv = 1.0 / rd;
	vec3 t0 = (vec3(-4.5, -1.6, -4.3) - ro) * inv;
	vec3 t1 = (vec3(4.5, 1.0, 2.7) - ro) * inv;
	vec3 tn = min(t0, t1);
	vec3 tf = max(t0, t1);
	float te = max(tn.x, max(tn.y, tn.z));
	float tx = min(tf.x, min(tf.y, tf.z));
	if (te < tx && te > 0.0 && te < best) {
		vec3 q = ro + rd * te;
		glass = 0.0;
		if (tn.y > tn.x && tn.y > tn.z) {
			if (abs(q.x) < 4.2 && q.z > -4.0 && q.z < 2.4) {
				col = inside_at(q, rd, rot);
			} else {
				float inset = min(4.5 - abs(q.x), min(q.z + 4.3, 2.7 - q.z));
				col = wood_at(q.xz * 0.5 + 1.0, 0.95);
				col = mix(col, brass.rgb * 0.9, smoothstep(0.025, 0.008, abs(inset - 0.15)));
			}
		} else if (tn.z > tn.x) {
			float inset = min(4.5 - abs(q.x), min(q.y + 1.6, 1.0 - q.y));
			col = wood_at(q.xy * 0.5 + 5.0, 0.6);
			col = mix(col, brass.rgb * 0.7, smoothstep(0.03, 0.01, abs(inset - 0.25)));
			vec2 lk = abs(q.xy - vec2(0.0, 0.5)) - vec2(0.22, 0.3);
			col = mix(col, brass.rgb * (0.7 - 0.5 * step(length(q.xy - vec2(0.0, 0.45)), 0.06)), step(max(lk.x, lk.y), 0.0));
		} else {
			col = wood_at(q.zy * 0.5 + 9.0, 0.4);
		}
	}
	return col;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float rot = drive * 0.14 * speed;
	vec3 ro = vec3(0.5 + 1.3 * sin(drive * 0.017), 6.4 + 0.3 * sin(drive * 0.011), -8.6);
	vec3 fw = normalize(vec3(0.0, 0.7, -0.5) - ro);
	vec3 rt = normalize(cross(vec3(0.0, 1.0, 0.0), fw));
	vec3 up = cross(fw, rt);
	vec3 rd = normalize(fw * 1.3 + rt * p.x + up * p.y);
	float glass;
	vec3 col = scene(ro, rd, rot, glass);
	if (glass > 0.5) {
		vec3 q = ro + rd * ((2.7 - ro.z) / rd.z);
		float g2;
		col = scene(q, vec3(rd.xy, -rd.z), rot, g2) * vec3(0.8, 0.83, 0.8) + 0.012;
	}
	col *= 1.0 - 0.35 * dot(p, p);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
