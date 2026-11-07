// Breath fog in a cold room (scripts/env/systems/atmosphere.gd): the particles of one puff from under the viewer's
// nose, each a soft, faintly curdled disc facing the eyes. The particles' colour ramp gives the fade in and out
// (COLOR.a); opacity is the breath parameter's. Lit by the room and the film's spill, so it shows in the film's light
// and not in the dark. Blended with alpha (never multiplied: the Mobile renderer's luminance multiplier).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

uniform vec3 colour : source_color = vec3(0.9, 0.93, 1.0);
uniform float opacity = 0.12;

#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;
varying vec4 tint;

void vertex() {
	// A particle billboard: the particle's place and size, the camera's axes.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	world_pos = MODEL_MATRIX[3].xyz;
	tint = COLOR;
}

float breath_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	float wisp = 0.75 + 0.25 * sin(c.x * 7.0 + TIME * 0.9 + world_pos.x * 13.0) * sin(c.y * 6.0 - TIME * 0.7);
	float disc = (1.0 - smoothstep(0.15, 1.0, r)) * wisp;
	vec3 light = min(room_light_at(world_pos, 0.8) * 1.5 + vec3(0.12), vec3(1.2));
	ALBEDO = colour * light;
	ALPHA = clamp(opacity * tint.a * disc + (breath_hash(FRAGCOORD.xy) - 0.5) / 255.0, 0.0, 1.0);
}
