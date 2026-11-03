// The effect library's transitions (scripts/effects/catalogue/transitions.gd, docs/effects.md): a part shown up to a
// moving plane, a part materialising band by band, and a soft glowing outline around a part. Compiled once per
// effect with FX_<NAME> defined.
//
// The wipe and the scan are still: their amount (0 hidden .. 1 whole) is set by whoever runs the transition, as the
// dissolve's is, and nothing here reads the clock. They are alpha-tested (cut out, not blended: no overdraw), so their
// cut edges are hard; a glowing line sits on every cut edge to carry it. Both sides are drawn, so the inside of a
// part shows (darker) where it is cut open. Their positions are in the part's own space, in metres: `size` (fx_scale)
// is the part's length along the axis, so amount runs the plane from one end to the other.
//
// The outline's glow is a second pass (fx_outline_glow.gdshader); this pass draws the surface unchanged.
shader_type spatial;
render_mode unshaded, shadows_disabled, specular_disabled;
#if defined(FX_WIPE) || defined(FX_SCAN_IN)
render_mode cull_disabled;
#else
render_mode cull_back;
#endif

#include "res://shaders/fx/fx_common.gdshaderinc"

#if defined(FX_SCAN_IN)
// Metres between the bands the part appears in.
uniform float scan_pitch = 0.03;
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

void fragment() {
	FxSurface s = fx_surface(UV, world_pos, world_normal, local_pos, local_normal, FRONT_FACING,
			CAMERA_POSITION_WORLD);
	vec3 col = s.lit;
	float a = 1.0;
	float amount = clamp(fx_amount, 0.0, 1.0);
	float size = max(fx_scale, 0.01);
#if defined(FX_WIPE)
	// Shown up to a plane across the part's axis (x, y or z), moving from its negative end to its positive one as
	// amount goes 0 -> 1. A glow just inside the cut, fading over 2.5 % of the size (1..8 cm), and a hot line on it.
	// The plane starts just before the part and ends well beyond it, so amount 0 hides it all and 1 shows it all,
	// without the glow.
	vec3 axis = fx_mode == 0 ? vec3(1.0, 0.0, 0.0) : (fx_mode == 1 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
	float h = dot(local_pos, axis);
	float depth = clamp(0.025 * size, 0.012, 0.08);
	float front = mix(-0.5 * size - 0.01, 0.5 * size + depth * 5.0, amount);
	float cut = front - h;
	float aa = max(fwidth(cut), 1e-5);
	float hot = 1.0 - smoothstep(aa, max(aa * 2.5, 0.004), cut);
	float glow = exp(-max(cut, 0.0) / depth) * 0.6 + hot;
	glow *= 1.0 - smoothstep(0.985, 1.0, amount);
	col = (FRONT_FACING ? col : col * 0.35) + fx_color * fx_strength * glow;
	a = 0.5 + cut * 1000.0;
#elif defined(FX_SCAN_IN)
	// Materialising from the bottom up (the part's own y): above the scan line only a faint grid (every four bands,
	// lines a pixel and a half wide, gone where they would be denser than a few pixels); below it, in a zone a quarter
	// of the part tall, the part appears as horizontal bands that thicken until they close, glowing in the effect's
	// colour like a hologram and fading to the surface as they settle; a bright line marks the scan. Amount 0: nothing;
	// the grid fades in over the first tenth; 1: the whole part, unchanged.
	float zone = max(0.25 * size, 0.04);
	float h = local_pos.y;
	float front = mix(-0.5 * size, 0.5 * size + zone, amount);
	float q = (front - h) / zone;
	float pitch = max(scan_pitch, 0.002);
	float b = h / pitch;
	float band = 0.5 * q - abs(fract(b) - 0.5);
	band = mix(band, q - 0.5, fx_fine(b));
	vec3 g = local_pos / (pitch * 4.0);
	vec3 gw = max(fwidth(g), vec3(1e-5));
	vec3 gpx = abs(fract(g + 0.5) - 0.5) / gw;
	vec3 keep = (1.0 - smoothstep(vec3(0.75), vec3(0.95), abs(normalize(local_normal))))
			* (1.0 - smoothstep(vec3(0.12), vec3(0.25), gw));
	float grid = max(max(step(gpx.x, 0.75) * keep.x, step(gpx.y, 0.75) * keep.y), step(gpx.z, 0.75) * keep.z);
	// On the near side only: the far side's grid seen through it would be a tangle.
	grid *= smoothstep(0.0, 0.1, amount) * (FRONT_FACING ? 1.0 : 0.0);
	float aa = max(fwidth(h), 1e-5);
	float scan = 1.0 - smoothstep(aa * 0.75, aa * 1.75, abs(h - front));
	scan *= 1.0 - smoothstep(0.97, 1.0, amount);
	scan *= step(0.001, amount);
	float settle = pow(clamp(1.0 - q, 0.0, 1.0), 1.5);
	vec3 holo = fx_color * fx_strength;
	vec3 solid = mix(FRONT_FACING ? col : col * 0.35, holo * 0.8 + col * 0.3, settle);
	bool shown = q >= 0.0 && band >= 0.0;
	col = shown ? solid : holo * 0.3;
	col += holo * scan * 1.5;
	a = (shown || grid > 0.5 || scan > 0.5) ? 1.0 : 0.0;
#elif defined(FX_SELECTION_OUTLINE)
	// The surface as it is: the glow is the second pass's.
#endif
	ALBEDO = col;
#if defined(FX_WIPE) || defined(FX_SCAN_IN)
	ALPHA = clamp(a, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
}
