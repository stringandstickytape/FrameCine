// The effect library's stylised looks (scripts/effects/catalogue/stylised.gd, docs/effects.md): pencil hatching,
// comic halftone, retro pixels, a glowing wireframe, stained glass and a two-colour tone. Compiled once per effect
// with FX_<NAME> defined. All are still (none reads the clock) and opaque.
//
// Shading comes from a fixed key light above and in front, as the toon effect's (room_effect.gdshader FX_TOON), at
// the room's brightness. Patterns are fixed to the part: drawn in its own space (metres, on the three planes of its
// own axes) or in its UV, never on the screen, so they stay put when the head moves. Every line and dot is
// antialiased over a pixel with fwidth, and a pattern too fine for the pixels fades to its average tone instead of
// shimmering (there is no MSAA on the headset).
shader_type spatial;
render_mode unshaded, shadows_disabled, specular_disabled, cull_back;

#include "res://shaders/fx/fx_common.gdshaderinc"

#if defined(FX_PIXEL)
// The light's steps (and the tones of a one-colour palette).
uniform int px_levels = 4;
#endif

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

// The key light (FX_TOON's): 0 facing away .. 1 facing it, half-Lambert so the shadow side keeps some shape.
const vec3 ST_KEY = vec3(-0.45, 0.75, 0.5);

float st_key(vec3 n) {
	return clamp(0.5 + 0.5 * dot(n, normalize(ST_KEY)), 0.0, 1.0);
}

// The room's brightness as one number (FX_TOON's), so a stylised part dims with the room without losing its look.
float st_level(vec3 light) {
	return clamp(dot(light, vec3(0.333)) * 1.4, 0.55, 1.25);
}

// Perceived lightness of a linear colour, 0..1.
float st_lightness(vec3 c) {
	return sqrt(clamp(dot(c, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0));
}

// Weights of the three planes of the part's own axes (yz, xz, xy) for a pattern drawn on all three: the plane the
// surface faces most, blended over a narrow band only (two line patterns averaged lose half their contrast).
vec3 st_planes(vec3 n) {
	vec3 w = pow(abs(n), vec3(24.0));
	return w / max(w.x + w.y + w.z, 1e-4);
}

#if defined(FX_HATCHING)
// One layer of pencil strokes of the given half width (in cycles) at x = k + 0.5, antialiased over a pixel, each
// stroke a little lighter or darker as a hand presses differently; when fewer than four pixels a cycle, faded to the
// share of the surface they cover. fwidth is taken of x itself, which is continuous, so the wrap of fract makes no
// seam.
float st_strokes(float x, float half_width, float layer) {
	float w = max(fwidth(x), 1e-5);
	float press = mix(0.7, 1.0, fx_hash(vec3(floor(x), layer, fx_seed * 31.0)));
	float l = (1.0 - smoothstep(half_width - w, half_width + w, abs(fract(x) - 0.5))) * press;
	// A stroke thinner than a pixel is fainter, not a pixel wide (and none at all at width 0).
	l *= clamp(2.0 * half_width / w, 0.0, 1.0);
	return mix(l, 2.0 * half_width * 0.85, smoothstep(0.25, 0.6, w));
}

// Three layers of strokes on one plane: diagonal, the other diagonal, then across; each layer appears as the tone
// passes its threshold and thickens as it gets darker. Returns the share of ink.
float st_hatch(vec2 q, float dark, float wobble) {
	float h1 = 0.2 * clamp((dark - 0.12) / 0.25, 0.0, 1.0);
	float h2 = 0.17 * clamp((dark - 0.38) / 0.22, 0.0, 1.0);
	float h3 = 0.14 * clamp((dark - 0.62) / 0.2, 0.0, 1.0);
	float l1 = st_strokes(dot(q, vec2(0.7071, 0.7071)) + wobble, h1, 1.0);
	float l2 = st_strokes(dot(q, vec2(0.7071, -0.7071)) - wobble * 0.7 + 0.31, h2, 2.0);
	float l3 = st_strokes(q.y * 0.9 + 0.17 + wobble * 0.5, h3, 3.0);
	return 1.0 - (1.0 - l1) * (1.0 - l2) * (1.0 - l3);
}
#elif defined(FX_HALFTONE)
// Round dots on a grid turned 45 degrees, sized so they cover `cover` of the plane; antialiased, and the flat tone
// they average to when fewer than about four pixels a dot.
float st_dots(vec2 q, float cover) {
	vec2 g = vec2(q.x + q.y, q.y - q.x) * 0.7071;
	vec2 fw = fwidth(g);
	float w = max(max(fw.x, fw.y), 1e-5);
	float d = length(fract(g) - 0.5);
	float r = sqrt(clamp(cover, 0.0, 1.0) / 3.14159) * 1.13;
	float dotted = (1.0 - smoothstep(r - w * 0.7, r + w * 0.7, d)) * clamp(2.0 * r / w, 0.0, 1.0);
	return mix(dotted, clamp(cover, 0.0, 1.0), smoothstep(0.25, 0.6, w));
}
#elif defined(FX_PIXEL)
// The nearest of a small palette (in perceptual space). 0: each channel to 16 levels (a 12-bit colour; the light's
// steps make the look, and a coarser snap would turn browns orange and olive); 1: eight colours; 2: green tones;
// 3: amber tones (by lightness, in the light's steps). No dither: a checker of two tones reads as noise.
vec3 st_palette(vec3 c, int mode, float levels) {
	vec3 p = sqrt(clamp(c, 0.0, 1.0));
	if (mode == 0) {
		vec3 q = floor(p * 15.0 + 0.5) / 15.0;
		return q * q;
	}
	if (mode == 1) {
		const vec3 EIGHT[8] = {vec3(0.10, 0.09, 0.14), vec3(0.93, 0.90, 0.82), vec3(0.72, 0.27, 0.24),
				vec3(0.92, 0.66, 0.30), vec3(0.42, 0.66, 0.33), vec3(0.24, 0.42, 0.68), vec3(0.47, 0.33, 0.57),
				vec3(0.52, 0.42, 0.33)};
		vec3 best = EIGHT[0];
		float bd = 1e9;
		for (int i = 0; i < 8; i++) {
			vec3 e = EIGHT[i] - p;
			float d = dot(e, e);
			if (d < bd) {
				bd = d;
				best = EIGHT[i];
			}
		}
		return best * best;
	}
	float l = clamp(floor(dot(p, vec3(0.3, 0.59, 0.11)) * (levels - 1.0) + 0.5) / (levels - 1.0), 0.0, 1.0);
	vec3 dark = mode == 2 ? vec3(0.06, 0.16, 0.09) : vec3(0.16, 0.07, 0.02);
	vec3 bright = mode == 2 ? vec3(0.68, 0.86, 0.42) : vec3(1.0, 0.78, 0.38);
	vec3 q = mix(dark, bright, l);
	return q * q;
}
#elif defined(FX_STAINED_GLASS)
// fx_fbm.png's cell points (scripts/effects/make_noise.gd, seed 911: 8 x 8, one in each square), so the nearest
// point here is the cell whose borders the texture's .a draws. Keep in step if that texture is ever made anew.
const vec2 ST_CELLS[64] = {vec2(0.1786, 0.3304), vec2(0.5217, 0.2949), vec2(0.4129, 0.4996), vec2(0.4800, 0.2254),
		vec2(0.5427, 0.4586), vec2(0.5239, 0.4739), vec2(0.8846, 0.2165), vec2(0.3286, 0.3347), vec2(0.1798, 0.2218),
		vec2(0.2319, 0.2254), vec2(0.6761, 0.2703), vec2(0.3719, 0.5523), vec2(0.1797, 0.4038), vec2(0.5989, 0.4103),
		vec2(0.6500, 0.3796), vec2(0.6753, 0.8833), vec2(0.1541, 0.5029), vec2(0.2266, 0.5437), vec2(0.2108, 0.2976),
		vec2(0.4619, 0.5530), vec2(0.2051, 0.7315), vec2(0.5957, 0.2714), vec2(0.1088, 0.6749), vec2(0.6371, 0.1150),
		vec2(0.4171, 0.4796), vec2(0.8690, 0.2805), vec2(0.6070, 0.7515), vec2(0.5255, 0.7154), vec2(0.4662, 0.5829),
		vec2(0.2951, 0.8893), vec2(0.7971, 0.5204), vec2(0.5527, 0.8005), vec2(0.5647, 0.6599), vec2(0.3816, 0.7222),
		vec2(0.3410, 0.8213), vec2(0.4117, 0.6851), vec2(0.2175, 0.1617), vec2(0.1671, 0.1911), vec2(0.1324, 0.8541),
		vec2(0.5919, 0.4530), vec2(0.5881, 0.5583), vec2(0.5924, 0.7868), vec2(0.1762, 0.7407), vec2(0.5892, 0.3153),
		vec2(0.8843, 0.5234), vec2(0.4234, 0.6672), vec2(0.3250, 0.7911), vec2(0.3546, 0.7020), vec2(0.6782, 0.5846),
		vec2(0.1452, 0.8380), vec2(0.2079, 0.7062), vec2(0.7593, 0.3353), vec2(0.7531, 0.7900), vec2(0.2175, 0.2264),
		vec2(0.4870, 0.8460), vec2(0.5329, 0.5694), vec2(0.6821, 0.1107), vec2(0.7201, 0.3986), vec2(0.7263, 0.5687),
		vec2(0.3242, 0.1146), vec2(0.5716, 0.1461), vec2(0.3760, 0.5943), vec2(0.5013, 0.4216), vec2(0.7154, 0.3412)};

// The index (0..63) of the cell p (in cells, 8 to the texture's repeat) lies in: its nearest point, looked for in
// the 2 x 2 squares around the grid corner nearest p (the 3 x 3 the texture used costs twice as much; the rare miss
// is next to a border, under the lead).
int st_cell(vec2 p) {
	vec2 c = floor(p - 0.5);
	int best = 0;
	float bd = 1e9;
	for (int oy = 0; oy <= 1; oy++) {
		for (int ox = 0; ox <= 1; ox++) {
			vec2 q = c + vec2(float(ox), float(oy));
			vec2 m = mod(q, 8.0);
			int k = int(m.y) * 8 + int(m.x);
			vec2 e = q + ST_CELLS[k] - p;
			float d = dot(e, e);
			if (d < bd) {
				bd = d;
				best = k;
			}
		}
	}
	return best;
}

// A pane's colour from a small palette by its cell and the part's seed. 0: jewels (ruby, sapphire, emerald, amber,
// amethyst, a pale clear pane); 1: warm; 2: cool; 3: the surface's own colour in lighter and darker panes.
vec3 st_glass(float h, int mode, vec3 base) {
	if (mode == 3) {
		return base * mix(0.45, 1.3, h);
	}
	// Linear light: deep, a little dusky, so the panes glow rather than shout.
	int i = int(h * 6.0) % 6;
	if (mode == 1) {
		const vec3 WARM[6] = {vec3(0.32, 0.03, 0.02), vec3(0.50, 0.16, 0.01), vec3(0.62, 0.38, 0.05),
				vec3(0.26, 0.04, 0.07), vec3(0.55, 0.26, 0.09), vec3(0.58, 0.48, 0.28)};
		return WARM[i];
	}
	if (mode == 2) {
		const vec3 COOL[6] = {vec3(0.02, 0.05, 0.30), vec3(0.01, 0.17, 0.21), vec3(0.05, 0.26, 0.42),
				vec3(0.09, 0.04, 0.28), vec3(0.02, 0.17, 0.08), vec3(0.36, 0.48, 0.50)};
		return COOL[i];
	}
	const vec3 JEWEL[6] = {vec3(0.34, 0.01, 0.03), vec3(0.02, 0.05, 0.36), vec3(0.01, 0.19, 0.06),
			vec3(0.55, 0.22, 0.01), vec3(0.14, 0.03, 0.27), vec3(0.22, 0.25, 0.14)};
	return JEWEL[i];
}
#endif

void fragment() {
	FxSurface s = fx_surface(UV, world_pos, world_normal, local_pos, local_normal, FRONT_FACING,
			CAMERA_POSITION_WORLD);
	vec3 col = s.lit;
	float level = st_level(s.light);
	float key = st_key(s.n);
	vec3 ln = normalize(local_normal) * (FRONT_FACING ? 1.0 : -1.0);
#if defined(FX_HATCHING)
	// Pencil on paper: the darker the tone (the key light, the surface's own lightness), the more layers of strokes,
	// drawn on the three planes of the part's own axes so they stay on it; a soft pencil contour where the surface
	// turns away. On white paper, or on the surface's colour.
	float tone = key * mix(0.75, 1.2, st_lightness(s.base));
	float dark = clamp(1.0 - tone, 0.0, 1.0);
	vec3 q = local_pos / max(fx_scale, 0.002);
	float n = fx_noise3(local_pos / max(fx_scale * 6.0, 0.01) + fx_seed * 7.0);
	float wobble = 0.35 * (n - 0.5);
	vec3 w = st_planes(ln);
	float ink = st_hatch(q.zy, dark, wobble) * w.x + st_hatch(q.xz, dark, wobble) * w.y
			+ st_hatch(q.xy, dark, wobble) * w.z;
	// The pencil's pressure wanders along the strokes too; the contour is a little darker.
	ink *= mix(0.8, 1.0, n);
	float contour = smoothstep(0.3, 0.06, s.facing);
	ink = max(ink, contour * 0.8);
	vec3 paper = fx_mode == 0 ? vec3(0.8, 0.78, 0.72) : s.base * 1.2 + 0.04;
	vec3 pencil = fx_mode == 0 ? fx_color : mix(fx_color, s.base * 0.3, 0.4);
	col = mix(paper, pencil, ink * clamp(fx_strength, 0.0, 1.0)) * min(level, 1.0) + emission;
#elif defined(FX_HALFTONE)
	// Comic print: dots of the surface's colour on paper, small where the key light falls and growing to merge in
	// the shadow, on the planes of the part's own axes; the deepest shadow darkens the ink a little.
	float cover = clamp(0.1 + 0.95 * (1.0 - key), 0.0, 1.0);
	vec3 q = local_pos / max(fx_scale, 0.002);
	vec3 w = st_planes(ln);
	float d = st_dots(q.zy, cover) * w.x + st_dots(q.xz, cover) * w.y + st_dots(q.xy, cover) * w.z;
	vec3 ink = s.base * mix(1.0, 0.55, smoothstep(0.35, 0.05, key));
	col = mix(fx_color2, ink, d) * min(level, 1.0) + emission;
#elif defined(FX_PIXEL)
	// Retro pixels: the part's UV in square cells, each one colour: the picture at the cell's middle, lit in a few
	// hard steps by the key light worked out at the cell's middle (from this pixel by the derivatives, so a cell is
	// one tone), the colours snapped to a small palette. A faint gap between cells.
	float cells = clamp(fx_scale, 2.0, 256.0);
	vec2 c = UV * cells;
	vec2 cell = floor(c);
	vec2 mid = (cell + 0.5) / cells;
	mat2 j = mat2(dFdx(UV), dFdy(UV));
	vec2 step_to = abs(determinant(j)) > 1e-14 ? clamp(inverse(j) * (mid - UV), vec2(-256.0), vec2(256.0)) : vec2(0.0);
	float ndl = dot(s.n, normalize(ST_KEY));
	float ndl_mid = ndl + dFdx(ndl) * step_to.x + dFdy(ndl) * step_to.y;
	float levels = float(clamp(px_levels, 2, 8));
	float band = floor(clamp(0.5 + 0.5 * ndl_mid, 0.0, 0.999) * levels) / (levels - 1.0);
	vec3 picture = albedo;
	if (use_texture) {
		vec2 size = vec2(textureSize(albedo_texture, 0)) * uv_scale;
		float lod = log2(max(max(size.x, size.y) / cells, 1.0));
		picture *= textureLod(albedo_texture, mid * uv_scale, lod).rgb;
	}
	vec3 lit = picture * mix(0.3, 1.15, band) * min(level, 1.0) + emission;
	col = st_palette(lit, fx_mode, levels);
	float fw = max(max(fwidth(c.x), fwidth(c.y)), 1e-5);
	vec2 edge = 0.5 - abs(fract(c) - 0.5);
	vec2 gap = 1.0 - smoothstep(vec2(0.04 - fw * 0.5), vec2(0.04 + fw * 0.5), edge);
	float grid = max(gap.x, gap.y) * (1.0 - smoothstep(0.08, 0.25, fw));
	col *= 1.0 - grid * 0.35 * clamp(fx_param, 0.0, 1.0);
#elif defined(FX_WIREFRAME)
	// A glowing wireframe: the grid of the part's own space (planes every `pitch` metres on its three axes, where
	// they cross the surface), a line a pixel and a half wide with a soft glow around it, the same width near and
	// far; where the grid gets denser than about eight pixels a cell it fades to an even glow. Each axis's lines leave
	// the faces they would lie flat on. Opaque dark faces (a little of the surface shows) and a faint rim.
	vec3 x = local_pos / max(fx_scale, 0.005);
	vec3 fw = max(fwidth(x), vec3(1e-5));
	vec3 dpx = abs(fract(x + 0.5) - 0.5) / fw;
	vec3 core = 1.0 - smoothstep(vec3(0.5), vec3(1.6), dpx);
	vec3 halo = exp(-dpx * 0.4);
	vec3 dense = smoothstep(vec3(0.06), vec3(0.2), fw);
	vec3 keep = 1.0 - smoothstep(vec3(0.75), vec3(0.95), abs(ln));
	vec3 line = mix(core + 0.3 * halo, vec3(0.35), dense) * keep;
	float glow = clamp(max(max(line.x, line.y), line.z) + 0.25 * (line.x + line.y + line.z), 0.0, 1.6);
	vec3 faces = s.base * s.light * 0.6 * clamp(fx_param, 0.0, 1.0) + fx_color * 0.03;
	col = faces + fx_color * fx_strength * (glow + 0.35 * fx_rim(s.facing, 3.0)) + emission;
#elif defined(FX_STAINED_GLASS)
	// Stained glass: panes in cells of the noise texture's cell pattern, each one colour of a small palette (by its
	// cell and the part's seed), with dark lead between them (the texture's cell borders, mipmapped so they fade when
	// small). Drawn on the plane of the part's own axes it faces most; where that changes, a lead too, as panes
	// would meet. Lit from behind: brighter where it faces the screen, a slow mottle in the glass, its middle a little
	// brighter than its edges.
	vec3 an = abs(ln);
	vec2 plane = an.x >= an.y && an.x >= an.z ? local_pos.zy : (an.y >= an.z ? local_pos.xz : local_pos.xy);
	float repeat_m = max(fx_scale, 0.01) * 8.0;
	vec2 p = plane / repeat_m + fx_seed * 3.1;
	vec4 n4 = fx_fbm2(p);
	int k = st_cell(p * 8.0 - 1.0 / 64.0);
	vec3 pane = st_glass(fx_hash(vec3(float(k), fx_seed * 17.0, 3.0)), fx_mode, s.base);
	float top = max(max(an.x, an.y), an.z);
	float second = an.x + an.y + an.z - top - min(min(an.x, an.y), an.z);
	float seam_x = top - second;
	float lead_w = 0.085;
	float aa = max(fwidth(n4.a), 1e-4);
	float lead = 1.0 - smoothstep(lead_w - aa, lead_w + aa, n4.a);
	float seam_aa = max(fwidth(seam_x), 1e-4);
	lead = max(lead, 1.0 - smoothstep(0.035 - seam_aa, 0.035 + seam_aa, seam_x));
	lead = mix(lead, 0.18, fx_fine2(p * 8.0));
	float to_screen = max(dot(s.n, normalize(screen_center - world_pos)), 0.0);
	vec3 through = vec3(0.45) + 0.8 * to_screen * screen_glow * spill_tint(world_pos);
	float mottle = 0.8 + 0.4 * n4.r;
	// Brightest in a pane's middle, dimmer against its lead, as light through glass set in a frame.
	float inner = mix(0.6, 1.15, smoothstep(lead_w, 0.5, n4.a));
	vec3 glass = pane * through * mottle * inner * fx_strength;
	vec3 leads = vec3(0.03, 0.03, 0.035) * (0.6 + 0.6 * s.light) + vec3(0.04) * fx_rim(s.facing, 2.0);
	col = mix(glass, leads, lead) + emission;
#elif defined(FX_DUOTONE)
	// Two colours: the surface's tone (its colour and picture under the key light) mapped onto a gradient from the
	// shadow colour to the highlight colour, mixed in perceptual space so the middle is not muddy.
	float tone = pow(key, 1.5) * mix(0.5, 1.25, st_lightness(s.base)) * min(level, 1.0);
	float c = mix(0.5, 0.06, clamp(fx_param, 0.0, 1.0));
	tone = smoothstep(0.48 - c, 0.48 + c, tone);
	vec3 a = sqrt(fx_color);
	vec3 b = sqrt(fx_color2);
	vec3 m = mix(a, b, tone);
	col = m * m + emission;
#endif
	ALBEDO = col + fx_dither(FRAGCOORD.xy);
}
