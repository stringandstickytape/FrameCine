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
// The twilight's finer structure (since 2026-11-08, the drive-in's desert dusk; 0, the default, is the plain
// gradient): the warm light held in a thinner band along the horizon under a clearer blue, and opposite the sunset the
// Earth's shadow rising as a blue-grey band under the pink belt of Venus.
uniform float afterglow = 0.0;
uniform vec3 belt_colour : source_color = vec3(0.62, 0.36, 0.42);

// The clouds: a tiling noise (sky.gd noise_texture(): r, g two sizes of cloud, b the galaxy's mottling, a rays).
uniform sampler2D sky_noise : filter_linear_mipmap, repeat_enable;
uniform float clouds = 0.0;
uniform vec2 cloud_offset = vec2(0.0);

// The dome's distance from the camera (metres; the camera's far plane is 200). The other layers have their own,
// nearer.
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
	vec3 level = normalize(vec3(d.x, 0.0, d.z) + vec3(1e-5));
	float g = dot(level, glow_dir);
	// Away from the sunset the horizon is duller and cooler (the Earth's shadow rising there).
	vec3 horizon = mix(mix(twilight_zenith, twilight_horizon, 0.4) * 0.7, twilight_horizon,
			smoothstep(-1.0, 1.0, g));
	vec3 twilight = mix(horizon, twilight_zenith, pow(up, 0.6));
	if (afterglow > 0.0) {
		float toward = smoothstep(-1.0, 1.0, g);
		float band = exp(-up * mix(7.0, 11.0, 1.0 - toward));
		vec3 rich = mix(twilight_zenith, horizon, band);
		float anti = smoothstep(-0.1, -0.85, g);
		float belt = exp(-pow((up - 0.15) / 0.075, 2.0)) * anti;
		float shade = (1.0 - smoothstep(0.02, 0.1, up)) * anti;
		rich = mix(rich, belt_colour, belt * 0.55);
		rich = mix(rich, twilight_zenith * 0.55 + horizon * 0.12, shade * 0.75);
		twilight = mix(twilight, rich, afterglow);
	}
	twilight += glow_colour * pow(max(g, 0.0), 6.0) * exp(-up * 9.0) * 0.9;
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
