// Material effects for the assistant's rooms (scripts/assistant/assistant_room.gd, docs/assistant.md "Effects"): the
// app's own shaders; the assistant names one and gives bounded numbers. Compiled once per effect with FX_<NAME>
// defined. The base is env_unlit_tex.gdshader's: colour x picture x (room light, or 1 when self-lit) + emission.
//
// Photosensitivity ceiling, enforced here as well as in the schema: no brightness change faster than 3 Hz
// (FX_MAX_HZ) and no swing larger than FX_MAX_SWING of the surface's own brightness. Flicker is several slow sines
// summed (all at or under the rate), so it wanders like a flame instead of strobing.
shader_type spatial;
render_mode unshaded, shadows_disabled, specular_disabled;
#if defined(FX_HOLOGRAM)
// Additive, both sides: the far faces show through the near ones, as light would.
render_mode blend_add, cull_disabled, depth_draw_never;
#elif defined(FX_GLASS)
render_mode cull_back, depth_draw_never;
#else
render_mode cull_back;
#endif

uniform vec3 albedo : source_color = vec3(1.0);
uniform float alpha = 1.0;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_texture = false;
uniform vec3 emission : source_color = vec3(0.0);
uniform bool self_lit = false;
// The effect's colour, strength, rate (Hz), swing (0..FX_MAX_SWING), amount (dissolve), and a per-part seed.
uniform vec3 fx_color : source_color = vec3(1.0);
uniform float fx_strength = 1.0;
uniform float fx_rate = 0.5;
uniform float fx_depth = 0.25;
uniform float fx_amount = 0.0;
uniform float fx_seed = 0.0;
// The film's loudness or brightness, smoothed (screen-reactive effects), 0..1.
uniform float react_level = 0.0;

#include "res://shaders/env_spill.gdshaderinc"

const float FX_MAX_HZ = 3.0;
const float FX_MAX_SWING = 0.4;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 local_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	local_pos = VERTEX;
}

float fx_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Smooth value noise, 0..1.
float fx_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(fx_hash(i), fx_hash(i + vec3(1, 0, 0)), f.x),
			mix(fx_hash(i + vec3(0, 1, 0)), fx_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(fx_hash(i + vec3(0, 0, 1)), fx_hash(i + vec3(1, 0, 1)), f.x),
			mix(fx_hash(i + vec3(0, 1, 1)), fx_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// -1..1, irregular: four sines at the rate and below it (never above FX_MAX_HZ), weights summing to 1.
float fx_flicker(float t, float rate) {
	float r = min(rate, FX_MAX_HZ);
	float s = fx_seed * 6.2831853;
	return 0.35 * sin(6.2831853 * r * t + s) + 0.3 * sin(6.2831853 * r * 0.71 * t + s * 1.7)
			+ 0.2 * sin(6.2831853 * r * 0.43 * t + s * 2.3) + 0.15 * sin(6.2831853 * r * 0.23 * t + s * 3.1);
}

// A brightness factor 1 +- swing that changes no faster than FX_MAX_HZ.
float fx_swing(float wave) {
	return 1.0 + clamp(fx_depth, 0.0, FX_MAX_SWING) * wave;
}

void fragment() {
	vec4 tex = use_texture ? texture(albedo_texture, UV) : vec4(1.0);
	vec3 base = albedo * tex.rgb;
	vec3 light = self_lit ? vec3(1.0) : room_light_at(world_pos, 1.0);
	vec3 n = normalize(world_normal) * (FRONT_FACING ? 1.0 : -1.0);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float facing = clamp(dot(n, v), 0.0, 1.0);
	vec3 col = base * light + emission;
	float a = alpha * tex.a;
	float t = TIME;
#if defined(FX_RIM_GLOW)
	// A soft fresnel rim: strongest where the surface turns away, falling off smoothly towards its middle.
	col += fx_color * fx_strength * pow(1.0 - facing, 2.5);
#elif defined(FX_PULSE)
	// A light inside: brightest where the surface faces you, softer towards the rim.
	float s = sin(6.2831853 * min(fx_rate, FX_MAX_HZ) * t + fx_seed * 6.2831853);
	col = base * light + (emission + fx_color * fx_strength * (0.35 + 0.65 * facing)) * fx_swing(s);
#elif defined(FX_FLICKER)
	col = base * light + (emission + fx_color * fx_strength * (0.35 + 0.65 * facing)) * fx_swing(fx_flicker(t, fx_rate));
#elif defined(FX_HOLOGRAM)
	// Fine scanlines drifting slowly up, brighter at the edges, a faint flicker under the ceiling.
	// Lines too fine for the pixels fade to their average instead of shimmering (moire).
	float ly = world_pos.y * 90.0 - t * 0.35;
	float lines = 0.6 + 0.4 * smoothstep(0.2, 0.8, abs(sin(3.14159265 * ly)));
	lines = mix(lines, 0.8, smoothstep(0.25, 0.6, fwidth(ly)));
	float edge = mix(0.1, 0.8, pow(1.0 - facing, 1.5));
	float lum = use_texture ? dot(tex.rgb, vec3(0.3, 0.59, 0.11)) : 1.0;
	col = fx_color * fx_strength * lines * edge * (0.4 + 0.6 * lum) * (1.0 + 0.08 * fx_flicker(t, 2.0));
	a = 1.0;
#elif defined(FX_GLASS)
	// Mostly clear in the middle, more reflective at grazing angles (fresnel), tinted by the colour.
	float f = 0.04 + 0.96 * pow(1.0 - facing, 4.0);
	vec3 r = reflect(-v, n);
	vec3 around = mix(light * 0.15, light * 1.2 + vec3(0.08), smoothstep(-0.3, 0.7, r.y));
	float glint = pow(max(dot(r, normalize(screen_center - world_pos)), 0.0), 64.0) * screen_glow;
	// A soft highlight from above and in front, where a room's light would catch a polished curve.
	float key = pow(max(dot(r, normalize(vec3(-0.35, 0.8, 0.5))), 0.0), 90.0);
	col = base * light * 0.3 + around * f + (glint * spill_tint(world_pos) + key * (light + vec3(0.3))) + emission;
	a = clamp(mix(0.1, 0.8, f) * alpha + key * 0.8, 0.0, 1.0);
#elif defined(FX_METAL)
	// The rooms have no lights to reflect, so a metal reflects a made-up surroundings, as a studio does: a dim
	// floor, a bright soft band at the horizon, a sky growing brighter overhead, faint panels around, all tinted by
	// the room's own light (ambient and the screen's colour). The metal's colour tints the reflection (brass,
	// copper; white for chrome), turning white at grazing angles (fresnel). A broad soft highlight and a sharp one
	// from a key light above and in front, and the screen's glint.
	vec3 r = reflect(-v, n);
	float az = atan(r.x, r.z);
	vec3 ground = mix(vec3(0.05), vec3(0.16), smoothstep(-1.0, -0.05, r.y));
	vec3 sky = mix(vec3(0.42), vec3(0.95), smoothstep(0.05, 0.95, r.y)) * (1.0 + 0.1 * sin(az * 3.0 + 0.7) * (1.0 - abs(r.y)));
	vec3 around = mix(ground, sky, smoothstep(-0.06, 0.05, r.y));
	around += vec3(0.5) * exp(-pow((r.y - 0.02) / 0.1, 2.0));
	vec3 tint = clamp(0.55 + 0.9 * light, vec3(0.45), vec3(1.6));
	float f = pow(1.0 - facing, 5.0);
	vec3 refl = mix(base, vec3(1.0), f);
	float k = max(dot(r, normalize(vec3(-0.45, 0.75, 0.5))), 0.0);
	float shine = 0.35 * pow(k, 10.0) + 1.6 * pow(k, 220.0);
	float glint = pow(max(dot(r, normalize(screen_center - world_pos)), 0.0), 96.0) * screen_glow;
	col = around * tint * refl + fx_strength * (shine * mix(base, vec3(1.0), 0.6) * tint
			+ glint * spill_tint(world_pos)) + emission;
#elif defined(FX_TOON)
	// Cel shading: three hard-edged tones of the colour from a fixed key light above and in front (edges
	// antialiased over a pixel), at the room's brightness; the outline is a second pass (room_outline.gdshader).
	float ndl = dot(n, normalize(vec3(-0.45, 0.75, 0.5)));
	float aa = max(fwidth(ndl), 1e-4);
	float tone = mix(0.42, 0.7, smoothstep(-0.05 - aa, -0.05 + aa, ndl));
	tone = mix(tone, 1.0, smoothstep(0.45 - aa, 0.45 + aa, ndl));
	float level = clamp(dot(light, vec3(0.333)) * 1.4, 0.55, 1.25);
	col = base * tone * level + emission;
#elif defined(FX_DISSOLVE)
	// Eaten away by noise as amount goes 0 -> 1, with a glowing edge.
	float d = fx_noise(local_pos * 6.0 + fx_seed * 13.0) * 0.75 + fx_noise(local_pos * 17.0) * 0.25;
	float cut = d - clamp(fx_amount, 0.0, 1.0) * 1.02;
	col += fx_color * fx_strength * (1.0 - smoothstep(0.0, 0.06, cut));
	a = cut + 0.5;
#endif
	ALBEDO = col;
#if defined(FX_DISSOLVE)
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#elif defined(FX_HOLOGRAM) || defined(FX_GLASS)
	ALPHA = a;
#endif
}
