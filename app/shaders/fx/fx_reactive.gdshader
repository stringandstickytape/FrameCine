// The effect library's reactive effects (scripts/effects/catalogue/reactive.gd, docs/effects.md): surfaces that
// follow the film. Compiled once per effect with FX_<NAME> defined. The film's loudness comes in as react_level
// (scripts/assistant/room_react.gd: low-passed and slew-limited, never steeper than a full-range 3 Hz sine); its
// colours from the bias light's 4 x 2 copy of the picture (env_spill.gdshaderinc, low-passed over 0.25 s).
//
// Photosensitivity: the loudness moves a glow by at most the swing (fx_depth, <= FX_MAX_SWING) around its middle;
// the patterns drift slowly enough that no pixel changes faster than a 3 Hz wave of the full swing.
shader_type spatial;
render_mode unshaded, shadows_disabled, specular_disabled, cull_back;

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

void fragment() {
	FxSurface s = fx_surface(UV, world_pos, world_normal, local_pos, local_normal, FRONT_FACING,
			CAMERA_POSITION_WORLD);
	vec3 col = s.lit;
	float t = FX_TIME;
	float level = clamp(react_level, 0.0, 1.0);
#if defined(FX_REACT_SOUND)
	// A light inside that rises with the film's sound, soft rings spreading from the part's middle at half a ring a
	// second, deeper when it is loud. The whole stays within 1 +- swing of its quiet middle.
	float rings = sin(FX_TAU * (length(local_pos) / max(fx_scale, 0.05) - 0.5 * t));
	float wave = (2.0 * level - 1.0) * 0.75 + 0.25 * level * rings;
	col += fx_color * fx_strength * (0.35 + 0.65 * s.facing) * fx_swing(wave, fx_depth);
#elif defined(FX_REACT_SCREEN)
	// The film's colours as a sheen: each side of the part takes the colour of the picture's side nearest it,
	// strongest where the surface turns away (as light grazing it), tinted by the effect's colour.
	vec3 film = fx_film_colour(world_pos);
	float sheen = mix(0.25, 1.0, fx_rim(s.facing, 2.0));
	col = mix(col, s.base * film * s.light, 0.35) + film * fx_color * fx_strength * 0.25 * sheen;
#elif defined(FX_REACT_CAUSTICS)
	// Light as under water: the cell borders of two layers of cells drifting apart, where both are thin. Loud
	// passages brighten it within the swing.
	vec2 p = (local_pos.xz + local_pos.y * vec2(0.37, -0.23)) / max(fx_scale, 0.05);
	float v = 0.012 * fx_speed01();
	float c1 = fx_fbm2(p * 0.5 + vec2(t * v, t * v * 0.6) + fx_seed).a;
	float c2 = fx_fbm2(p * 0.43 + vec2(-t * v * 0.7, t * v) + 0.5).a;
	float caustic = (1.0 - smoothstep(0.0, 0.6, c1)) * (1.0 - smoothstep(0.0, 0.6, c2));
	caustic = mix(caustic, 0.12, fx_fine2(p * 4.0));
	col += fx_color * fx_strength * (0.15 + caustic) * fx_swing(2.0 * level - 1.0, fx_depth);
#endif
	ALBEDO = col;
}
