// Light sources in a built-in room lit for real (the cinema, environments/cinema.gd): lamp shades, ceiling cans,
// step lights, exit signs, the projection booth's window. They give light and take none: the colour is all emission
// (the albedo black), so a lightmap bake (LightmapGI) takes them as emitters and nothing lights them up.
//   follows_house   0: a constant light (exit signs, step lights); 1: dims with the house lights as the room's
//                   surfaces do (env_light over house_reference, room_material.gdshaderinc HOUSE)
//   picture         a texture's colours times colour (a sign's lettering, the booth's window)
//   bake_pass       the lightmapper's view: as designed, house level 1
shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled, ambient_light_disabled;

uniform vec3 colour : source_color = vec3(1.0);
uniform float energy = 1.0;
uniform float follows_house = 0.0;
uniform float house_reference = 0.05;
uniform sampler2D picture : source_color, filter_linear;
uniform bool use_picture = false;
uniform bool bake_pass = false;

// env_light (the room's level).
#include "res://shaders/env_spill.gdshaderinc"

void fragment() {
	float level = bake_pass ? 1.0 : clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	level *= level;
	vec3 c = colour;
	if (use_picture) {
		c *= texture(picture, UV).rgb;
	}
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	EMISSION = c * energy * mix(1.0, level, follows_house);
}
