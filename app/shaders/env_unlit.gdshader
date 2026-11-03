// Environment surfaces: unlit, no textures. Brightness = the room's ambient level (global env_light) plus a cheap
// fall-off "spill" from the screen (global screen_center / screen_glow), so walls near the screen read as lit without
// any light, shadow or GI pass. One ALU-only fragment shader for every surface.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled;

uniform vec3 albedo : source_color = vec3(0.3);
// How much this surface catches the screen's light (0 = none).
uniform float spill = 1.0;
// Darkens towards the floor, a fake ambient occlusion: brightness *= mix(1 - floor_darkening, 1, height / 3 m).
uniform float floor_darkening = 0.3;

// env_light, screen_center, screen_glow and the bias light's tint (ideas #29).
#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 light = room_light_at(world_pos, spill);
	light *= mix(1.0 - floor_darkening, 1.0, clamp(world_pos.y / 3.0, 0.0, 1.0));
	ALBEDO = albedo * light;
}
