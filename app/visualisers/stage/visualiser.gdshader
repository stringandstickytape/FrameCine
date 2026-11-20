// Stage lights (visualiser.json): an empty stage at a sound check, seen from the floor of the hall, every surface
// and beam found exactly (no marching). Eight moving heads hang from a truss and six stand at the back of the deck
// pointing up, each a part of the spectrum: its beam
// swings on the music's clock (drive), widens and brightens with its part, hangs in the haze (the nearest approach
// of the pixel's ray to the beam's line, stopped where the beam lands) and throws a pool on the boards. A fan of
// lasers tilts over the hall with the high notes. Behind, a wall of LEDs shows the spectrum as mirrored bars over a
// slow plasma, each LED a dot; the glossy deck mirrors it. Speaker stacks stand at the sides, their cones pumping with
// the bass; a microphone stand and two wedges wait at the front. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float sweep = 0.5;
uniform float haze = 0.6;
uniform bool lasers = true;
uniform vec4 light_a : source_color = vec4(1.0, 0.3, 0.55, 1.0);
uniform vec4 light_b : source_color = vec4(0.25, 0.6, 1.0, 1.0);
uniform vec4 laser : source_color = vec4(0.3, 1.0, 0.45, 1.0);

const int HEADS = 8;
const int LIGHTS = 14;
const float DECK = 0.9;
const float WALL_Z = 8.0;
const float TRUSS_Y = 6.7;


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float hash1(vec2 c) {
	uint h = hash_u(uint(int(c.x) + 100000) * 73856093u ^ uint(int(c.y) + 100000) * 19349663u);
	return float(h & 16777215u) / 16777215.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash1(i), hash1(i + vec2(1.0, 0.0)), f.x), mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec3 head_colour(int i) {
	float k = 0.5 + 0.5 * sin(float(i) * 0.9 + drive * 0.06);
	return mix(light_a.rgb, light_b.rgb, k);
}

vec3 head_pos(int i) {
	if (i >= HEADS) {
		return vec3(-5.5 + float(i - HEADS) * 2.2, DECK + 0.25, 6.6);
	}
	return vec3(-6.1 + float(i) * 12.2 / float(HEADS - 1), TRUSS_Y - 0.35, 2.0);
}

// Where head i points: sweeping side to side and out over the hall, neighbours a little apart in time.
vec3 head_dir(int i) {
	float fi = float(i);
	float t = drive * sweep;
	float pan = 0.55 * sin(t * 0.33 + fi * 0.7) + 0.25 * sin(t * 0.19 + fi * 2.1);
	float tilt = -0.45 + 0.75 * sin(t * 0.27 + fi * 0.45);
	if (i >= HEADS) {
		// The ones on the deck: a fan opening and closing, leaning out over the hall.
		float fan = (fi - float(HEADS) - 2.5) * (0.12 + 0.2 * (0.5 + 0.5 * sin(t * 0.21)));
		return normalize(vec3(sin(fan + 0.2 * sin(t * 0.4 + fi)), 1.0, -0.35 + 0.3 * sin(t * 0.17 + fi * 0.6)));
	}
	return normalize(vec3(sin(pan), -1.0, tilt));
}

// The LED wall at (u, v) 0..1: the spectrum as bars from the middle out, over a slow plasma; each LED a dot.
vec3 led_wall(vec2 w) {
	vec2 grid = vec2(96.0, 38.0);
	vec2 cell = (floor(w * grid) + 0.5) / grid;
	vec2 f = fract(w * grid) - 0.5;
	float x = abs(cell.x - 0.5) * 2.0;
	float h = band(0.03 + 0.9 * x) * 0.92;
	float bar = step(cell.y, h);
	vec3 bc = mix(light_a.rgb, light_b.rgb, clamp(cell.y / 0.8, 0.0, 1.0));
	float peak = step(abs(cell.y - h - 0.02), 0.014);
	float plasma = 0.5 + 0.5 * sin(cell.x * 9.0 + drive * 0.3 + 3.0 * sin(cell.y * 5.0 - drive * 0.21));
	vec3 c = mix(light_b.rgb, light_a.rgb, plasma) * 0.2 * (0.5 + 0.5 * plasma);
	c = mix(c, bc * 0.85, bar);
	c += vec3(1.0) * peak * 0.6;
	return c * smoothstep(0.48, 0.3, length(f));
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 uv = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	vec3 ro = vec3(0.6 * sin(drive * 0.04), 1.7, -7.6 + 0.4 * sin(drive * 0.03));
	vec3 rd = normalize(vec3(uv.x - ro.x * 0.02, uv.y + 0.2, 0.95));
	float px_a = 1.0 / size.y;

	// What the ray meets: the LED wall, the deck, its front, the hall's floor, a speaker stack.
	vec3 col = vec3(0.012, 0.012, 0.018);
	float depth = 60.0;
	vec3 n = vec3(0.0);
	int what = 0;
	float tw = (WALL_Z - ro.z) / rd.z;
	vec3 pw = ro + rd * tw;
	if (pw.y > DECK) {
		depth = tw;
		what = abs(pw.x) < 7.2 && pw.y < 6.3 ? 1 : 5;
	}
	if (rd.y < 0.0) {
		float td = (DECK - ro.y) / rd.y;
		vec3 pd = ro + rd * td;
		if (pd.z > 0.0 && pd.z < WALL_Z && td < depth) {
			depth = td;
			what = 2;
		}
		float tf = -ro.y / rd.y;
		vec3 pf = ro + rd * tf;
		if (pf.z <= 0.0 && tf < depth) {
			depth = tf;
			what = 4;
		}
	}
	float tr = -ro.z / rd.z;
	vec3 pr = ro + rd * tr;
	if (pr.y > 0.0 && pr.y < DECK && tr < depth) {
		depth = tr;
		what = 3;
	}
	// Speaker stacks: boxes either side, the front face with three cones.
	for (int s = -1; s <= 1; s += 2) {
		vec3 bc = vec3(float(s) * 6.9, DECK + 1.75, 1.0);
		vec3 bh = vec3(0.85, 1.75, 0.7);
		vec3 m = 1.0 / rd;
		vec3 k = abs(m) * bh;
		vec3 t1 = -m * (ro - bc) - k;
		vec3 t2 = -m * (ro - bc) + k;
		float tn = max(max(t1.x, t1.y), t1.z);
		float tf2 = min(min(t2.x, t2.y), t2.z);
		if (tn < tf2 && tn > 0.0 && tn < depth) {
			depth = tn;
			what = 6;
		}
	}

	vec3 pos = ro + rd * depth;
	float gloss = 0.0;
	if (what == 1) {
		col = led_wall(vec2((pos.x + 7.2) / 14.4, (pos.y - DECK) / (6.3 - DECK)));
	} else if (what == 2) {
		// The deck: black boards, glossy; it mirrors the wall.
		float board = smoothstep(0.0, 0.02, abs(fract(pos.x / 0.3) - 0.5) - 0.47);
		col = vec3(0.025) * (0.7 + 0.3 * vnoise(pos.xz * vec2(3.0, 40.0))) * (1.0 - 0.5 * board);
		n = vec3(0.0, 1.0, 0.0);
		gloss = 0.3;
		vec3 rr = reflect(rd, n);
		float t2 = (WALL_Z - pos.z) / rr.z;
		vec3 p2 = pos + rr * t2;
		if (abs(p2.x) < 7.2 && p2.y < 6.3) {
			float fres = 0.08 + 0.6 * pow(1.0 - max(-rd.y, 0.0), 4.0);
			col += led_wall(vec2((p2.x + 7.2) / 14.4, (p2.y - DECK) / (6.3 - DECK))) * fres * (0.75 + 0.25 * vnoise(pos.xz * vec2(6.0, 60.0)));
		}
	} else if (what == 3) {
		col = vec3(0.02) + vec3(0.03) * step(0.48, abs(fract(pos.x / 1.2) - 0.5));
	} else if (what == 4) {
		col = vec3(0.02) * (0.6 + 0.4 * vnoise(pos.xz * 4.0));
		n = vec3(0.0, 1.0, 0.0);
		gloss = 0.12;
	} else if (what == 6) {
		col = vec3(0.022);
		if (abs(pos.z - 0.3) < 0.01) {
			float sx = pos.x - sign(pos.x) * 6.9;
			float pump = 1.0 + 0.1 * bass;
			for (int k = 0; k < 3; k++) {
				float cy = DECK + 0.65 + float(k) * 1.1;
				float l = length(vec2(sx, pos.y - cy)) / pump;
				col += vec3(0.035) * smoothstep(0.5, 0.47, l) * (0.4 + 0.6 * smoothstep(0.0, 0.45, l));
				col += vec3(0.05) * smoothstep(0.02, 0.0, abs(l - 0.47)) + vec3(0.03) * smoothstep(0.16, 0.13, l);
				col += light_a.rgb * 0.05 * bass * smoothstep(0.5, 0.2, l);
			}
		}
	}

	// The truss and the heads on it, in front of the wall.
	float tt = (2.0 - ro.z) / rd.z;
	vec3 pt = ro + rd * tt;
	if (tt < depth && abs(pt.x) < 7.6) {
		float bar = abs(abs(pt.y - TRUSS_Y) - 0.16) - 0.022;
		float web = abs(fract(pt.x / 0.36) - 0.5 - (pt.y - TRUSS_Y) * 1.3) * 0.36 - 0.012;
		web = max(web, abs(pt.y - TRUSS_Y) - 0.16);
		float tsd = min(bar, web);
		for (int i = 0; i < HEADS; i++) {
			vec3 hp = head_pos(i);
			tsd = min(tsd, max(abs(pt.x - hp.x) - 0.13, abs(pt.y - hp.y - 0.1) - 0.2));
		}
		col = mix(col, vec3(0.03, 0.03, 0.035), smoothstep(tt * px_a, -tt * px_a, tsd));
	}
	// The microphone stand and two wedges at the front of the deck.
	float tm = (1.2 - ro.z) / rd.z;
	vec3 pm = ro + rd * tm;
	if (tm < depth) {
		float stand = max(abs(pm.x) - 0.012, max(DECK - pm.y, pm.y - 2.35));
		stand = min(stand, length(vec2(pm.x - 0.05, pm.y - 2.4) * vec2(0.6, 1.0)) - 0.045);
		stand = min(stand, max(abs(pm.x) - 0.22, abs(pm.y - DECK - 0.02) - 0.02));
		float wx = abs(pm.x) - 1.8;
		float wedge = max(max(abs(wx) - 0.4, DECK - pm.y), pm.y - DECK - 0.32 + 0.3 * abs(wx));
		col = mix(col, vec3(0.03), smoothstep(tm * px_a, -tm * px_a, min(stand, wedge)));
	}

	// The beams: each head's pool on what it lands on, and its light in the haze.
	float smoke = (0.55 + 0.45 * haze) * (0.75 + 0.5 * vnoise(uv * 3.0 + vec2(drive * 0.04, drive * 0.02)));
	for (int i = 0; i < LIGHTS; i++) {
		vec3 bp = head_pos(i);
		vec3 bd = head_dir(i);
		float b = band(i < HEADS ? 0.04 + float(i) / float(HEADS - 1) * 0.86 : 0.1 + float(i - HEADS) * 0.15);
		vec3 hc = head_colour(i) * (0.6 + 0.5 * b);
		float s_end = 9.0;
		if (i < HEADS) {
			s_end = bp.y / -bd.y;
			if (bp.z + bd.z * s_end > 0.0) {
				s_end = (bp.y - DECK) / -bd.y;
			}
			s_end = min(s_end, (WALL_Z - bp.z) / max(bd.z, 0.0001));
		}
		float spread = 0.06 * (0.8 + 0.6 * b);
		// The pool where it lands.
		if (i < HEADS && (what == 2 || what == 4)) {
			vec3 land = bp + bd * s_end;
			float r_end = 0.07 + spread * s_end;
			float d = length(pos.xz - land.xz) / (r_end * 1.25);
			col += hc * exp(-d * d * d * d) * (0.25 + gloss) * (0.8 + 0.2 * vnoise(pos.xz * 9.0));
		}
		vec3 w0 = ro - bp;
		float bb = dot(rd, bd);
		float d0 = dot(rd, w0);
		float e0 = dot(bd, w0);
		float den = max(1.0 - bb * bb, 0.001);
		float u = clamp((e0 - bb * d0) / den, 0.0, s_end);
		float s = max(dot(bp + bd * u - ro, rd), 0.0);
		if (s < depth) {
			float dist = length(ro + rd * s - bp - bd * u);
			float r = 0.07 + spread * u;
			float g = exp(-dist * dist / (r * r)) * 1.1 / (1.0 + 0.3 * u) * min(1.0 / sqrt(den), 3.0);
			col += hc * g * smoke;
		}
		// The lens.
		float lens = length(cross(rd, bp - ro)) / max(dot(bp - ro, rd), 0.1);
		col += hc * (exp(-lens * 900.0) * 1.2 + exp(-lens * 150.0) * 0.25) * step(dot(bp - ro, rd), depth);
	}

	// The lasers: a fan of nine from the top of the wall, tilting over the hall.
	if (lasers) {
		vec3 ls = vec3(0.0, 6.5, WALL_Z - 0.3);
		float a = 0.5 + 0.28 * sin(drive * sweep * 0.31);
		vec3 down = normalize(vec3(0.0, -sin(a), -cos(a)));
		vec3 nl = vec3(0.0, down.z, -down.y);
		float tl = dot(ls - ro, nl) / dot(rd, nl);
		if (tl > 0.0 && tl < depth) {
			vec3 v = ro + rd * tl - ls;
			float along = dot(v, down);
			if (along > 0.0) {
				float th = atan(v.x, along);
				float gap = 0.13 + 0.05 * sin(drive * sweep * 0.23);
				float k = clamp(floor(th / gap + 0.5), -4.0, 4.0);
				float dist = abs(sin(th - k * gap)) * length(v);
				float thick = 0.012 + 0.0015 * tl;
				col += laser.rgb * exp(-dist * dist / (thick * thick)) * (0.25 + 0.75 * treble) * smoke * min(1.0 / max(abs(dot(rd, nl)), 0.15), 5.0) * 0.5;
			}
		}
	}

	col *= 1.0 - 0.3 * pow(length(UV - 0.5) * 1.25, 2.5);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
