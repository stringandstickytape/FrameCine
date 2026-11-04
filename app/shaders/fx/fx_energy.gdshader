// The effect library's energy effects (scripts/effects/catalogue/energy.gd, docs/effects.md): light that seems to come
// from the surface itself. Compiled once per effect with FX_<NAME> defined.
//
// - plasma: slow flowing plasma in two colours: 3D value noise bent by another tap of it (domain warp), soft bright
//   veins, brighter toward the silhouette. Draws its own surface.
// - aurora: curtains of light on a night: vertical rays (the fractal texture stretched tall) along a fold that wanders
//   sideways, a soft foot that wavers, fading upward; the first colour at the foot, the second above. Draws its own
//   surface.
// - nebula: deep space: clouds of glow in two colours with darker dust lanes (three taps of 3D value noise, each
//   bending the next) and a few small stars, still, twinkling slowly. Draws its own surface.
// - force_field: an additive hex grid, both sides, brighter at the rim; rows of cells brighten in turn, a slow ripple
//   moving up the field.
// - circuit: traces over the surface's own colour, dimmed to a board: rows and columns cut into segments with a pad at
//   each end, and soft pulses running along some of them.
// - neon: a neon tube: a near-white core where the surface faces you, its colour deepening toward the rim and lifting
//   again at the very edge (the glow); an optional faint hum.
// The analytic patterns (hex cells, traces) are drawn in the part's own space on three planes, chosen by the normal,
// so a box's faces are exact and a sphere's seams are short cross-fades; a pixel draws only the planes it shows. Lines
// are antialiased over a pixel and fade to their average when too fine (energy_line, as fx_line); the 3D noise drops
// its finest tap by its derivative (energy_fine3, as fx_fine).
//
// Photosensitivity: every pattern moves slowly, and the clock moves the noise through its third axis or along the
// rays, never as a hard edge. At speed 1 a pixel sees about a third of a pass of the plasma or the clouds a second and
// less of the aurora's rays (full contrast: well under the 1.2 passes a second the ceiling allows); the hex ripple is
// a sine at the rate (at most 1.5 Hz) within the swing (fx_swing); the stars twinkle with fx_wander at 0.4 Hz within
// theirs; a circuit pulse is a wide soft bump (about half a second at speed 1) riding on a trace that keeps its own
// light; neon's hum is fx_wander at 1.5 Hz within at most 0.2. tests/test_effects.gd measures each at its fastest
// options.
shader_type spatial;
render_mode unshaded, shadows_disabled, specular_disabled;
#if defined(FX_FORCE_FIELD)
// Additive, both sides: the far side of the field shows through the near one, as light would.
render_mode blend_add, cull_disabled, depth_draw_never;
#else
render_mode cull_back;
#endif

#include "res://shaders/fx/fx_common.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	local_pos = VERTEX;
	local_normal = NORMAL;
}

// Four random numbers 0..1 for a whole-numbered cell, in one tap: fx_value_noise's texels read at their middles.
vec4 energy_rnd4(vec2 cell) {
	return textureLod(fx_value_noise, (cell + 0.5) / 64.0, 0.0);
}

// How much each of the part's three planes (zy, xz, xy) shows, by the normal: sharp, so the seams stay short, and 0
// under 1 %, so a pixel draws only the one or two planes it shows (the patterns are skipped where their weight is 0;
// their derivatives are taken before, outside the branches).
vec3 energy_planes(vec3 n) {
	vec3 w = pow(abs(normalize(n)), vec3(16.0));
	w /= max(w.x + w.y + w.z, 1e-4);
	w *= step(0.01, w);
	return w / max(w.x + w.y + w.z, 1e-4);
}

// The pixel's size on each plane (zy, xz, xy), in p's units: the largest step of its two coordinates.
vec3 energy_plane_px(vec3 p) {
	vec3 fw = fwidth(p);
	return vec3(max(fw.z, fw.y), max(fw.x, fw.z), max(fw.x, fw.y));
}

// fx_line with the pixel's size given (w, in d's units), for patterns drawn in branches (no derivatives there) and
// distances that jump (where a circuit segment's slot ends: its own fwidth would draw a faint line along the jump).
float energy_line(float d, float half_width, float w) {
	w = max(w, 1e-5);
	float l = 1.0 - smoothstep(half_width - w, half_width + w, d);
	return mix(l, half_width * 2.0, smoothstep(half_width * 1.5, half_width * 4.0, w));
}

// A rotation (orthonormal) between noise taps, so the value noise's lattice does not line up from one tap to the next
// (its blobs would look square along the axes).
const mat3 ENERGY_TURN = mat3(vec3(0.0, 0.8, 0.6), vec3(-0.8, 0.36, -0.48), vec3(-0.6, -0.48, 0.64));

// fx_fine for a 3D coordinate: 0 fine to draw .. 1 far finer than a pixel.
float energy_fine3(vec3 x) {
	vec3 w = fwidth(x);
	return smoothstep(0.35, 0.9, max(w.x, max(w.y, w.z)));
}

#if defined(FX_FORCE_FIELD)
// The hexagon around p (p in cell widths; pointed top and bottom): xy the offset from its middle, zw its middle.
vec4 energy_hex(vec2 p) {
	const vec2 S = vec2(1.0, 1.7320508);
	vec4 c = floor(vec4(p, p - vec2(0.5, 1.0)) / S.xyxy) + 0.5;
	vec4 h = vec4(p - c.xy * S, p - (c.zw + 0.5) * S);
	return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, c.xy * S) : vec4(h.zw, (c.zw + 0.5) * S);
}

// One plane of the field: x its light (edge line and a faint fill brightening toward the edge), y the ripple's wave
// for its cell (-1..1). px: the pixel's size in cells. has_up: the plane's second axis is the part's height (the
// cell's row); the plane facing up has none, so its cells take up_px, the pixel's height.
vec2 energy_field(vec2 p, float px, float up_px, bool has_up, float t) {
	vec4 h = energy_hex(p);
	float d = max(dot(abs(h.xy), vec2(0.5, 0.8660254)), abs(h.x));
	float line = energy_line(0.5 - d, 0.035, px);
	float fill = 0.05 + 0.12 * smoothstep(0.15, 0.5, d);
	vec4 r = energy_rnd4(floor(vec2(h.z * 2.0, h.w / 0.8660254) + 0.5));
	float row = has_up ? h.w : up_px;
	float wave = sin(FX_TAU * (fx_rate_hz() * t - row / 7.0) + r.x * 1.6);
	return vec2(line + fill * (0.7 + 0.6 * r.y), wave);
}
#endif

#if defined(FX_CIRCUIT)
// One plane of the board, q in trace spacings (px: the pixel's size in them): rows of traces at whole q.y, columns at
// whole q.x + 0.5, each cut into segments of up to five spacings, most of them drawn, with a pad at each end. x: the
// traces, y: their pulses (0..1, soft bumps running along some segments), both antialiased.
vec2 energy_traces(vec2 q, float px, float t, float v) {
	vec2 out_ = vec2(0.0);
	for (int axis = 0; axis < 2; axis++) {
		// Rows, then columns as rows of the turned plane.
		vec2 r = axis == 0 ? q : vec2(q.y, q.x + 0.5);
		float j = floor(r.y + 0.5);
		float u = r.x / 5.0 + fract(j * 0.618034 + 0.5 * float(axis));
		float k = floor(u);
		vec4 rnd = energy_rnd4(vec2(k, j * 2.0 + float(axis)));
		float a = 0.04 + 0.35 * rnd.b * rnd.b;
		float b = 0.96 - 0.35 * rnd.g * rnd.g;
		float x = (fract(u) - a) * 5.0;
		float len = (b - a) * 5.0;
		float dy = r.y - j;
		vec2 to_line = vec2(x - clamp(x, 0.0, len), dy);
		float drawn = step(axis == 0 ? 0.4 : 0.62, rnd.r);
		float trace = energy_line(length(to_line), 0.05, px);
		// A pad at each end: a ring round a darker middle, as a via.
		float pad = min(length(vec2(x, dy)), length(vec2(x - len, dy)));
		trace = max(trace, energy_line(pad, 0.15, px) * (1.0 - 0.65 * energy_line(pad, 0.06, px))) * drawn;
		// A pulse every (len + 6) spacings of travel, on about half the segments, each its own way; it starts and
		// ends 3 spacings off the segment and shows only on it (a trace too fine to draw is spread over its whole
		// row, so the pulse would show past the ends, where it jumps back to the start).
		float dir = rnd.a < 0.5 ? 1.0 : -1.0;
		float pos = fract(t * v / (len + 6.0) + rnd.a * 3.7) * (len + 6.0) - 3.0;
		float along = (dir > 0.0 ? x : len - x) - pos;
		float on = smoothstep(-0.5, 0.0, x) * smoothstep(len + 0.5, len, x);
		float pulse = exp(-along * along / 0.81) * on * step(0.5, fract(rnd.a * 7.3 + rnd.r));
		out_.x = max(out_.x, trace);
		out_.y = max(out_.y, trace * pulse);
	}
	return out_;
}
#endif

void fragment() {
	FxSurface s = fx_surface(UV, world_pos, world_normal, local_pos, local_normal, FRONT_FACING,
			CAMERA_POSITION_WORLD);
	vec3 col = s.lit;
	float rim = fx_rim(s.facing, 1.0);
#if defined(FX_PLASMA)
	// 3D value noise, its position bent by another tap (domain warp); the whole moves slowly through the noise's
	// third axis, so it flows and changes shape in place. f mixes the deep colour into the bright one.
	float t = FX_TIME;
	vec3 p = local_pos / max(fx_scale, 0.05) + fx_seed * 7.0;
	float z = 0.1 * fx_speed01() * t;
	vec2 w = fx_noise3x2(p * 0.7 + vec3(0.0, 0.0, z * 0.5)) - 0.5;
	vec3 q = ENERGY_TURN * p * 1.4 + vec3(w * 2.6, z);
	vec2 n = fx_noise3x2(q);
	vec2 d = fx_noise3x2(q * 2.3 + vec3(n.yx * 1.2, -z * 0.5) + 5.3);
	float detail = mix(d.x, 0.5, energy_fine3(q * 2.3));
	float f = smoothstep(0.3, 0.8, n.x * 0.7 + detail * 0.3);
	// Soft bright veins where the second noise crosses its middle, stronger in the bright flows.
	float vein = pow(1.0 - abs(2.0 * n.y - 1.0), 4.0) * (0.3 + 0.7 * f);
	vec3 c = mix(fx_color2 * 0.7, fx_color, f * f) + mix(fx_color, vec3(1.0), 0.25) * vein * 0.4;
	c *= mix(1.0, 0.5 + 1.4 * rim * rim, clamp(fx_param, 0.0, 1.0));
	col = c * fx_strength + fx_dither(FRAGCOORD.xy);
#elif defined(FX_AURORA)
	// h across the surface and y up, in curtain heights; the curtain's foot half a height under the part's middle.
	float t = FX_TIME;
	float hgt = max(fx_scale, 0.1);
	float h = (local_pos.x + 0.71 * local_pos.z) / hgt + fx_seed * 11.0;
	float drift = 0.012 * fx_speed01() * t;
	vec2 bend = fx_noise3x2(vec3(h * 0.8 - drift * 2.0, 0.5, drift * 1.5)) - 0.5;
	// The foot wavers up and down along the curtain; the fold bends the rays sideways.
	float y = local_pos.y / hgt + 0.5 + bend.y * 0.4;
	float fold = h + bend.x * 1.2;
	float rays = fx_fbm2(vec2(fold * 0.9 - drift, 0.13 + y * 0.012)).r;
	// The rays grow streakier upward, as they thin out.
	rays = smoothstep(0.35, 0.8, rays);
	rays = 0.12 + 0.88 * mix(rays, rays * rays * rays, clamp(y, 0.0, 1.0));
	float folds = 0.04 + 0.96 * smoothstep(0.3, 0.75, fx_noise3(vec3(fold * 2.2 + 3.0, 1.7, drift * 4.0)));
	float profile = smoothstep(-0.06, 0.12, y) * (0.1 + 0.9 * exp(-3.0 * max(y, 0.0)))
			* smoothstep(0.95, 0.35, y);
	vec3 c = mix(fx_color, fx_color2, smoothstep(0.05, 0.7, y));
	vec3 night = mix(vec3(0.004, 0.01, 0.016), vec3(0.008, 0.006, 0.022), clamp(y, 0.0, 1.0));
	col = night + c * fx_strength * rays * folds * profile * 1.4 + fx_dither(FRAGCOORD.xy);
#elif defined(FX_NEBULA)
	// Three taps of 3D value noise, each bending the next: glow in the first colour, glow in the second, dust that
	// darkens both. The whole drifts slowly; the stars stay.
	float t = FX_TIME;
	vec3 p0 = local_pos / max(fx_scale, 0.1);
	vec3 p = p0 + fx_seed * 5.0 + vec3(0.7, 0.25, 0.45) * (0.02 * fx_speed01() * t);
	vec2 a = fx_noise3x2(p * 1.3);
	vec3 q = ENERGY_TURN * p * 2.6 + vec3(a - 0.5, 0.0) * 1.6;
	vec2 b = fx_noise3x2(q);
	vec2 c3 = fx_noise3x2(ENERGY_TURN * q * 2.3 + vec3(b.yx - 0.5, 0.0) * 0.9 + 3.1);
	vec2 fine = mix(c3, vec2(0.5), energy_fine3(q * 2.3));
	float g1 = smoothstep(0.25, 0.85, a.x * 0.5 + b.x * 0.3 + fine.x * 0.2);
	float g2 = smoothstep(0.3, 0.85, a.y * 0.45 + b.y * 0.35 + fine.y * 0.2);
	float dust = smoothstep(0.45, 0.8, b.y * 0.5 + fine.x * 0.5);
	vec3 c = vec3(0.005, 0.006, 0.016) + fx_color * (g1 * g1 * 0.8 + pow(g1, 4.0) * 0.7)
			+ fx_color2 * (g2 * g2 * 0.6 + pow(g2, 4.0) * 0.3);
	c += vec3(0.3) * pow(g1 * g2, 3.0);
	c *= 1.0 - 0.6 * dust;
	// Stars: one per cell of a 15 cm grid on the plane the surface faces most, at a random point where the cell's
	// number says so; at least a pixel wide (smaller ones dimmed instead), twinkling slowly within the swing.
	vec3 an = abs(local_normal);
	vec2 sp = (an.x > max(an.y, an.z) ? local_pos.zy : (an.y > an.z ? local_pos.xz : local_pos.xy)) / 0.15;
	vec2 cell = floor(sp);
	vec4 r = energy_rnd4(cell + 101.0);
	vec2 at = cell + 0.2 + 0.6 * r.gb;
	float rad = max(0.035, length(fwidth(sp)) * 0.9);
	float star = smoothstep(rad, 0.0, length(sp - at)) * pow(0.035 / rad, 2.0);
	star *= step(1.0 - clamp(fx_param, 0.0, 1.0) * 0.35, r.r) * (0.35 + 0.65 * r.a);
	star *= fx_swing(fx_wander(t, 0.4, r.b), fx_depth);
	c += vec3(star) * mix(vec3(1.0), fx_color2 * 0.5 + 0.6, 0.3);
	col = c * fx_strength + fx_dither(FRAGCOORD.xy);
#elif defined(FX_FORCE_FIELD)
	// Hex cells on the part's three planes, blended by the normal; brighter at the rim; each cell's light swings
	// with the ripple's wave for its row (fx_swing: the rate and swing under the ceiling).
	float t = FX_TIME;
	vec3 p = local_pos / max(fx_scale, 0.02);
	vec3 w = energy_planes(local_normal);
	vec3 px = energy_plane_px(p);
	vec2 f = vec2(0.0);
	if (w.x > 0.0) {
		f += energy_field(p.zy, px.x, 0.0, true, t) * w.x;
	}
	if (w.y > 0.0) {
		f += energy_field(p.xz + 0.37, px.y, p.y, false, t) * w.y;
	}
	if (w.z > 0.0) {
		f += energy_field(p.xy + 0.61, px.z, 0.0, true, t) * w.z;
	}
	float light = f.x * mix(0.25, 1.0, pow(rim, 1.5)) * fx_swing(f.y, fx_depth);
	col = fx_color * fx_strength * light;
#elif defined(FX_CIRCUIT)
	// Traces on the part's three planes, blended by the normal, glowing faintly over the dimmed surface; pulses add
	// light along them as wide soft bumps, 1.8 spacings a second at speed 1, so a pixel under one rises and falls over
	// about half a second, never past the ceiling.
	float t = FX_TIME;
	vec3 q = local_pos / max(fx_scale, 0.01);
	vec3 w = energy_planes(local_normal);
	float v = 1.8 * fx_speed01();
	vec3 px = energy_plane_px(q);
	vec2 tr = vec2(0.0);
	if (w.x > 0.0) {
		tr += energy_traces(q.zy, px.x, t, v) * w.x;
	}
	if (w.y > 0.0) {
		tr += energy_traces(q.xz + 0.29, px.y, t, v) * w.y;
	}
	if (w.z > 0.0) {
		tr += energy_traces(q.xy + 0.53, px.z, t, v) * w.z;
	}
	float pulses = tr.y * clamp(fx_param, 0.0, 1.0);
	col = s.lit * 0.35 + (fx_color2 * tr.x * 0.55 + fx_color * pulses * 0.55) * fx_strength;
#elif defined(FX_NEON)
	// A tube of light: near white where it faces you, its colour deepening toward the rim and softening at the very
	// edge (the glow spreading); core sets how wide the white is.
	float hot = pow(s.facing, mix(30.0, 5.0, clamp(fx_param, 0.0, 1.0)));
	vec3 c = fx_color * (0.3 + 0.7 * sqrt(s.facing));
	c = mix(c, mix(fx_color, vec3(1.0), 0.85), hot);
	c += fx_color * 0.35 * pow(1.0 - s.facing, 3.0);
	float hum = fx_swing(fx_wander(FX_TIME, 1.5, fx_seed), min(fx_depth, 0.2));
	col = c * fx_strength * hum;
#endif
	ALBEDO = fx_print(col, UV);
#if defined(FX_FORCE_FIELD)
	ALPHA = 1.0;
#endif
}
