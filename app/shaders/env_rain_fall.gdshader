// Falling rain or snow (scripts/env/systems/weather.gd): the draw pass of the weather's GPU particles. Rain: a thin
// streak that stays upright and turns about its own vertical axis to face the eyes (a raindrop's motion blur). Snow:
// a soft round flake facing the eyes that sways a little as it falls (by its own phase, from INSTANCE_ID). Lit by the
// room and the film's spill, so the rain glints in the film's light and is near unseen in the dark. Blended with
// alpha (never multiplied: the Mobile renderer's luminance multiplier).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

uniform bool flake = false;
uniform vec3 colour : source_color = vec3(0.75, 0.8, 0.9);
uniform float opacity = 0.35;
// How much a surface catches the screen's light, and the least light it shows by.
uniform float catch_light = 0.7;
uniform float floor_light = 0.04;

#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	vec3 at = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	if (flake) {
		float phase = fract(float(INSTANCE_ID) * 0.618034) * 6.2831853;
		at.x += 0.12 * sin(TIME * 0.8 + phase + at.y * 0.9);
		at.z += 0.1 * cos(TIME * 0.6 + phase * 1.3 + at.y * 0.7);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sx,
				INV_VIEW_MATRIX[2] * sx, vec4(at, 1.0));
	} else {
		// Upright, turned about Y to face the eyes.
		vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz) + vec3(1e-5, 0.0, 0.0));
		vec3 front = normalize(cross(side, vec3(0.0, 1.0, 0.0)));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side * sx, 0.0), vec4(0.0, sy, 0.0, 0.0), vec4(front * sx, 0.0),
				vec4(at, 1.0));
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	world_pos = at;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float shape;
	if (flake) {
		shape = 1.0 - smoothstep(0.2, 1.0, length(c));
	} else {
		// Thin across, fading towards both ends (brightest a little below the middle: the drop's head).
		shape = (1.0 - smoothstep(0.0, 1.0, abs(c.x))) * (1.0 - smoothstep(0.1, 1.0, abs(c.y + 0.25)));
	}
	vec3 light = min(room_light_at(world_pos, catch_light) * 1.6 + vec3(floor_light), vec3(1.5));
	ALBEDO = colour * light;
	ALPHA = clamp(opacity * shape * COLOR.a, 0.0, 1.0);
}
