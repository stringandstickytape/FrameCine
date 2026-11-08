// A soft halo round a small light (the Athens rooftop's bulbs: scripts/env/systems/kit/athens_roof.gd): each quad's
// four corners sit at the light's centre and are spread here to face the eye, `size` metres across its radius; a
// round glow, brightest in the middle, added over what is behind. It dims with the house lights as the lamps do
// (follows_house). No depth write, never baked.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled,
		skip_vertex_transform;

#include "res://shaders/env_spill.gdshaderinc"

uniform vec3 colour : source_color = vec3(1.0, 0.7, 0.4);
uniform float energy = 1.0;
uniform float size = 0.15;
uniform float follows_house = 1.0;
uniform float house_reference = 0.05;

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// A little towards the eye, so the bulb's own globe never hides its glow.
	c.xyz *= max(1.0 - 0.06 / max(length(c.xyz), 0.1), 0.0);
	c.xy += (UV * 2.0 - 1.0) * size;
	VERTEX = c.xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float k = pow(max(1.0 - r, 0.0), 2.4);
	float level = clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	level *= level;
	ALBEDO = colour * energy * k * mix(1.0, level, follows_house);
}
