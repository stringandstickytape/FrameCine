// The sea floor round a glass dome (scripts/env/systems/kit/seabed.gd, docs/environments.md "dome_hall"): the floor's
// banks and trench, rocks, coral, fronds, an old diving bell on its skid, a vent's chimney. Unshaded and never baked:
// the light is computed here, all of it the water's (env_water.gdshaderinc): the lit water's glow from above, the
// surface's light and its caustics when the water is shallow, the floodlights' pools, the film's light through the
// glass. Then the murk takes it into the water's own colour with distance, so the far banks melt into the blue.
// Per vertex: COLOR the surface's own colour, UV2.x how much it sways (0 rooted, 1 a frond's tip), UV.x its phase.
// Fronds sway slowly (a swing every 7 to 11 s, at most `sway` metres at the tip), scaled by the Motion setting.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

#include "res://shaders/env_water.gdshaderinc"

uniform float sway = 0.35;
// How much of the lit water's glow reaches a surface facing up (and a little round the sides): the light falling
// from above is several times the water's own glow seen sideways.
uniform float water_glow = 5.0;

varying vec3 world_pos;
varying vec3 world_n;
varying vec3 own;

void vertex() {
	float w = UV2.x;
	if (w > 0.0 && sway > 0.0) {
		float ph = UV.x * 6.2831853;
		float t = TIME * water_motion;
		vec2 off = vec2(sin(t * 0.71 + ph), cos(t * 0.57 + ph * 1.3)) * sway * w * w;
		off += vec2(sin(t * 1.9 + ph * 2.0 + VERTEX.y), 0.0) * 0.04 * w * water_motion;
		VERTEX.xz += off;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	own = COLOR.rgb;
}

void fragment() {
	vec3 n = normalize(world_n);
	// Fronds, fans and other thin parts are seen from both sides: a back is lit as a front.
	if (!FRONT_FACING) {
		n = -n;
	}
	float up = n.y * 0.5 + 0.5;
	vec3 light = water_top * water_glow * (0.25 + 1.4 * up * up);
	if (sun > 0.0) {
		float lit = max(n.y, 0.0);
		light += sun_colour * sun * lit * (0.3 + 1.6 * caustic(world_pos.xz));
	}
	light += flood_light(world_pos, n);
	light += film_light(world_pos) * 0.6;
	light += vec3(env_light) * 0.5;
	vec3 c = own * light;
	ALBEDO = in_water(c, world_pos, CAMERA_POSITION_WORLD);
}
