// The effect library's materials (scripts/effects/catalogue/materials.gd, docs/effects.md): procedural surfaces
// that look like a real material, polished, woven or cut. Compiled once per effect with FX_<NAME> defined.
//
// The rooms have no lights to reflect, so the shiny ones reflect a made-up studio (fx_studio: a dim floor, a bright
// soft band at the horizon, a sky brightening overhead, tinted by the room's light), a key light above and in front
// (a small highlight), and the screen's glint in its own colour. Their patterns come from the shared noise textures
// at low frequencies, faded to their average where they would be finer than a pixel (there is no MSAA).
//
// iridescent      thin-film colours (a soap bubble, a beetle's shell) over the surface: the hue turns with the angle
//                 you see it at and with the film's thickness, which wanders over the surface
// pearl           soft lustrous white with a faint pink and green sheen that turns with the angle, a gentle highlight
// velvet          the surface's colour as soft fabric: darker facing you, a bright soft sheen at the rim
// brushed_metal   fine streaks around the part or along it, the highlight stretched across them, the colour tinting
// carbon_fibre    a woven twill of dark fibre bands under a clear coat; the bands catch the light by their direction
// marble          veined polished stone; the veins can flow very slowly (flow, 0 by default)
// crystal         see-through cut crystal: flat facets, sharp glints, rainbow tints along the facets' edges
// liquid_chrome   a mirror whose reflection slowly flows, as if the metal were liquid
// frosted_glass   see-through milky glass, brighter and more opaque at grazing angles, a soft fine grain
//
// Photosensitivity: only liquid_chrome and marble (with flow) move. Their reflections and veins drift so slowly that
// no pixel changes faster than a 3 Hz wave of the full swing (docs/effects.md, "Photosensitivity"); the others do not
// read the clock at all.
shader_type spatial;
render_mode unshaded, shadows_disabled, specular_disabled;
#if defined(FX_CRYSTAL) || defined(FX_FROSTED_GLASS)
// See-through, as room_effect.gdshader's glass: drawn over what is behind, writing no depth.
render_mode cull_back, depth_draw_never;
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

// The key light: above, a little left, in front (room_effect.gdshader's metal).
const vec3 MAT_KEY = vec3(-0.45, 0.75, 0.5);

float mat_key(vec3 r, float power) {
	return pow(max(dot(r, normalize(MAT_KEY)), 0.0), power);
}

// The screen's glint seen in a reflection r at p, in the screen's colour.
vec3 mat_glint(vec3 r, vec3 p, float power) {
	return pow(max(dot(r, normalize(screen_center - p)), 0.0), power) * screen_glow * spill_tint(p);
}

// A clear polished coat over a surface: the studio reflected by fresnel (faint facing you, whole at grazing angles),
// a small highlight and the screen's glint.
vec3 mat_coat(FxSurface s, vec3 p, float strength) {
	vec3 r = reflect(-s.v, s.n);
	float f = 0.04 + 0.96 * pow(1.0 - s.facing, 5.0);
	return strength * (fx_studio(r, s.light) * f + mat_key(r, 160.0) * 0.45 * (s.light + 0.3)
			+ mat_glint(r, p, 96.0) * 0.5);
}

// A flat place on the part for patterns: its own space folded to 2D (as fx_reactive's caustics), in units of size.
vec2 mat_plane(vec3 lp, float size) {
	return (lp.xz + lp.y * vec2(0.37, -0.23)) / max(size, 0.01);
}

// Marble's vein: fx_line with its edge never sharper than 0.01 of the way between veins, so a vein creeping
// past (flow) takes at least half a second to cover a pixel, however the surface is turned.
float mat_vein(float x, float half_width) {
	float w = max(fwidth(x), 0.01);
	float l = 1.0 - smoothstep(half_width - w, half_width + w, x);
	return mix(l, half_width * 2.0, smoothstep(half_width * 1.5, half_width * 4.0, fwidth(x)));
}

// Crystal's cut: of the 26 directions to the sides, edges and corners of a cube turned by `turn`, the one nearest
// the normal n (nq, back in n's frame), how near it is (returned), and how much nearer than the next (e: 0 on an
// edge between two facets). With n's sizes sorted a >= b >= c, the nearest is the largest of a, (a + b) / sqrt 2
// and (a + b + c) / sqrt 3, and its direction takes n's largest one, two or three components.
float mat_cut(vec3 n, mat3 turn, out vec3 nq, out float e) {
	vec3 nl = turn * n;
	vec3 m = abs(nl);
	float ma = max(m.x, max(m.y, m.z));
	float mc = min(m.x, min(m.y, m.z));
	float mb = m.x + m.y + m.z - ma - mc;
	vec3 cand = vec3(ma, (ma + mb) * 0.70711, (ma + mb + mc) * 0.57735);
	float best = max(cand.x, max(cand.y, cand.z));
	e = best - (cand.x + cand.y + cand.z - best - min(cand.x, min(cand.y, cand.z)));
	float pick = best == cand.x ? (ma + mb) * 0.5 : (best == cand.y ? (mb + mc) * 0.5 : mc * 0.5);
	nq = transpose(turn) * normalize(sign(nl) * step(vec3(pick), m));
	return best;
}

void fragment() {
	FxSurface s = fx_surface(UV, world_pos, world_normal, local_pos, local_normal, FRONT_FACING,
			CAMERA_POSITION_WORLD);
	vec3 col = s.lit;
	float a = s.a;
	vec3 r = reflect(-s.v, s.n);
#if defined(FX_IRIDESCENT)
	// Thin-film interference: light reflected from the film's top and bottom adds up or cancels by wavelength, so a
	// film of a few hundred nanometres shows bands of colour. The path through it is 2 n d cos(angle inside), so the
	// hue turns as the surface turns away. The thickness d wanders slowly over the surface (fx_fbm2), around a mean
	// set by `thickness`. The colours tint the studio's reflection over the surface's own colour.
	vec2 p = mat_plane(local_pos, fx_scale);
	float d = mix(0.28, 0.62, clamp(fx_param, 0.0, 1.0)) + 0.32 * (fx_fbm2(p * 0.3 + fx_seed).r - 0.5);
	float cos_in = sqrt(1.0 - (1.0 - s.facing * s.facing) / (1.33 * 1.33));
	vec3 film = 0.5 + 0.5 * cos(FX_TAU * 2.0 * 1.33 * d * cos_in / vec3(0.65, 0.54, 0.46));
	film = mix(vec3(dot(film, vec3(0.3, 0.5, 0.2))), film, 0.8);
	float f = mix(0.18, 0.9, pow(1.0 - s.facing, 2.5));
	float k = clamp(fx_strength, 0.0, 2.0);
	vec3 env = fx_studio(r, s.light) * 0.45 + 0.06 * s.light;
	col = s.lit * (1.0 - 0.2 * min(k, 1.0)) + film * (env * f + mat_key(r, 60.0) * 0.3 * (s.light + 0.3)) * k;
#elif defined(FX_PEARL)
	// Nacre: a soft body lit around its curve, faint cloudy layers, a sheen at the rim turning from pink to green
	// with the angle (thin layers of nacre), a dim soft reflection and a gentle highlight.
	vec2 p = mat_plane(local_pos, 0.25);
	float nacre = fx_fbm2(p * 0.4 + fx_seed).g;
	vec3 body = fx_color * s.light * (0.28 + 0.3 * s.facing) * (0.95 + 0.12 * (nacre - 0.5));
	float edge = 1.0 - s.facing;
	vec3 hue = mix(vec3(1.0, 0.72, 0.82), vec3(0.72, 1.0, 0.86), smoothstep(0.2, 0.8, edge + 0.4 * (nacre - 0.5)));
	float k = clamp(fx_strength, 0.0, 2.0);
	float f = 0.06 + 0.5 * pow(edge, 3.0);
	col = body + hue * fx_color * (pow(edge, 1.4) * 0.22 * k * (s.light + 0.2) + fx_studio(r, s.light) * f)
			+ k * (mat_key(r, 30.0) * 0.28 * (s.light + 0.3) + mat_glint(r, world_pos, 24.0) * 0.15) + emission;
#elif defined(FX_VELVET)
	// Pile standing up from the cloth: looking straight in you see between the fibres (darker), at a slant you see
	// their sides (a bright soft sheen at the rim). Broad patches where the pile lies differently, and a faint fine
	// texture that fades out before it is finer than a pixel.
	vec2 p = mat_plane(local_pos, 1.0);
	vec4 n = fx_fbm2(p * 0.6 + fx_seed);
	float fine = mix(fx_fbm2(p * 9.0).r - 0.5, 0.0, fx_fine2(p * 9.0 * 32.0));
	float pile = 1.0 + 0.16 * (n.g - 0.5) + 0.1 * fine;
	float rim = pow(1.0 - s.facing, 2.2);
	vec3 sheen = mix(s.base, vec3(1.0), 0.35) * fx_color;
	col = s.base * s.light * (0.3 + 0.16 * s.facing) * pile
			+ sheen * (s.light + 0.1) * rim * 1.4 * clamp(fx_strength, 0.0, 2.0) * pile + emission;
#elif defined(FX_BRUSHED_METAL)
	// Brushed metal: fine grooves run one way, around the part's upright axis (as on a turned post) or along it. Each
	// groove tilts the surface across itself, so the reflection breaks into streaks along the grooves, and the
	// highlight spreads across them (anisotropic: Kajiya-Kay's strand highlight). The surface's colour tints it all;
	// the finest streaks fade to their average before they are finer than a pixel.
	vec3 up = normalize(mat3(MODEL_MATRIX) * vec3(0.0, 1.0, 0.0));
	vec3 side = normalize(mat3(MODEL_MATRIX) * vec3(1.0, 0.0, 0.0));
	vec3 around = cross(up, s.n);
	around = length(around) > 1e-3 ? normalize(around) : side;
	vec3 groove = fx_mode == 0 ? around : normalize(cross(s.n, around));
	vec3 tilt = cross(s.n, groove);
	// Along: across the streaks is the face's horizontal (x, or z on a face looking along x).
	float flat_x = abs(local_normal.x) > abs(local_normal.z) ? local_pos.z : local_pos.x;
	float across = fx_mode == 0 ? local_pos.y : flat_x;
	float along = fx_mode == 0 ? local_pos.x * 0.7 + local_pos.z * 0.7 : local_pos.y;
	float coarse = fx_fbm2(vec2(along * 0.15 + fx_seed, across * 6.0)).r - 0.5;
	float fine = mix(fx_fbm2(vec2(along * 0.3, across * 22.0 + 0.5)).g - 0.5, 0.0, fx_fine(across * 22.0 * 32.0));
	float streak = coarse * 0.6 + fine * 0.8;
	vec3 rb = reflect(-s.v, normalize(s.n + tilt * streak * 0.35));
	vec3 env = fx_studio(rb, s.light);
	env = mix(env, vec3(dot(env, vec3(0.333))), 0.25);
	vec3 h = normalize(normalize(MAT_KEY) + s.v);
	float th = dot(groove, h);
	float spec = pow(max(1.0 - th * th, 0.0), 60.0);
	vec3 hs = normalize(normalize(screen_center - world_pos) + s.v);
	float ts = dot(groove, hs);
	float sglint = pow(max(1.0 - ts * ts, 0.0), 120.0) * screen_glow;
	vec3 tint = mix(s.base, vec3(1.0), 0.12);
	float k = clamp(fx_strength, 0.0, 2.0);
	col = tint * env * (0.82 + 0.35 * streak) + k * (spec * 0.32 * mix(tint, vec3(1.0), 0.4) * (s.light + 0.3)
			+ sglint * 0.25 * spill_tint(world_pos) * tint) * (0.85 + 0.5 * streak) + emission;
#elif defined(FX_CARBON_FIBRE)
	// A 2/2 twill: bands of fibre (tows) a `size` wide, each passing over two crossing bands and under two, which
	// draws the weave's diagonal steps. Each tow is rounded across (darker at its sides and ends, so neighbouring
	// tows meet in a soft dark seam instead of an edge) and catches the light along its fibres: the two directions
	// light up at different angles. Mapped by the part's own space on its face's main axis, in metres. Too fine for
	// the pixels, the weave fades to its average. A clear coat over it all.
	vec3 an = abs(local_normal);
	vec2 q;
	vec3 tu;
	vec3 tv;
	if (an.x >= an.y && an.x >= an.z) {
		q = local_pos.zy;
		tu = vec3(0.0, 0.0, 1.0);
		tv = vec3(0.0, 1.0, 0.0);
	} else if (an.y >= an.z) {
		q = local_pos.xz;
		tu = vec3(1.0, 0.0, 0.0);
		tv = vec3(0.0, 0.0, 1.0);
	} else {
		q = local_pos.xy;
		tu = vec3(1.0, 0.0, 0.0);
		tv = vec3(0.0, 1.0, 0.0);
	}
	q /= max(fx_scale, 0.002);
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float step4 = mod(cell.x + cell.y, 4.0);
	bool along_u = step4 < 2.0;
	float run = (along_u ? step4 + f.x : step4 - 2.0 + f.y) * 0.5;
	float side_of = along_u ? f.y : f.x;
	float profile = pow(sin(3.14159265 * side_of), 0.6) * smoothstep(0.0, 0.07, run) * smoothstep(1.0, 0.93, run);
	// Fibres along the tow: faint lines, stretched noise across it, gone before they are finer than a pixel.
	vec2 qs = along_u ? vec2(q.x * 0.08, q.y * 5.0) : vec2(q.y * 0.08 + 0.5, q.x * 5.0);
	float strand = mix(fx_fbm2(qs).r - 0.5, 0.0, fx_fine(qs.y * 32.0));
	vec3 fibre = normalize(mat3(MODEL_MATRIX) * (along_u ? tu : tv));
	vec3 h = normalize(normalize(MAT_KEY) + s.v);
	float th = dot(fibre, h);
	float sheen = pow(max(1.0 - th * th, 0.0), 30.0);
	vec3 hs = normalize(normalize(screen_center - world_pos) + s.v);
	float ts = dot(fibre, hs);
	vec3 glow = (s.light + 0.2) * 0.11 * sheen + spill_tint(world_pos) * screen_glow * 0.1
			* pow(max(1.0 - ts * ts, 0.0), 30.0);
	vec3 tow = (fx_color * s.light * (0.35 + 0.5 * profile) + glow * profile) * (1.0 + 0.5 * strand);
	vec3 mean = fx_color * s.light * 0.65 + glow * 0.6;
	// The bands' rounding repeats every band, so the weave fades to its mean from about 7 pixels a band down to 2.5
	// (sooner than fx_fine2, which would leave a moire).
	vec2 qw = fwidth(q);
	float fade = smoothstep(0.15, 0.4, max(qw.x, qw.y));
	col = mix(tow, mean, fade) + mat_coat(s, world_pos, clamp(fx_strength, 0.0, 2.0)) + emission;
#elif defined(FX_MARBLE)
	// Veined stone: veins are sheets through the block, folded by two layers of smooth noise so they wander, thicken
	// and thin; where the surface cuts a sheet it shows a vein (a fine dark line in a softer halo). Finer hairline
	// veins cross them here and there, and faint clouding lies in the stone. A polished clear coat over it. flow
	// moves the sheets very slowly through the folds (at most a fiftieth of the way to the next vein a second), so
	// the veins creep and change shape like ink in water. (The sheets move, not the noise: a texture moved by less
	// than its filter's precision steps instead of gliding, and the thin veins would show every step.)
	vec3 q = local_pos / max(fx_scale, 0.05) + fx_seed * 5.0;
	vec2 w = fx_noise3x2(q * 0.7);
	vec2 w2 = fx_noise3x2(q * 1.9 + 3.7);
	float creep = 0.0;
	if (fx_speed > 0.0) {
		creep = FX_TIME * 0.02 * fx_speed01();
	}
	float u = dot(q, vec3(0.62, 0.48, 0.3)) + 1.7 * (w.x - 0.5) + 0.5 * (w2.x - 0.5) - creep;
	float u2 = dot(q, vec3(-0.35, 0.55, 0.75)) * 1.6 + 2.2 * (w.y - 0.5) + 0.7 * (w2.y - 0.5) + creep * 0.7;
	float d1 = abs(fract(u + 0.5) - 0.5);
	float d2 = abs(fract(u2 + 0.5) - 0.5);
	float width = 0.005 + 0.025 * smoothstep(0.4, 0.8, w.y);
	float vein = mat_vein(d1, width) * (0.45 + 0.35 * w2.y) + (1.0 - smoothstep(0.0, 0.22, d1)) * 0.16
			+ (mat_vein(d2, 0.006) * 0.5 + (1.0 - smoothstep(0.0, 0.06, d2)) * 0.1) * smoothstep(0.45, 0.65, w2.x);
	float cloud = fx_fbm2(mat_plane(local_pos, fx_scale) * 0.12).g - 0.5;
	vec3 stone = mix(fx_color * (0.97 + 0.2 * cloud), fx_color2, clamp(vein, 0.0, 1.0));
	col = stone * s.light * (0.6 + 0.18 * s.facing) + mat_coat(s, world_pos, clamp(fx_strength, 0.0, 2.0) * 0.8)
			+ emission;
#elif defined(FX_CRYSTAL)
	// Cut crystal: the normal, nudged by slow noise and snapped to the nearest of 52 directions, makes flat facets
	// meeting at sharp edges (on a curved part like a cut stone, on a flat face as broad planes). Each facet
	// reflects the studio by fresnel and flashes as a whole when it turns to the key light; through it, the room
	// shows darkened and bent, and light bouncing inside brightens some facets more than others. The facets' edges
	// split the light into rainbow tints that turn with the angle. The colour tints the crystal.
	// The cut: two sets of 26 facets, each facing the sides, edges and corners of a cube, the two cubes turned
	// apart (mat_cut). Slow noise nudges the normal, so flat faces get broad facets too and the cut is not regular.
	vec2 wn = fx_noise3x2(local_pos / max(fx_scale, 0.05) + fx_seed * 7.0) - 0.5;
	vec3 nn = normalize(local_normal + 0.22 * vec3(wn.x, wn.y, -wn.x - wn.y));
	const mat3 TURN_A = mat3(vec3(0.866, 0.171, -0.470), vec3(0.0, 0.940, 0.342), vec3(0.5, -0.296, 0.814));
	const mat3 TURN_B = mat3(vec3(0.707, 0.0, 0.707), vec3(-0.408, 0.816, 0.408), vec3(-0.577, -0.577, 0.577));
	vec3 nqa;
	vec3 nqb;
	float ea;
	float eb;
	float ba = mat_cut(nn, TURN_A, nqa, ea);
	float bb = mat_cut(nn, TURN_B, nqb, eb);
	vec3 nq = ba > bb ? nqa : nqb;
	// Near a facet's edge the two nearest directions are about as near.
	float e = min(ba > bb ? ea : eb, abs(ba - bb));
	float edge = 1.0 - smoothstep(0.0, 0.005 + fwidth(e), e);
	vec3 n = normalize(mat3(MODEL_MATRIX) * nq) * (FRONT_FACING ? 1.0 : -1.0);
	float facing = clamp(dot(n, s.v), 0.0, 1.0);
	vec3 rf = reflect(-s.v, n);
	vec3 rt = refract(-s.v, n, 1.0 / 1.5);
	float f = 0.05 + 0.95 * pow(1.0 - facing, 4.0);
	vec3 rainbow = 0.55 + 0.45 * cos(FX_TAU * (dot(rf, vec3(1.3, 0.7, 0.9)) * 1.2 + vec3(0.0, 0.33, 0.67)));
	// Light bouncing inside: each facet shows its own share, brightening and dimming as you move past it.
	float inner = 0.5 + 0.5 * cos(FX_TAU * (fx_hash(nq * 3.7 + fx_seed) + 1.2 * dot(s.v, n)));
	float glint = mat_key(rf, 120.0);
	vec3 tint = mix(s.base, vec3(1.0), 0.35);
	col = tint * (fx_studio(rt, s.light) * 0.36 + inner * inner * 0.3 * (s.light + 0.2))
			+ fx_studio(rf, s.light) * f * 0.75 + rainbow * edge * 0.4 * (s.light + 0.2) * clamp(fx_strength, 0.0, 2.0)
			+ glint * 0.6 * (s.light + 0.3) + mat_glint(rf, world_pos, 48.0) * 0.35 + emission;
	a = clamp(0.25 + 0.55 * f + inner * inner * 0.2 + glint * 0.5 + edge * 0.25, 0.0, 1.0) * s.a;
#elif defined(FX_LIQUID_CHROME)
	// A mirror over a surface that flows: the normal is tilted by slow noise that turns from one shape into another
	// and back, so the studio's horizon and sky bend and slide across it like liquid metal. Tinted by the colour,
	// white at grazing angles (fresnel); a soft highlight and the screen's glint move with the flow. (The noises
	// stay put and are blended by the clock: a texture moved slower than its filter's precision steps instead of
	// gliding, a step a frame.)
	float ph = FX_TAU * FX_TIME * 0.05 * fx_speed01() + fx_seed * FX_TAU;
	vec3 q = local_pos / max(fx_scale, 0.05) + fx_seed * 7.0;
	vec2 w1 = fx_noise3x2(q) - 0.5;
	vec2 w2 = fx_noise3x2(q * 1.3 + vec3(5.2, 1.7, 3.1)) - 0.5;
	vec2 w = w1 * cos(ph) + w2 * sin(ph);
	vec3 d = vec3(w.x, 0.5 * (w.x + w.y), w.y);
	vec3 n = normalize(s.n + 0.75 * (d - s.n * dot(d, s.n)));
	vec3 rf = reflect(-s.v, n);
	float f = pow(1.0 - clamp(dot(n, s.v), 0.0, 1.0), 5.0);
	vec3 tint = mix(fx_color, vec3(1.0), f);
	col = tint * fx_studio(rf, s.light) * 0.75 + mat_key(rf, 40.0) * 0.35 * (s.light + 0.3)
			+ mat_glint(rf, world_pos, 48.0) * 0.4 + emission;
#elif defined(FX_FROSTED_GLASS)
	// Glass ground rough: light passing through scatters, so it looks milky, more so where the surface turns away
	// and you look through more of it; the studio's reflection is blurred to a soft sheen and the screen's light a
	// broad glow. A soft grain, which fades out before it is finer than a pixel. The colour tints the glass.
	float frost = clamp(fx_param, 0.0, 1.0);
	float rim = pow(1.0 - s.facing, 2.2);
	vec2 p = mat_plane(local_pos, 0.5);
	float grain = mix(fx_fbm2(p * 3.0 + fx_seed).r - 0.5, 0.0, fx_fine2(p * 3.0 * 32.0));
	vec3 env = fx_studio(r, s.light);
	env = mix(env, vec3(dot(env, vec3(0.333))), 0.6);
	vec3 tint = mix(s.base, vec3(1.0), 0.25);
	vec3 milk = tint * (s.light * (0.32 + 0.25 * frost) + 0.06) * (1.0 + 0.5 * rim);
	col = milk * (1.0 + 0.18 * grain) + env * (0.04 + 0.3 * rim) + mat_glint(r, world_pos, 6.0) * 0.12 * tint
			+ emission;
	a = clamp(mix(0.3, 0.7, frost) + 0.3 * rim + 0.05 * grain, 0.0, 1.0) * s.a;
#endif
	ALBEDO = fx_print(col + fx_dither(FRAGCOORD.xy), UV);
#if defined(FX_CRYSTAL) || defined(FX_FROSTED_GLASS)
	ALPHA = a;
#endif
}
