// The sky system's constellation lines (scripts/env/systems/sky.gd): faint thin bands between the stars of the
// usual figures, as a planetarium shows them. Off by default. The mesh is in the equatorial frame, like the stars.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled,
		skip_vertex_transform;

#include "res://shaders/env_sky_common.gdshaderinc"

uniform mat3 star_basis = mat3(1.0);
uniform float lines = 0.0;
uniform vec3 line_colour : source_color = vec3(0.45, 0.6, 0.9);
uniform float model_radius = 184.0;

varying float across;
varying float vis;

void vertex() {
	vec3 p = star_basis * (VERTEX / model_radius);
	vec3 d = normalize(p);
	vec3 world = CAMERA_POSITION_WORLD + sky_room_basis(MODEL_MATRIX) * p * radius;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	across = UV.y * 2.0 - 1.0;
	float lum = dot(sky_base(d), vec3(0.2126, 0.7152, 0.0722));
	float show = mix(clamp(1.0 - lum * 10.0, 0.0, 1.0), 1.0, space);
	vis = lines * show * smoothstep(-0.01, 0.06, d.y) * (1.0 - sky_cloud_cover(d, 3.0));
}

void fragment() {
	ALBEDO = line_colour;
	ALPHA = clamp((1.0 - smoothstep(0.2, 1.0, abs(across))) * 0.4 * vis, 0.0, 1.0);
}
