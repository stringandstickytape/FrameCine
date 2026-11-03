// The screen_glow widget (scripts/assistant/assistant_room.gd): the part glows in the picture's colour (the bias
// light's spill), and, with "react", shimmers or ripples with the film's brightness (REACT_BRIGHTNESS: the bias
// light's smoothed 4 x 2 copy of the picture, read here on the GPU) or loudness (REACT_LOUDNESS: react_level, set
// by scripts/assistant/room_react.gd).
//
// Photosensitivity ceiling: the brightness swings by at most MAX_SWING (amount, clamped) and changes no faster than
// 3 Hz: the picture's copy is low-passed (0.25 s), the loudness low-passed and slew-limited, the shimmer drifts at
// about 1 Hz and the ripple's rings pass at 0.8 Hz.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled;

uniform vec3 albedo : source_color = vec3(1.0);
uniform float strength = 1.0;
uniform float amount = 0.25;
uniform float react_level = 0.0;

#include "res://shaders/env_spill.gdshaderinc"

const float MAX_SWING = 0.4;

varying vec3 world_pos;
varying vec3 local_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_pos = VERTEX;
}

float glow_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float glow_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(glow_hash(i), glow_hash(i + vec3(1, 0, 0)), f.x),
			mix(glow_hash(i + vec3(0, 1, 0)), glow_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(glow_hash(i + vec3(0, 0, 1)), glow_hash(i + vec3(1, 0, 1)), f.x),
			mix(glow_hash(i + vec3(0, 1, 1)), glow_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 glow = albedo * spill_tint(world_pos) * strength;
#if defined(REACT_BRIGHTNESS) || defined(REACT_LOUDNESS)
#if defined(REACT_BRIGHTNESS)
	// The picture's mean (two linear taps cover the 8 cells), as linear light; a typical film about 0.4.
	vec3 c = 0.5 * (spill_srgb_to_linear(textureLod(screen_thumb, vec2(0.25, 0.5), 0.0).rgb)
			+ spill_srgb_to_linear(textureLod(screen_thumb, vec2(0.75, 0.5), 0.0).rgb));
	float level = clamp(dot(c, vec3(0.2126, 0.7152, 0.0722)) / (SPILL_REFERENCE * 2.5), 0.0, 1.0);
#else
	float level = clamp(react_level, 0.0, 1.0);
#endif
#if defined(STYLE_RIPPLE)
	// Soft rings spreading from the part's centre, 25 cm apart, passing at 0.8 Hz.
	float pattern = sin(6.2831853 * (length(local_pos) * 4.0 - TIME * 0.8));
#else
	// Light moving over the surface like water caustics, slowly: the ridges of two octaves of noise (bright where
	// the noise crosses its middle), drifting under one cell a second.
	float n = glow_noise(local_pos * 4.0 + vec3(0.0, TIME * 0.18, TIME * 0.12)) * 0.65
			+ glow_noise(local_pos * 9.0 - vec3(TIME * 0.14, 0.0, TIME * 0.1)) * 0.35;
	float pattern = pow(1.0 - abs(n * 2.0 - 1.0), 3.0) * 2.0 - 1.0;
#endif
	glow *= 1.0 + clamp(amount, 0.0, MAX_SWING) * level * (0.5 + 0.5 * pattern);
#endif
	ALBEDO = glow;
}
