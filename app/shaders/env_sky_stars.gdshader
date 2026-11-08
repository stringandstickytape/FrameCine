// The sky system's stars (scripts/env/systems/sky.gd): one small quad per star, at its place on the celestial sphere
// (the mesh is in the equatorial frame; star_basis turns it to the room's sky for the time and latitude). A soft disc,
// its brightness by magnitude, its colour by its colour index. Hidden by the twilight, by clouds and near the
// horizon; a slow, small twinkle when asked for (off by default, for comfort; under 1 Hz).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled,
		skip_vertex_transform;

#include "res://shaders/env_sky_common.gdshaderinc"

// Equatorial -> room frame.
uniform mat3 star_basis = mat3(1.0);
uniform float stars = 1.0;
uniform float twinkle = 0.0;
// The layer's distance (its mesh's vertices are there too, so the checks see them far away): nearer than the
// dome, whose flat facets come up to a metre inside its radius, so the dome never hides a star.
uniform float model_radius = 185.0;
// The brightest (magnitude under 0: an evening planet) show through a bright twilight, as they do. Since 2026-11-08
// (the drive-in's evening star); 0 by default.
uniform float bright_in_twilight = 0.0;

varying vec2 corner;
varying float vis;
varying vec4 tint;

void vertex() {
	vec3 p = star_basis * (VERTEX / model_radius);
	vec3 d = normalize(p);
	vec3 world = CAMERA_POSITION_WORLD + sky_room_basis(MODEL_MATRIX) * p * model_radius;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	corner = UV * 2.0 - 1.0;
	float lum = dot(sky_base(d), vec3(0.2126, 0.7152, 0.0722));
	float show = mix(clamp(1.0 - lum * 14.0, 0.0, 1.0), 1.0, space);
	show = mix(show, max(show, clamp(1.2 - lum * 2.0, 0.0, 1.0)), bright_in_twilight * smoothstep(0.0, -1.0, UV2.y));
	float low = 1.0 - clamp(d.y * 3.0, 0.0, 1.0);
	float ext = mix(smoothstep(-0.01, 0.1, d.y), step(-0.02, d.y), space);
	float cover = sky_cloud_cover(d, 3.0);
	float tw = 1.0 - twinkle * 0.4 * (0.5 + 0.5 * sin(TIME * (1.5 + 4.0 * UV2.x) + UV2.x * 40.0)) * mix(0.7, 1.4, low);
	vis = stars * show * ext * (1.0 - cover) * tw;
	tint = COLOR;
}

void fragment() {
	float r2 = dot(corner, corner);
	ALBEDO = tint.rgb;
	ALPHA = clamp(exp(-r2 * 4.5) * tint.a * vis, 0.0, 1.0);
}
