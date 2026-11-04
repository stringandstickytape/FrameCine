// Shared by the effect library's shaders (docs/effects.md; scripts/effects/effect_library.gd sets every uniform here
// from an effect's options). The base is room_effect.gdshader's, so a part looks the same until its effect adds to
// it: colour x picture x (room light, or 1 when self-lit) + emission.
//
// Noise comes from two small textures (app/textures/fx, made by scripts/effects/make_noise.gd) instead of arithmetic:
// fx_noise3 is 3D value noise in one tap, fx_fbm2 four octaves in one mipmapped tap, fx_cells2 cells (Worley) in
// one. Keep spatial and temporal frequencies low: there is no MSAA on the headset, so anything finer than a few
// pixels shimmers; fade fine detail out by its derivative (fx_fine) rather than drawing it.
//
// Photosensitivity ceiling, enforced here as well as in the catalogue and its tests: no brightness change faster than
// 3 Hz (FX_MAX_HZ) and no swing larger than FX_MAX_SWING of the surface's own brightness. A pattern that moves may
// change a pixel by more than the swing only slowly: no steeper than a 3 Hz wave of the full swing (docs/effects.md,
// "Photosensitivity"). fx_speed is 0..1 everywhere; each effect turns it into its own slow rate, and the clamp here
// means a bad number cannot make anything faster.

uniform vec3 albedo : source_color = vec3(1.0);
uniform float alpha = 1.0;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_texture = false;
// A library material under the effect (a layered look): its picture repeats every uv_scale of the part's UV, or,
// compiled with FX_BASE_TRIPLANAR, every base_scale metres of the part's own space on all three axes.
uniform vec2 uv_scale = vec2(1.0);
uniform float base_scale = 1.0;
uniform vec3 emission : source_color = vec3(0.0);
uniform bool self_lit = false;
// An effect's colours, strength, speed (0..1), size, rate (Hz), swing (0..FX_MAX_SWING), amount, a per-part seed,
// one more number (0..1) and a choice (an enum's index). What each means is the effect's (its catalogue entry).
uniform vec3 fx_color : source_color = vec3(1.0);
uniform vec3 fx_color2 : source_color = vec3(0.0);
uniform float fx_strength = 1.0;
uniform float fx_speed = 0.3;
uniform float fx_scale = 1.0;
uniform float fx_rate = 0.5;
uniform float fx_depth = 0.25;
uniform float fx_amount = 0.0;
uniform float fx_seed = 0.0;
uniform float fx_param = 0.5;
uniform int fx_mode = 0;
// The film's loudness, smoothed and slew-limited (scripts/assistant/room_react.gd), 0..1.
uniform float react_level = 0.0;
uniform sampler2D fx_value_noise : filter_linear, repeat_enable;
uniform sampler2D fx_fbm : filter_linear_mipmap, repeat_enable;

#include "res://shaders/env_spill.gdshaderinc"

const float FX_MAX_HZ = 3.0;
const float FX_MAX_SWING = 0.4;
const float FX_TAU = 6.2831853;

// The clock. Tests compile a variant with FX_TEST_CLOCK to step it by hand and read the brightness back.
#if defined(FX_TEST_CLOCK)
uniform float fx_test_time = 0.0;
#define FX_TIME fx_test_time
#else
#define FX_TIME TIME
#endif

// fx_speed and fx_strength as the effects use them: clamped, whatever the material was given.
float fx_speed01() {
	return clamp(fx_speed, 0.0, 1.0);
}

float fx_rate_hz() {
	return clamp(fx_rate, 0.0, FX_MAX_HZ);
}

// A brightness factor 1 +- swing (wave -1..1); the swing never above FX_MAX_SWING.
float fx_swing(float wave, float depth) {
	return 1.0 + clamp(depth, 0.0, FX_MAX_SWING) * clamp(wave, -1.0, 1.0);
}

// -1..1, irregular, like a flame: four sines at the rate and below it (never above FX_MAX_HZ), weights summing to 1.
float fx_wander(float t, float rate, float seed) {
	float r = min(rate, FX_MAX_HZ);
	float s = seed * FX_TAU;
	return 0.35 * sin(FX_TAU * r * t + s) + 0.3 * sin(FX_TAU * r * 0.71 * t + s * 1.7)
			+ 0.2 * sin(FX_TAU * r * 0.43 * t + s * 2.3) + 0.15 * sin(FX_TAU * r * 0.23 * t + s * 3.1);
}

float fx_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// 3D value noise, 0..1, in one texture tap: the lattice's z slices are moved copies of one 64 x 64 random field
// (make_noise.gd), R one slice and G the next. Two independent noises: .x from R/G, .y from B/A.
vec2 fx_noise3x2(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec2 uv = i.xy + vec2(37.0, 17.0) * i.z + f.xy;
	vec4 t = textureLod(fx_value_noise, (uv + 0.5) / 64.0, 0.0);
	return vec2(mix(t.r, t.g, f.z), mix(t.b, t.a, f.z));
}

float fx_noise3(vec3 p) {
	return fx_noise3x2(p).x;
}

// Four octaves of smooth noise baked into one tiling texture: .r and .g two fractal noises, .b cell distance
// (Worley F1), .a cell borders (F2 - F1). One unit of p is one repeat of the texture (8 cells, 4..32 noise cells).
// Mipmapped, so it fades to its average instead of shimmering when small on screen.
vec4 fx_fbm2(vec2 p) {
	return texture(fx_fbm, p);
}

// How much finer than a pixel a pattern is, 0 (fine to draw) .. 1 (far too fine: draw its average instead).
// x: the pattern's coordinate, in its own cycles.
float fx_fine(float x) {
	return smoothstep(0.35, 0.9, fwidth(x));
}

float fx_fine2(vec2 x) {
	vec2 w = fwidth(x);
	return smoothstep(0.35, 0.9, max(w.x, w.y));
}

// A line of the given half width (in x's units) at x = 0, antialiased over a pixel, faded to its average when
// too thin to draw.
float fx_line(float x, float half_width) {
	float w = max(fwidth(x), 1e-5);
	float l = 1.0 - smoothstep(half_width - w, half_width + w, abs(x));
	return mix(l, half_width * 2.0, smoothstep(half_width * 1.5, half_width * 4.0, w));
}

// The picture under the effect: by UV (uv_scale repeats), or by the part's own space on three axes.
vec4 fx_picture(vec2 uv, vec3 local_p, vec3 local_n) {
	if (!use_texture) {
		return vec4(1.0);
	}
#if defined(FX_BASE_TRIPLANAR)
	vec3 w = pow(abs(local_n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 1e-4);
	vec3 q = local_p / max(base_scale, 0.01);
	return texture(albedo_texture, q.zy) * w.x + texture(albedo_texture, q.xz) * w.y
			+ texture(albedo_texture, q.xy) * w.z;
#else
	return texture(albedo_texture, uv * uv_scale);
#endif
}

// Everything an effect starts from. light is the room's (ambient and the screen's spill) or 1 when self-lit; lit is
// what the surface shows without the effect (room_effect.gdshader's base).
struct FxSurface {
	vec3 base;
	vec3 light;
	vec3 lit;
	vec3 n;
	vec3 v;
	float facing;
	float a;
	vec4 tex;
};

FxSurface fx_surface(vec2 uv, vec3 world_p, vec3 world_n, vec3 local_p, vec3 local_n, bool front, vec3 camera) {
	FxSurface s;
	s.tex = fx_picture(uv, local_p, local_n);
	s.base = albedo * s.tex.rgb;
	s.light = self_lit ? vec3(1.0) : room_light_at(world_p, 1.0);
	s.n = normalize(world_n) * (front ? 1.0 : -1.0);
	s.v = normalize(camera - world_p);
	s.facing = clamp(dot(s.n, s.v), 0.0, 1.0);
	s.lit = s.base * s.light + emission;
	s.a = alpha * s.tex.a;
	return s;
}

// Fresnel-like rim: 0 facing you, 1 edge-on.
float fx_rim(float facing, float power) {
	return pow(1.0 - facing, power);
}

// A made-up surroundings for reflections (as room_effect.gdshader's metal): a dim floor, a bright soft band at the
// horizon, a sky brightening overhead, tinted by the room's light.
vec3 fx_studio(vec3 r, vec3 light) {
	vec3 ground = mix(vec3(0.05), vec3(0.16), smoothstep(-1.0, -0.05, r.y));
	vec3 sky = mix(vec3(0.42), vec3(0.95), smoothstep(0.05, 0.95, r.y));
	vec3 around = mix(ground, sky, smoothstep(-0.06, 0.05, r.y));
	around += vec3(0.5) * exp(-pow((r.y - 0.02) / 0.1, 2.0));
	return around * clamp(0.55 + 0.9 * light, vec3(0.45), vec3(1.6));
}

// The film's picture colour nearest p, as linear light (a typical film about 1), for screen-reactive effects.
vec3 fx_film_colour(vec3 p) {
	float u = clamp(0.5 + dot(p - screen_center, screen_axis), 0.125, 0.875);
	vec3 c = spill_srgb_to_linear(textureLod(screen_thumb, vec2(u, 0.5), 0.0).rgb);
	return min(c / SPILL_REFERENCE, vec3(SPILL_MAX));
}

// Under half a level of 8-bit noise, fixed (it does not flicker), so slow dark gradients do not band.
vec3 fx_dither(vec2 frag) {
	return vec3((fx_hash(vec3(frag, 61.0)) - 0.5) / 255.0);
}

// The last step of an effect's colour. Compiled with FX_PRINT (an effect on our controller model's shell,
// scripts/xr/controller_look.gd), the legends printed in the model's texture go over it in their ink; otherwise
// nothing. The energy, nature and materials shaders call it.
#if defined(FX_PRINT)
#include "res://shaders/controller_print.gdshaderinc"
vec3 fx_print(vec3 col, vec2 uv) {
	return controller_print(col, uv);
}
#else
vec3 fx_print(vec3 col, vec2 uv) {
	return col;
}
#endif
