// The effect library's natural effects (scripts/effects/catalogue/nature.gd, docs/effects.md): water, fire, smoke,
// sky and wind, all slow. Compiled once per effect with FX_<NAME> defined.
//
// Patterns that need cells or several octaves read fx_fbm (fx_common.gdshaderinc) laid on the part's own three planes
// and blended by its normal (nat_weights, sharp: mostly one plane shows), so a sphere, a box or a model is covered
// without stretching. Small things (stars, specks) are one candidate per cell of a grid on the plane the part faces
// most, drawn no smaller than a pixel with their energy spread when smaller, and faded to their average when the
// cells themselves get too small for the pixels.
//
//   caustics   light as under water: the borders of two layers of cells drifting apart, wobbled by a slow warp;
//              brightest where the layers meet. Lights the surface's own colour (layers).
//   water      a calm surface: two drifting layers of fbm tilt the normal a little; the deep colour in the middle,
//              fx_studio's surroundings and the screen's glint reflected at grazing angles (fresnel).
//   lava       dark crust plates (warped fbm cells) with molten cracks between them (the cells' borders), still;
//              a slow heat field creeping along them brightens the cracks and warms the plates' edges.
//   embers     a charred surface (fbm) with glowing seams and specks, each speck brightening and dimming at its own
//              slow rate, a few wandering a little; a dim heat breathing under the char.
//   smoke      see-through smoke rising and curling slowly: 3D value noise warped by a larger one, gathered into
//              wisps; thinning where the surface turns away, so the shell's outline does not show.
//   clouds     soft clouds drifting over a sky colour (fbm), forming and thinning slowly (a 3D noise in time).
//   starfield  stars on a night colour, each its own slow twinkle, and a faint band of dust with more stars in it.
//   wind_sway  the part bends from its foot in slow gusts (vertex motion, in metres); the surface keeps its colour,
//              with a faint pale sheen in the gusts, as leaves turning.
//
// Photosensitivity ceiling (docs/effects.md): no pixel changes faster than a 3 Hz wave of swing 0.4 would. Every
// brightness wave here is fx_swing(..., <= FX_MAX_SWING) at 1 Hz or slower. Drifting patterns move a few hundredths
// of a cell a second at speed 1 (the drift rates are in texture units, so a pattern keeps its pace in cells whatever
// its size), their edges are soft, and the brightest (caustics, smoke) sit over a floor of light, so a line or a
// wisp arriving changes a pixel by only part of its brightness. Lines and points fade to their average before they
// are thinner than a couple of pixels (nat_fine, fx_fine2), so nothing is sampled between pixels. The lava's plates
// stay still: drifting slowly over the magnified fbm texture, their sharp cracks moved in the filter's sub-texel
// steps, small jumps (the softer patterns here do not show them). fx_lab.gd --photo: every effect here at about half
// the ceiling or less.
shader_type spatial;
render_mode unshaded, shadows_disabled, specular_disabled;
#if defined(FX_SMOKE)
// See-through, both sides: the far side of a shell of smoke shows through the near one.
render_mode blend_mix, cull_disabled, depth_draw_never;
#else
render_mode cull_back;
#endif

#include "res://shaders/fx/fx_common.gdshaderinc"

#if defined(FX_WIND_SWAY)
// The height in the part's own space (metres) that stays still: its foot.
uniform float sway_base = -0.5;
// The pale sheen in the gusts, 0..0.4 of the colour.
uniform float sway_sheen = 0.15;
// The gust (-1..1) and how far the vertex bends (0 at the foot .. 1), for the sheen.
varying vec2 sway_gust;
#endif

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
#if defined(FX_WIND_SWAY)
	// Height above the foot, 0 at the foot and 1 at size metres above it. The bend starts gently, as a stem's, and
	// eases to its full at the top, with no kink anywhere (smoothstep).
	float h = smoothstep(0.0, 1.0, (VERTEX.y - sway_base) / max(fx_scale, 0.05));
	// Gusts: slow sines summed (fx_wander, at the rate and under it), arriving a little later further along the wind
	// (world x), so neighbouring plants are out of step. The lean is mostly downwind, a little across.
	vec3 origin = MODEL_MATRIX[3].xyz;
	float rate = mix(0.12, 0.6, fx_speed01());
	float tt = FX_TIME - origin.x * 0.35 - origin.z * 0.12;
	float g1 = fx_wander(tt, rate, fx_seed);
	float g2 = fx_wander(tt + 2.3, rate * 0.83, fx_seed + 0.41);
	float amp = clamp(fx_strength, 0.0, 0.2);
	vec3 bend = vec3(0.35 + 0.65 * g1, 0.0, 0.35 * g2) * amp * h;
	// From the room's metres into the part's own space (MODEL_MATRIX's inverse for a rotation and a scale).
	mat3 m = mat3(MODEL_MATRIX);
	vec3 sc = vec3(dot(m[0], m[0]), dot(m[1], m[1]), dot(m[2], m[2]));
	VERTEX += (transpose(m) * bend) / max(sc, vec3(1e-6));
	sway_gust = vec2(g1, h);
#endif
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	local_pos = VERTEX;
	local_normal = NORMAL;
}

// How much each of the part's three planes (x: zy, y: xz, z: xy) shows, by its own normal; sharp, so mostly one does
// and the blend between two is narrow.
vec3 nat_weights(vec3 n) {
	vec3 w = abs(n);
	w *= w;
	w *= w;
	return w / max(w.x + w.y + w.z, 1e-5);
}

// fx_fbm2 on the three planes (p in the texture's units), blended by w; each plane its own piece of the texture so
// they do not repeat each other.
vec4 nat_fbm3(vec3 p, vec3 w) {
	return fx_fbm2(p.zy + vec2(0.31, 0.57)) * w.x + fx_fbm2(p.xz) * w.y + fx_fbm2(p.xy + vec2(0.63, 0.19)) * w.z;
}

// fx_fine for a pattern in the part's own space, p in its cells: 0 while a cell spans k / 0.35 pixels or more, 1
// when it spans k / 0.9 or less. k: how many times thinner than a cell the pattern's lines are, so they fade out
// while still a couple of pixels wide.
float nat_fine(vec3 p, float k) {
	return smoothstep(0.35, 0.9, length(fwidth(p)) * k);
}

// The plane the part faces most there: its coordinates (q) and an index (0, 1, 2) for the cells' hashes.
vec3 nat_plane(vec3 p, vec3 n) {
	vec3 a = abs(n);
	if (a.x >= a.y && a.x >= a.z) {
		return vec3(p.zy, 0.0);
	}
	return a.y >= a.z ? vec3(p.xz, 1.0) : vec3(p.xy, 2.0);
}

// A glowing point per grid cell (stars, specks), drawn no smaller than a pixel: g the grid coordinate on the plane,
// at its position in the cell (0.2..0.8) with core its radius (cells, <= 0.1). Returns the light (energy kept when
// spread over a pixel), faded out at the cell's edge so a spread one is never cut by it.
float nat_point(vec2 g, vec2 at, float core) {
	float px = max(length(fwidth(g)), 1e-4);
	float r = max(core, px * 0.7);
	vec2 f = fract(g);
	float d2 = dot(f - at, f - at);
	float edge = 1.0 - smoothstep(0.38, 0.5, max(abs(f.x - 0.5), abs(f.y - 0.5)));
	return exp(-d2 / (r * r)) * (core * core) / (r * r) * edge;
}

void fragment() {
	FxSurface s = fx_surface(UV, world_pos, world_normal, local_pos, local_normal, FRONT_FACING,
			CAMERA_POSITION_WORLD);
	vec3 col = s.lit;
	float a = s.a;
#if defined(FX_CAUSTICS)
	// Light focused by moving water: two layers of cell borders drifting apart (and a slow warp wobbling both), per
	// plane so the lines stay whole. Thin bright lines, brightest where the layers meet, over a little light
	// everywhere. Speed 1 moves a layer 0.064 cells a second (and the warp about as much) and a line is about a
	// fifth of a cell wide, so it takes a few seconds to pass a pixel.
	float t = FX_TIME;
	vec3 p = local_pos / max(fx_scale, 0.05);
	vec3 w = nat_weights(local_normal);
	float v = 0.008 * fx_speed01();
	vec2 warp = (fx_noise3x2(p * 5.0 + vec3(0.0, 0.0, t * 0.07 * fx_speed01() + fx_seed * 5.0)) - 0.5) * 0.05;
	vec2 d1 = vec2(t * v, t * v * 0.6) + warp + fx_seed;
	vec2 d2 = vec2(-t * v * 0.7, t * v) + warp.yx + 0.5;
	vec3 c1 = vec3(fx_fbm2(p.zy * 0.5 + d1 + 0.3).a, fx_fbm2(p.xz * 0.5 + d1).a, fx_fbm2(p.xy * 0.5 + d1 + 0.6).a);
	vec3 c2 = vec3(fx_fbm2(p.zy * 0.43 + d2 + 0.3).a, fx_fbm2(p.xz * 0.43 + d2).a,
			fx_fbm2(p.xy * 0.43 + d2 + 0.6).a);
	vec3 l1 = 1.0 - smoothstep(0.0, 0.36, c1);
	vec3 l2 = 1.0 - smoothstep(0.0, 0.36, c2);
	// Mostly the lines themselves: where two nearly parallel ones cross, the crossing slides along them fast, so it
	// only adds a little.
	vec3 lines = 0.45 * (l1 * l1 + l2 * l2) + 0.5 * l1 * l2;
	float caustic = dot(lines, w);
	caustic = mix(caustic, 0.22, nat_fine(p * 4.0, 4.0));
	col += mix(s.base, vec3(1.0), 0.35) * fx_color * fx_strength * (0.25 + caustic);
#elif defined(FX_WATER)
	// A calm surface: the normal tilted a little by two layers of fbm drifting different ways (each plane tilting
	// along itself), then the deep colour where you look into it and the surroundings where you look across it.
	float t = FX_TIME;
	vec3 p = local_pos / max(fx_scale, 0.05) * 0.25;
	vec3 w = nat_weights(local_normal);
	float v = 0.012 * fx_speed01();
	vec2 d1 = vec2(t * v, t * v * 0.4);
	vec2 d2 = vec2(-t * v * 0.55, t * v * 0.8) + 0.37;
	vec4 x1 = fx_fbm2(p.zy + d1 + 0.3);
	vec4 y1 = fx_fbm2(p.xz + d1);
	vec4 z1 = fx_fbm2(p.xy + d1 + 0.6);
	vec2 x2 = fx_fbm2(p.zy * 1.9 + d2 + 0.3).gr;
	vec2 y2 = fx_fbm2(p.xz * 1.9 + d2).gr;
	vec2 z2 = fx_fbm2(p.xy * 1.9 + d2 + 0.6).gr;
	vec2 tx = x1.rg + 0.6 * x2 - 0.8;
	vec2 ty = y1.rg + 0.6 * y2 - 0.8;
	vec2 tz = z1.rg + 0.6 * z2 - 0.8;
	vec3 tilt = vec3(0.0, tx.y, tx.x) * w.x + vec3(ty.x, 0.0, ty.y) * w.y + vec3(tz.x, tz.y, 0.0) * w.z;
	float height = dot(vec3(x1.r, y1.r, z1.r), w);
	tilt = (MODEL_MATRIX * vec4(tilt, 0.0)).xyz;
	tilt -= s.n * dot(tilt, s.n);
	vec3 n = normalize(s.n + tilt * mix(0.1, 0.9, clamp(fx_param, 0.0, 1.0)));
	float facing = clamp(dot(n, s.v), 0.0, 1.0);
	vec3 r = reflect(-s.v, n);
	float f = 0.04 + 0.96 * pow(1.0 - facing, 5.0);
	// The body: the deep colour, lighter on the crests (light scattered back through the thin water).
	vec3 deep = fx_color * s.light * (0.6 + 0.8 * height);
	vec3 around = fx_studio(r, s.light);
	// The screen's glint and a soft key light from above, broken up by the ripples.
	float glint = pow(max(dot(r, normalize(screen_center - world_pos)), 0.0), 10.0) * screen_glow;
	float key = pow(max(dot(r, normalize(vec3(-0.35, 0.8, 0.5))), 0.0), 12.0);
	col = mix(deep, around, clamp(f * fx_strength, 0.0, 1.0)) + fx_strength * (0.3 * glint * spill_tint(world_pos)
			+ 0.12 * key * (s.light + 0.2)) + emission;
#elif defined(FX_LAVA)
	// Crust plates (the fbm's cells, warped) with molten cracks between them (its cell borders), still (see the top).
	// The flow is a heat field (3D value noise) creeping along and through time, a tenth of its cell a second at
	// speed 1, that brightens the cracks and warms the plates' edges.
	float t = FX_TIME;
	vec3 m = local_pos / max(fx_scale, 0.05);
	vec3 p = m * 0.125;
	vec3 w = nat_weights(local_normal);
	// A still warp a third of a plate across, so the plates are not the texture's tidy cells.
	vec2 bend = fx_noise3x2(m * 1.3 + fx_seed * 3.0) - 0.5;
	vec4 c = nat_fbm3(p + vec3(bend, bend.x - bend.y) * 0.05, w);
	float heat = fx_noise3(m * 0.7 + t * fx_speed01() * vec3(0.05, 0.03, 0.08) + fx_seed * 9.0);
	heat = smoothstep(0.15, 0.85, heat);
	// The cracks' width does not change with time (an edge sweeping a pixel would flash it): only their glow does.
	float wide = mix(0.08, 0.24, clamp(fx_param, 0.0, 1.0));
	float width = wide * (0.6 + 0.8 * c.g);
	float aa = fwidth(c.a);
	float crack = 1.0 - smoothstep(0.0, width + aa, c.a);
	float bleed = 1.0 - smoothstep(0.0, width * 2.5 + aa, c.a);
	float fine = nat_fine(p * 8.0, 1.4 / wide);
	crack = mix(crack, wide * 1.6, fine);
	bleed = mix(bleed, wide * 3.0, fine);
	vec3 crust = fx_color2 * s.light * (0.6 + 0.7 * c.r) * (0.85 + 0.3 * c.b);
	float hot = crack * (0.35 + 0.65 * heat);
	vec3 molten = mix(fx_color * vec3(0.55, 0.3, 0.25), fx_color, smoothstep(0.1, 0.6, hot));
	molten = mix(molten, mix(fx_color, vec3(1.0, 0.92, 0.65), 0.6), smoothstep(0.6, 1.0, hot));
	col = crust + emission + fx_color * fx_strength * 0.12 * bleed * (0.3 + 0.7 * heat);
	col = mix(col, molten * fx_strength * (0.4 + 0.8 * hot), crack);
#elif defined(FX_EMBERS)
	// Char (the fbm's noise and cell borders, darker in the cracks) with a dim heat breathing under it, and specks:
	// one candidate per cell of a grid on the plane the part faces, kept by density, each brightening and dimming
	// by at most the swing at its own rate (a quarter of the rate .. the rate), a few wandering a little in their cell.
	float t = FX_TIME;
	vec3 p = local_pos / max(fx_scale, 0.05);
	vec3 w = nat_weights(local_normal);
	vec4 c = nat_fbm3(p * 0.06, w);
	// The heat: patches a few specks across, drifting through time over about twenty seconds.
	float under = smoothstep(0.3, 0.8, fx_noise3(p * 0.3 + vec3(0.0, 0.0, t * 0.05) + fx_seed * 7.0));
	float seams = 1.0 - smoothstep(0.0, 0.12 + fwidth(c.a), c.a);
	seams = mix(seams, 0.15, nat_fine(p * 0.48, 5.0));
	vec3 chr = fx_color2 * s.light * (0.55 + 0.9 * c.r) * (1.0 - 0.4 * seams);
	col = chr + emission + fx_color * fx_strength * under * (0.03 + 0.2 * seams * c.r);
	vec3 q = nat_plane(p, local_normal);
	vec3 cell = vec3(floor(q.xy), q.z * 17.0 + 3.0);
	float many = mix(0.1, 0.7, clamp(fx_param, 0.0, 1.0));
	float glow = 0.0;
	if (fx_hash(cell + 11.0) < many) {
		vec2 at = vec2(0.3) + 0.4 * vec2(fx_hash(cell + 1.7), fx_hash(cell + 3.1));
		float k = fx_hash(cell + 5.3);
		if (k < 0.2) {
			float ph = FX_TAU * (0.03 * t * (0.5 + k * 2.5) + fx_hash(cell + 6.6));
			at += 0.1 * vec2(sin(ph), cos(ph * 0.8));
		}
		float rate = fx_rate_hz() * (0.25 + 0.75 * fx_hash(cell + 9.4));
		float b = (0.3 + 1.5 * pow(fx_hash(cell + 7.9), 2.0)) * (0.2 + 0.8 * under);
		float tw = fx_swing(sin(FX_TAU * (rate * t + fx_hash(cell + 13.2))), fx_depth);
		glow = nat_point(q.xy, at, 0.03 + 0.07 * k * k) * b * tw;
	}
	glow = mix(glow, 0.01 * many * (0.2 + 0.8 * under), fx_fine2(q.xy));
	vec3 hot = mix(fx_color, vec3(1.0, 0.85, 0.55), smoothstep(0.6, 1.4, glow));
	col += hot * fx_strength * glow;
#elif defined(FX_SMOKE)
	// Two taps of 3D value noise, stretched upwards: a large one rising, which warps a finer one rising faster and
	// drifting a little. Lit by the room, thinner where the surface turns away from you. Speed 1 moves the noise 0.1
	// to 0.16 of its cells a second (the smoke rises about a quarter of a puff a second).
	float t = FX_TIME;
	vec3 p = local_pos / max(fx_scale, 0.05);
	float v = 0.1 * fx_speed01();
	vec3 up = vec3(1.0, 0.45, 1.0);
	vec2 big = fx_noise3x2(p * up * 0.9 + vec3(0.0, -t * v, t * v * 0.1) + fx_seed * 7.0);
	vec3 q = p * up * 2.4 + vec3(big.x - 0.5, 0.0, big.y - 0.5) * 1.5 + vec3(t * v * 0.2, -t * v * 1.6, 0.0);
	vec2 fine = fx_noise3x2(q);
	float fade = fx_fine2(q.xy);
	float detail = mix(fine.x, 0.5, fade);
	// Streaks: where the finer noise's second half crosses its middle, the smoke gathers into wisps.
	float wisp = mix(1.0 - abs(2.0 * fine.y - 1.0), 0.5, fade);
	// Never quite clear (a faint haze), so a wisp coming and going changes a pixel only by part of its brightness.
	float dens = 0.12 + 0.88 * smoothstep(0.5, 0.85, big.y * 0.58 + detail * 0.42) * (0.45 + 0.55 * wisp);
	col = fx_color * s.light * (0.85 + 0.3 * wisp) + emission;
	a = clamp(dens * fx_strength * 0.6 * smoothstep(0.0, 0.6, s.facing), 0.0, 1.0) * s.a;
#elif defined(FX_CLOUDS)
	// fbm on the part's planes drifting with the wind; a 3D noise moving through time thickens and thins it slowly.
	// Cover sets how much is cloud. Brighter where thick (lit from above), over the sky colour.
	float t = FX_TIME;
	vec3 p = local_pos / max(fx_scale, 0.05) * 0.25;
	vec3 w = nat_weights(local_normal);
	vec3 wind = t * 0.006 * fx_speed01() * vec3(1.0, 0.3, 0.6);
	vec4 c = nat_fbm3(p + wind, w);
	vec2 grow = fx_noise3x2(p * 10.0 + vec3(0.0, 0.0, t * 0.05 * fx_speed01()) + fx_seed * 5.0);
	grow = mix(grow, vec2(0.5), fx_fine2(vec2(p.x + p.z, p.y) * 10.0));
	float n = c.r * 0.7 + c.g * 0.3 + 0.12 * (grow.x - 0.5) + 0.06 * (grow.y - 0.5);
	float cover = clamp(fx_param, 0.0, 1.0);
	float edge = 0.66 - 0.3 * cover;
	float dens = smoothstep(edge, edge + 0.08, n);
	// Thin edges grey, a little of the sky in them; the thick middles bright.
	vec3 cloud = mix(mix(fx_color, fx_color2, 0.3) * 0.7, fx_color, smoothstep(edge + 0.02, edge + 0.18, n));
	vec3 sky = fx_color2 * (0.92 + 0.16 * c.g);
	col = mix(sky, cloud, dens * 0.96) * s.light + emission;
#elif defined(FX_STARFIELD)
	// Stars: one candidate per cell (size metres) of a grid on the plane the part faces, kept by density (more in the
	// dust band), placed inside the cell, brightness skewed so few are bright, a slight colour each; drawn no smaller
	// than a pixel, faded to their average when the cells get too small. Twinkle: each its own rate (0.15..1 Hz) and
	// phase, by at most the twinkle (<= 0.4). The band: a slab through the part's middle, clumped by noise. The
	// night glows by itself (a painted or lit dome), not lit by the room.
	float t = FX_TIME;
	vec3 p = local_pos / max(fx_scale, 0.01);
	vec3 bn = normalize(vec3(0.35, 1.0, 0.25));
	float bd = dot(local_pos, bn) / max(length(local_pos), 0.3);
	float dust = fx_noise3(local_pos * 1.6 + fx_seed * 3.0) * 0.6 + fx_noise3(local_pos * 4.1 + 0.5) * 0.4;
	float band = exp(-bd * bd / 0.02) * smoothstep(0.3, 0.8, dust);
	col = fx_color2 * (1.0 + 1.5 * band) + fx_color * vec3(0.8, 0.82, 1.0) * band * 0.015 * fx_strength + emission;
	vec3 q = nat_plane(p, local_normal);
	vec3 cell = vec3(floor(q.xy), q.z * 17.0 + 5.0);
	float keep = mix(0.04, 0.5, clamp(fx_param, 0.0, 1.0)) * (1.0 + 1.5 * band);
	vec3 star = vec3(0.0);
	if (fx_hash(cell + 11.0) < keep) {
		vec2 at = vec2(0.25) + 0.5 * vec2(fx_hash(cell + 1.7), fx_hash(cell + 3.1));
		float b = pow(fx_hash(cell + 7.9), 3.0) * 1.6 + 0.12;
		float rate = 0.15 + 0.85 * fx_hash(cell + 9.4);
		float tw = fx_swing(sin(FX_TAU * (rate * t + fx_hash(cell + 13.2))), fx_depth);
		vec3 tint = mix(vec3(0.8, 0.88, 1.0), vec3(1.0, 0.9, 0.75), fx_hash(cell + 15.8));
		star = tint * b * tw * nat_point(q.xy, at, 0.07);
	}
	star = mix(star, vec3(0.0025 * keep), fx_fine2(q.xy));
	col += fx_color * fx_strength * star;
#elif defined(FX_WIND_SWAY)
	// The surface as it is, a pale sheen rising and falling with the gusts where the part bends most.
	col += fx_color * s.light * clamp(sway_sheen, 0.0, 0.4) * sway_gust.y * fx_swing(sway_gust.x, FX_MAX_SWING);
#endif
	ALBEDO = fx_print(col + fx_dither(FRAGCOORD.xy), UV);
#if defined(FX_SMOKE)
	ALPHA = a;
#endif
}
