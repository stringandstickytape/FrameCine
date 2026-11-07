// Shared by the sky system's shaders (scripts/env/systems/sky.gd; docs/environments.md, "The sky"): the dome
// (env_sky.gdshader), the stars (env_sky_stars), the constellation lines (env_sky_lines) and Earth (env_sky_earth).
// Every layer is drawn round the camera, not round the room: it is at the same distance whichever way the head goes,
// like the real sky, and never comes nearer than the room. A direction is in the room's frame (y up, -z ahead).

// The twilight to night gradient: dusk 0 is the last light of the evening, 1 full night.
uniform vec3 night_zenith : source_color = vec3(0.004, 0.006, 0.016);
uniform vec3 night_horizon : source_color = vec3(0.02, 0.025, 0.05);
uniform vec3 twilight_zenith : source_color = vec3(0.08, 0.12, 0.30);
uniform vec3 twilight_horizon : source_color = vec3(0.75, 0.42, 0.25);
uniform vec3 ground_colour : source_color = vec3(0.01, 0.01, 0.012);
// The sunset's glow low over the horizon, where the sun went down (glow_dir: its direction in the room's frame).
uniform vec3 glow_colour : source_color = vec3(1.0, 0.45, 0.18);
uniform vec3 glow_dir = vec3(-1.0, 0.0, 0.0);
uniform float dusk = 1.0;
// 0: a sky with air (the gradient); 1: space (black, the stars at full).
uniform float space = 0.0;

// The clouds: a tiling noise (sky.gd noise_texture(): r, g two sizes of cloud, b the galaxy's mottling, a rays).
uniform sampler2D sky_noise : filter_linear_mipmap, repeat_enable;
uniform float clouds = 0.0;
uniform vec2 cloud_offset = vec2(0.0);

// The layers' distance from the camera (metres; the camera's far plane is 200).
uniform float radius = 190.0;

const float SKY_PI = 3.14159265;

// The room's frame in the world, without the room's scale.
mat3 sky_room_basis(mat4 model) {
	return mat3(normalize(model[0].xyz), normalize(model[1].xyz), normalize(model[2].xyz));
}

// The sky's colour without clouds, stars or the galaxy, in the direction d (unit, room frame).
vec3 sky_base(vec3 d) {
	float up = clamp(d.y, 0.0, 1.0);
	float h = pow(up, 0.45);
	vec3 night = mix(night_horizon, night_zenith, h);
	vec3 twilight = mix(twilight_horizon, twilight_zenith, pow(up, 0.6));
	float g = max(dot(normalize(vec3(d.x, 0.0, d.z) + vec3(1e-5)), glow_dir), 0.0);
	twilight += glow_colour * pow(g, 6.0) * exp(-up * 9.0) * 0.9;
	vec3 c = mix(twilight, night, smoothstep(0.0, 1.0, dusk));
	c *= 1.0 - space;
	// Below the horizon: the ground, quickly.
	return mix(c, ground_colour, smoothstep(0.0, -0.04, d.y));
}

// How much of the sky the clouds cover in the direction d (0..1). lod: a mip level for the vertex stage (-1: the
// fragment's own).
float sky_cloud_cover(vec3 d, float lod) {
	if (clouds <= 0.0 || d.y <= 0.0) {
		return 0.0;
	}
	vec2 uv = d.xz / (d.y + 0.12) * 0.32 + cloud_offset;
	vec2 n2;
	if (lod < 0.0) {
		n2 = vec2(texture(sky_noise, uv).r, texture(sky_noise, uv * 2.7 + vec2(0.37, 0.11)).g);
	} else {
		n2 = vec2(textureLod(sky_noise, uv, lod).r, textureLod(sky_noise, uv * 2.7 + vec2(0.37, 0.11), lod).g);
	}
	float n = n2.x * 0.68 + n2.y * 0.32;
	float c = smoothstep(1.0 - clouds * 0.85, 1.0 - clouds * 0.85 + 0.3, n);
	// Thinner straight up, thicker towards the horizon, as clouds look.
	return c * smoothstep(0.0, 0.05, d.y) * mix(1.0, 0.8, d.y);
}

// The camera-centred position of a direction at a distance (world space), for the vertex stage.
vec3 sky_world(vec3 room_dir, mat4 model, vec3 camera, float r) {
	return camera + sky_room_basis(model) * room_dir * r;
}
