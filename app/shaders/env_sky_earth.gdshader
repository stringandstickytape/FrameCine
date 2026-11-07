// The sky system's Earth (scripts/env/systems/sky.gd), as seen from the Moon: a small sphere high in a black sky,
// lit from one side (its phase), turning slowly on its axis (earth_spin, from sky.gd: held to the comfort limits).
// Oceans, land, ice and clouds are drawn from the sky's noise: an Earth-like world, not a map. The sphere stays where
// it is; only its surface turns.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled, fog_disabled, skip_vertex_transform;

#include "res://shaders/env_sky_common.gdshaderinc"

// Its centre's direction (room frame), the tangent of half its size, its frame (local y its axis, z towards the
// viewer), where the sunlight comes from (room frame), how far it has turned (radians) and its distance.
uniform vec3 earth_dir = vec3(0.0, 0.5, -0.866);
uniform float earth_half = 0.0175;
uniform mat3 earth_basis = mat3(1.0);
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform float earth_spin = 0.0;
uniform float earth_radius = 175.0;

varying vec3 n_local;
varying vec3 n_room;

void vertex() {
	n_local = normalize(VERTEX);
	n_room = earth_basis * n_local;
	vec3 p = earth_dir + n_room * earth_half;
	vec3 world = CAMERA_POSITION_WORLD + sky_room_basis(MODEL_MATRIX) * p * earth_radius;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(n_local);
	float lat = asin(clamp(n.y, -1.0, 1.0));
	float lon = atan(n.x, n.z) + earth_spin;
	vec2 uv = vec2(lon / (2.0 * SKY_PI) * 2.0, lat / SKY_PI * 1.4 + 0.5);
	float land_n = textureLod(sky_noise, uv, 1.0).r * 0.7 + textureLod(sky_noise, uv * 3.0, 1.0).g * 0.3;
	float land = smoothstep(0.54, 0.6, land_n);
	float dry = textureLod(sky_noise, uv * 1.7 + vec2(0.3, 0.1), 1.0).b;
	vec3 ocean = vec3(0.008, 0.03, 0.11);
	vec3 ground = mix(vec3(0.035, 0.08, 0.025), vec3(0.22, 0.16, 0.08), smoothstep(0.4, 0.7, dry));
	vec3 surf = mix(ocean, ground, land);
	surf = mix(surf, vec3(0.75, 0.8, 0.85), smoothstep(1.05, 1.2, abs(lat)));
	float cl = smoothstep(0.55, 0.78, textureLod(sky_noise, uv * vec2(1.0, 1.6) + vec2(earth_spin * 0.03, 0.2), 1.0).a);
	surf = mix(surf, vec3(0.85, 0.86, 0.88), cl * 0.85);
	vec3 nr = normalize(n_room);
	float light = smoothstep(-0.06, 0.22, dot(nr, sun_dir));
	float rim = pow(1.0 - clamp(dot(nr, -earth_dir), 0.0, 1.0), 3.0);
	ALBEDO = surf * (light * 1.15 + 0.012) + vec3(0.12, 0.28, 0.7) * rim * (light * 0.9 + 0.04);
}
