// Specks in the water outside a glass dome (scripts/env/systems/kit/seabed.gd): marine snow sinking slowly and
// bubbles rising from a vent. No particle system: each speck is a quad of one mesh, and this shader moves it from
// TIME and its own seeds, so there is nothing to simulate and the count never changes. The quads face the main camera
// (both eyes alike). Marine snow is never inside the dome (`dome_*`: a speck that drifts inside it is not drawn); it
// glitters where the floodlights or the film's light catch it, and the murk swallows it with distance. In the abyss a
// few of the specks glow on their own now and then (`biolum`): a soft swell over about a second, each its own
// rhythm, far under the photosensitivity ceiling.
// Per vertex: VERTEX the speck's place when TIME is 0 (the room's frame), UV the quad's corner, UV2 and COLOR.r seeds.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

#include "res://shaders/env_water.gdshaderinc"

// 0 marine snow, 1 bubbles.
uniform int kind = 0;
uniform float size = 0.05;
uniform float opacity = 0.8;
// Snow: metres a second it sinks, the box it wraps round in (y), the dome it keeps out of (the room's frame).
uniform float fall = 0.035;
uniform vec2 y_range = vec2(-2.0, 20.0);
uniform vec3 dome_centre = vec3(0.0);
uniform float dome_radius = 9.0;
uniform float dome_drum = 1.3;
uniform float dome_height = 7.5;
// Bubbles: where they start (the room's frame), how high they rise, metres a second.
uniform vec3 vent = vec3(0.0);
uniform float rise_height = 16.0;
uniform float rise = 0.7;
uniform float biolum = 0.0;
uniform vec3 biolum_colour : source_color = vec3(0.3, 0.75, 1.0);
uniform float level = 1.0;

varying vec3 world_pos;
varying float fade;
varying float own_glow;

bool inside_dome(vec3 p) {
	vec3 q = p - dome_centre;
	float r = dome_radius + 0.25;
	float d = length(q.xz);
	if (q.y < -0.5 || d > r) {
		return false;
	}
	if (q.y <= dome_drum) {
		return true;
	}
	float h = dome_height + 0.25;
	float a = d / r;
	float b = (q.y - dome_drum) / h;
	return a * a + b * b < 1.0;
}

void vertex() {
	float t = TIME * water_motion;
	vec3 p = VERTEX;
	float s1 = UV2.x;
	float s2 = UV2.y;
	float s3 = COLOR.r;
	float grow = 1.0;
	fade = 1.0;
	own_glow = 0.0;
	if (kind == 0) {
		float span = y_range.y - y_range.x;
		float y = p.y - y_range.x - t * fall * (0.6 + 0.8 * s1);
		p.y = y_range.x + mod(y, span);
		p.x += 0.35 * sin(t * 0.11 + s2 * 6.2831853) + 0.12 * sin(t * 0.37 + s1 * 9.0);
		p.z += 0.35 * cos(t * 0.09 + s1 * 6.2831853) + 0.12 * cos(t * 0.29 + s2 * 7.0);
		// In and out at the wrap, so nothing pops.
		float u = (p.y - y_range.x) / span;
		fade = smoothstep(0.0, 0.04, u) * (1.0 - smoothstep(0.96, 1.0, u));
		if (inside_dome(p)) {
			fade = 0.0;
		}
		grow = 0.6 + 0.8 * s3;
		if (biolum > 0.0 && s3 > 0.86) {
			float beat = 0.5 + 0.5 * sin(TIME * (0.9 + 1.4 * s2) + s1 * 40.0);
			own_glow = biolum * pow(beat, 10.0);
		}
	} else {
		float u = fract(s1 + t * rise / rise_height);
		float y = u * rise_height;
		p = vent + vec3(0.0, y, 0.0);
		float spread = 0.08 + y * 0.05;
		p.x += spread * (s2 - 0.5) * 2.0 + 0.06 * sin(t * 3.1 + s1 * 30.0) * (1.0 + y * 0.1);
		p.z += spread * (s3 - 0.5) * 2.0 + 0.06 * cos(t * 2.7 + s2 * 30.0) * (1.0 + y * 0.1);
		fade = smoothstep(0.0, 0.03, u) * (1.0 - smoothstep(0.7, 1.0, u));
		grow = (0.5 + 0.7 * s3) * (1.0 + u * 1.2);
	}
	vec3 centre = (MODEL_MATRIX * vec4(p, 1.0)).xyz;
	float s = size * grow * (fade > 0.0 ? 1.0 : 0.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(MAIN_CAM_INV_VIEW_MATRIX[0] * s, MAIN_CAM_INV_VIEW_MATRIX[1] * s,
			MAIN_CAM_INV_VIEW_MATRIX[2] * s, vec4(centre, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	VERTEX = vec3(UV.x - 0.5, UV.y - 0.5, 0.0);
	world_pos = centre;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r2 = dot(c, c);
	float shape;
	if (kind == 0) {
		shape = exp(-r2 * 4.0) * (1.0 - smoothstep(0.7, 1.0, r2));
	} else {
		// A bubble: a bright rim and a spark, its middle clear.
		float r = sqrt(r2);
		shape = smoothstep(0.55, 0.85, r) * (1.0 - smoothstep(0.85, 1.0, r)) + 0.8 * exp(-dot(c - vec2(-0.35, 0.35),
				c - vec2(-0.35, 0.35)) * 40.0);
	}
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 light = water_top * 1.6 + flood_light(world_pos, v) * 1.4 + film_light(world_pos) * 0.5 + sun_colour * sun * 0.5
			+ vec3(env_light);
	vec3 col = light + biolum_colour * own_glow * 3.0;
	float dist = distance(world_pos, CAMERA_POSITION_WORLD);
	ALBEDO = col * shape * opacity * fade * level * exp(-dist * murk * 0.8);
}
