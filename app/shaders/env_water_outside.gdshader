// The water all round a glass dome (scripts/env/systems/dome_hall.gd, outside "water"): a big sphere seen from inside,
// coloured by where the eye looks through it (env_water.gdshaderinc water_colour): the deep below, the lit water
// above and, nearer the surface, Snell's window and the shafts. Like a lamp it gives light and takes none (albedo
// black, all emission), so a lightmap bake takes its glow as light from outside (bake_pass: the plain gradient).
shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled, ambient_light_disabled, fog_disabled;

#include "res://shaders/env_water.gdshaderinc"

uniform float energy = 1.0;
uniform bool bake_pass = false;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 dir = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec3 c = bake_pass ? mix(water_deep, water_top, smoothstep(-0.55, 0.8, dir.y)) : water_colour(dir);
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	EMISSION = c * energy;
}
