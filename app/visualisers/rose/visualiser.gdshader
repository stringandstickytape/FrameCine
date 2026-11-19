// Rose window (visualiser.json): a gothic rose window seen from inside, the sun behind it. Stone tracery (dark
// against the light) holds a central six-lobed oculus, twelve lancets, twelve small eyes and twenty-four quatrefoil
// roundels, each glazed in small pieces of coloured glass between lead lines. Every lancet and roundel is a part of
// the spectrum going round the wheel, and glows with it; the oculus glows with the bass and swells on a beat. The sun
// moves slowly behind, so the light sweeps across the glass, and coloured shafts fall into the room through dust that
// glints with the high notes.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float glow = 0.7;
uniform float beams = 0.6;
uniform float pieces = 0.5;
uniform float sun_speed = 0.5;
uniform vec4 glass_a : source_color = vec4(0.1, 0.24, 0.8, 1.0);
uniform vec4 glass_b : source_color = vec4(0.78, 0.07, 0.13, 1.0);
uniform vec4 glass_c : source_color = vec4(0.96, 0.7, 0.18, 1.0);
uniform vec4 glass_d : source_color = vec4(0.12, 0.58, 0.32, 1.0);
uniform vec4 stone : source_color = vec4(0.5, 0.45, 0.39, 1.0);

const float RADIUS = 0.45;
// The lancets: a wedge from X0 to XM, then a pointed (equilateral) arch.
const float X0 = 0.24;
const float XM = 0.44;
const float K = 0.205;


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

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash3(i, 3.0).x, hash3(i + vec2(1.0, 0.0), 3.0).x, f.x),
			mix(hash3(i + vec2(0.0, 1.0), 3.0).x, hash3(i + vec2(1.0, 1.0), 3.0).x, f.x), f.y);
}

// q in a sector's own frame (x out from the middle along the sector's axis).
vec2 sector(vec2 u, float a, float count, float shift, out float index) {
	float st = TAU / count;
	float i = floor((a - shift) / st + 0.5);
	index = mod(i, count);
	float sa = a - shift - i * st;
	return length(u) * vec2(cos(sa), sin(sa));
}

float lancet(vec2 q) {
	float wm = K * XM;
	float c = inversesqrt(1.0 + K * K);
	float wedge = max(max((abs(q.y) - K * q.x) * c, X0 - q.x), q.x - XM);
	float arch = max(max(length(q - vec2(XM, wm)) - 2.0 * wm, length(q - vec2(XM, -wm)) - 2.0 * wm), XM - q.x);
	float d = min(wedge, arch);
	// A stone ring in the head, glazed inside.
	float ring = abs(length(q - vec2(XM + 0.07, 0.0)) - 0.04) - 0.007;
	return max(d, -ring);
}

float quatrefoil(vec2 q) {
	float d = length(q) - 0.042;
	for (int i = 0; i < 4; i++) {
		float a = float(i) * PI * 0.5 + PI * 0.25;
		d = min(d, length(q - 0.036 * vec2(cos(a), sin(a))) - 0.04);
	}
	return d;
}

// The glazing at u (window units, 1 = the outer edge): x the signed distance to glass (negative inside), y which
// opening (0 oculus, 1 lancet, 2 roundel, 3 eye), z its number, w its place in the spectrum.
vec4 window(vec2 u) {
	float r = length(u);
	float a = atan(u.y, u.x);
	vec4 best = vec4(r - (0.14 + 0.028 * abs(cos(a * 3.0))), 0.0, 0.0, 0.04);
	float i = 0.0;
	vec2 q = sector(u, a, 12.0, -PI * 0.5, i);
	float d = lancet(q);
	if (d < best.x) {
		best = vec4(d, 1.0, i, 0.06 + i / 12.0 * 0.88);
	}
	float j = 0.0;
	vec2 q2 = sector(u, a, 24.0, -PI * 0.5, j) - vec2(0.785, 0.0);
	d = quatrefoil(q2);
	if (d < best.x) {
		best = vec4(d, 2.0, j, 0.1 + j / 24.0 * 0.85);
	}
	float k = 0.0;
	vec2 q3 = sector(u, a, 12.0, -PI * 0.5 + PI / 12.0, k) - vec2(0.625, 0.0);
	d = length(q3) - 0.04;
	if (d < best.x) {
		best = vec4(d, 3.0, k, 0.5);
	}
	return best;
}

// Where the sun is behind the window, and how strongly it lights u through the glass.
float sunlight(vec2 u) {
	float sa = drive * sun_speed * 0.06 + 2.2;
	vec2 sd = vec2(cos(sa), sin(sa));
	return 0.55 + 0.75 * smoothstep(-0.9, 1.0, dot(u, sd));
}

float music(vec4 w) {
	if (w.y < 0.5) {
		return 0.65 + 0.7 * bass + 0.3 * beat;
	}
	return 0.4 + 1.15 * band(w.w);
}

// The glass's own colour for an opening (no pieces, no lead): what the light shafts carry.
vec3 opening_colour(vec4 w, vec2 u) {
	if (w.y < 0.5) {
		return length(u) < 0.07 ? glass_c.rgb : (mod(floor(atan(u.y, u.x) / TAU * 6.0 + 6.0), 2.0) < 1.0
				? glass_a.rgb : glass_b.rgb);
	}
	if (w.y < 1.5) {
		return mod(w.z, 2.0) < 1.0 ? glass_a.rgb : glass_b.rgb;
	}
	if (w.y < 2.5) {
		return mod(w.z, 2.0) < 1.0 ? glass_d.rgb : glass_b.rgb;
	}
	return mix(glass_c.rgb, vec3(1.0), 0.35);
}

// Light coming through the window at u, blurred (for the shafts): each ring of openings as a soft band of its colours,
// as much light as the glass in it lets through.
vec3 through(vec2 u) {
	float r = length(u);
	if (r > 0.9) {
		return vec3(0.0);
	}
	float a = atan(u.y, u.x);
	vec3 c = (glass_a.rgb + glass_b.rgb + glass_c.rgb) * 0.3 * (0.65 + 0.7 * bass) * smoothstep(0.19, 0.14, r);
	float i = 0.0;
	vec2 q = sector(u, a, 12.0, -PI * 0.5, i);
	float lw = smoothstep(0.22, 0.27, r) * smoothstep(0.62, 0.55, r) * smoothstep(0.75, 0.35, abs(q.y) / (r * 0.26));
	c += (mod(i, 2.0) < 1.0 ? glass_a.rgb : glass_b.rgb) * lw * 0.8 * (0.4 + 1.15 * band(0.06 + i / 12.0 * 0.88));
	float j = 0.0;
	vec2 q2 = sector(u, a, 24.0, -PI * 0.5, j);
	float rw = smoothstep(0.69, 0.74, r) * smoothstep(0.87, 0.82, r) * 0.5;
	c += (mod(j, 2.0) < 1.0 ? glass_d.rgb : glass_b.rgb) * rw * (0.4 + 1.15 * band(0.1 + j / 24.0 * 0.85));
	return c * sunlight(u);
}

// Lead between the pieces: the distance to the nearest border of a cell (Voronoi), and the cell.
vec3 voronoi(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash3(n + g, 1.0).xy;
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 o = hash3(n + g, 1.0).xy;
			vec2 r = g + o - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return vec3(md, n + mg);
}

vec3 wall(vec2 p) {
	// Ashlar: courses of blocks, each a little different, with mortar between.
	float row = floor(p.y / 0.075);
	vec3 hr = hash3(vec2(row, 0.0), 5.0);
	float bw = 0.16 + 0.08 * hr.x;
	float x = p.x / bw + hr.y;
	float col_i = floor(x);
	vec3 hb = hash3(vec2(col_i, row), 6.0);
	vec2 f = vec2(fract(x) * bw, fract(p.y / 0.075) * 0.075);
	float edge = min(min(f.x, bw - f.x), min(f.y, 0.075 - f.y)) * size.y;
	float mortar = smoothstep(1.0, 2.5, edge);
	vec3 c = stone.rgb * (0.13 + 0.05 * hb.x) * (0.85 + 0.3 * noise2(p * 40.0));
	return c * mix(0.45, 1.0, mortar);
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = UV * vec2(aspect, 1.0);
	vec2 centre = vec2(aspect * 0.63, 0.47);
	vec2 u = (p - centre) / RADIUS;
	float r = length(u);
	float px = 1.0 / (RADIUS * size.y);
	vec3 col;
	if (r < 0.93) {
		vec4 w = window(u);
		vec3 base = opening_colour(w, u);
		// A gold border round each lancet, green in its head's ring.
		if (w.y > 0.5 && w.y < 1.5) {
			if (w.x > -0.016) {
				base = glass_c.rgb;
			}
			float i = 0.0;
			vec2 q = sector(u, atan(u.y, u.x), 12.0, -PI * 0.5, i);
			if (length(q - vec2(XM + 0.07, 0.0)) < 0.033) {
				base = glass_d.rgb;
			}
		}
		if (w.y > 1.5 && w.y < 2.5) {
			float j = 0.0;
			vec2 q2 = sector(u, atan(u.y, u.x), 24.0, -PI * 0.5, j) - vec2(0.785, 0.0);
			if (length(q2) < 0.026) {
				base = glass_c.rgb;
			}
		}
		// The pieces: each its own shade, a few another colour; mottled, with a seed or two.
		vec3 v = voronoi(u / (0.045 / (0.5 + pieces)));
		vec3 hp = hash3(v.yz, 2.0);
		if (hp.x < 0.1) {
			base = mix(base, glass_c.rgb, 0.7);
		} else if (hp.x < 0.16) {
			base = mix(base, glass_d.rgb, 0.6);
		}
		base *= 0.72 + 0.45 * hp.y;
		base *= 0.85 + 0.3 * noise2(u * 60.0 + hp.z * 10.0);
		vec3 light = base * sunlight(u) * music(w) * (0.4 + glow);
		// Lead: round each piece and along the stone.
		float lead = max(smoothstep(2.2 * px, 1.0 * px, v.x * 0.045 / (0.5 + pieces)),
				smoothstep(-3.0 * px, -1.5 * px, w.x));
		vec3 lead_col = vec3(0.035, 0.035, 0.04) + light * 0.08;
		vec3 glass = mix(light, lead_col, lead);
		// Stone tracery, dark against the light: rounder (lighter) in the middle of a bar, lit at the edges by the
		// glass beside it.
		float d = w.x;
		vec3 st = stone.rgb * (0.1 + 0.12 * smoothstep(0.0, 0.025, d));
		st *= 0.85 + 0.3 * noise2(u * 80.0);
		st += opening_colour(w, u) * music(w) * exp(-d * 45.0) * 0.22;
		col = mix(st, glass, smoothstep(px, -px, w.x));
	} else if (r < 1.02) {
		// The frame: mouldings round the wheel, scalloped on the inside.
		float a = atan(u.y, u.x);
		float inner = 0.93 + 0.012 * (1.0 - abs(sin(a * 24.0)));
		float m = 0.5 + 0.5 * sin((r - 0.93) * 230.0);
		vec3 st = stone.rgb * (0.08 + 0.1 * m) * (0.85 + 0.3 * noise2(u * 80.0));
		col = mix(st, wall(p), smoothstep(1.015, 1.02, r));
		col *= smoothstep(inner - px, inner + px, r);
	} else {
		col = wall(p);
		col += vec3(1.0, 0.85, 0.65) * 0.05 * exp(-(r - 1.0) * 2.0);
	}
	// Shafts of coloured light falling into the room through dust, and the dust itself.
	// They spread from the window towards us, out from a point near the middle that leans with the sun: a pixel out
	// along a line from there gets the light of the lancet and the roundel on that line, so no marching is needed.
	// Fine streaks along the rays drift slowly, as light in dust does.
	float sa = drive * sun_speed * 0.06 + 2.2;
	vec2 src = centre + vec2(cos(sa), sin(sa)) * RADIUS * 0.2;
	vec2 ds = p - src;
	vec2 ray = ds / max(length(ds), 1e-5);
	vec3 shaft = through(ray * 0.42) + through(ray * 0.78) + (glass_a.rgb + glass_c.rgb) * 0.12 * (0.6 + bass);
	float streak = 0.45 + 0.9 * pow(noise2(ray * 9.0 + vec2(drive * 0.02, 0.0)), 2.0);
	float haze = 0.6 + 0.6 * noise2(p * 5.0 + vec2(drive * 0.05, -drive * 0.08));
	shaft *= streak * haze * smoothstep(0.9, 1.08, r) * exp(-max(r - 1.0, 0.0) * 1.6);
	col += shaft * beams * 0.85;
	vec2 dc = floor(p / 0.03);
	vec3 hd = hash3(dc, 9.0);
	vec2 mote = (dc + 0.5 + 0.4 * vec2(sin(drive * 0.3 + hd.x * 6.0), cos(drive * 0.23 + hd.y * 6.0))) * 0.03;
	float md = length(p - mote) * size.y;
	col += shaft * beams * hd.z * exp(-md * md * 0.5) * (0.6 + 1.6 * treble) * 1.5;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
