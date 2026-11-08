// The Screening room 1962's garden at night (scripts/env/systems/kit/screening_1962.gd; docs/environments.md, "Room:
// Screening room 1962"): the terrace, the pool and its coping, the planters and their agaves, the palms down the
// slope, the low wall at the terrace's edge and the eaves over the glass, in one mesh and one draw. Since 2026-11-08.
// Unshaded: the light was worked out as the garden was built and rides in the vertex colours (the night's cool light
// from above, the room's warm light through the glass, the pool's glow by its distance), so a fragment is a few
// multiplies, and two texture reads where the pool's light ripples. Nothing moves but the water's light.
//   UV2.x      0 a surface; 1 the pool's water (and its walls under it)
//   COLOR.rgb  the surface's colour as lit (linear); the water's own glow
//   COLOR.a    how much of the pool's light reaches a surface (its ripples ride on it)
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled, fog_disabled;

uniform sampler2D caustic_map : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 pool_colour : source_color = vec3(0.3, 0.85, 0.9);
// The pool's lamps (the kit's glow: lower in the film).
uniform float pool_level = 1.0;
// The water's clock (seconds times the kit's water_motion: the Motion setting slows it).
uniform float water_clock = 0.0;
uniform float ripple_scale = 0.8;
// The water's glow over its vertex colours (they stay under 1: its lamps' grading rides in them).
uniform float water_gain = 3.2;
// The night's sky in the water at a glancing look (linear).
uniform vec3 sky_glint : source_color = vec3(0.012, 0.016, 0.03);

varying vec3 world_pos;
varying float kind;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	kind = UV2.x;
}

float web(vec2 p) {
	float t = water_clock * 0.05;
	vec2 q = p / (ripple_scale * 4.0);
	float a = 1.0 - smoothstep(0.0, 0.16, texture(caustic_map, q + vec2(t, t * 0.37)).r);
	float b = 1.0 - smoothstep(0.0, 0.16, texture(caustic_map, q * 1.31 + vec2(-t * 0.71, t * 0.53) + 0.37).r);
	return a * b + 0.25 * (a + b);
}

void fragment() {
	if (kind > 0.5) {
		// The water: its own glow (brighter by its lamps), the web of light on the pool's floor seen through it, and
		// at a glancing look more of the night's sky than of the water.
		float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
		vec3 water = COLOR.rgb * water_gain * pool_level * (0.7 + 0.8 * web(world_pos.xz));
		ALBEDO = mix(sky_glint, water, 0.4 + 0.6 * sqrt(facing));
	} else {
		float w = COLOR.a > 0.002 ? web(world_pos.xz + world_pos.y * 0.7) : 0.0;
		ALBEDO = COLOR.rgb + pool_colour * COLOR.a * pool_level * (0.2 + 1.2 * w);
	}
}
