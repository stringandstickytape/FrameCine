// A projector's beam in a built-in room (the cinema's, environments/cinema.gd; as scripts/env/projector.gd's): a
// transparent cone drawn additively, brightest near the lens and fading out before the screen, soft at its edges.
// Each side is weighted by how directly it is seen (a cheap stand-in for the length of the path through the light).
// It shows more as the house lights go down (env_light over house_reference: faint at 1, full at the playing level)
// and takes the picture's colour and brightness with the bias light (env_spill.gdshaderinc's spill_tint).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

uniform vec3 colour : source_color = vec3(1.0, 0.95, 0.85);
uniform float strength = 0.0035;
uniform float house_reference = 0.05;

#include "res://shaders/env_spill.gdshaderinc"

varying float along;
varying vec2 side;
varying vec3 world_pos;

void vertex() {
	along = UV.y;
	side = UV2;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float level = clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	float dark = clamp(1.25 - level, 0.2, 1.0);
	float edge = smoothstep(0.0, 0.3, min(side.x, 1.0 - side.x));
	float thick = abs(dot(NORMAL, VIEW));
	float a = strength * dark * (1.0 - smoothstep(0.45, 0.95, along)) * (0.35 + 0.65 * (1.0 - along)) * edge
			* thick * thick;
	// One colour for the whole beam: the picture's middle (its mean, near enough).
	ALBEDO = colour * spill_tint(screen_center) * a;
}
