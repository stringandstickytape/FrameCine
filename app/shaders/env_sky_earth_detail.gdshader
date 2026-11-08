// The sky system's detailed Earth (scripts/env/systems/sky.gd, `earth_detail`; since 2026-11-08, the Crater's quality
// pass: "Earth is the jewel ... oceans with sun glint, cloud bands, a bright limb with a thin blue atmosphere, the night
// side's city lights faint on the dark part, slowly turning", the brief). The plain Earth (env_sky_earth.gdshader)
// stays as it was for any other room.
//
// The mesh is a sphere a little larger than Earth (its atmosphere's reach); each pixel finds where its ray meets the
// ball itself, so the limb is exact at any size. Earth's face is kit/earth_map.gd's map (land, dry land, ice, where the
// cities are); the sky's noise breaks up the coasts, mottles the land and draws the clouds: bands along the equator and
// the storm tracks, clear over the deserts and the subtropical highs. Lit from the side its phase gives: the oceans'
// glint where the sun is mirrored, a rosy edge to the clouds along the terminator, the cities' lights faint and warm on
// the dark side, a thin blue atmosphere round the limb, brightest on the sunlit side. Earth covers a few degrees, so
// the work per pixel is cheap in all.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_back, shadows_disabled, specular_disabled, fog_disabled,
		skip_vertex_transform;

#include "res://shaders/env_sky_common.gdshaderinc"

uniform sampler2D earth_map : filter_linear_mipmap, repeat_enable;
uniform vec3 earth_dir = vec3(0.0, 0.5, -0.866);
uniform float earth_half = 0.0175;
uniform mat3 earth_basis = mat3(1.0);
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform float earth_spin = 0.0;
uniform float earth_radius = 175.0;
// How bright Earth's day side is, and its night side's lights.
uniform float day_level = 1.0;
uniform float city_level = 1.0;

// The atmosphere reaches this far over the ball (in Earth's radii; the real one's glow is thinner still).
const float AIR = 0.035;

varying vec3 ray;

void vertex() {
	vec3 n_room = earth_basis * normalize(VERTEX);
	vec3 p = earth_dir + n_room * earth_half * (1.0 + AIR * 1.4);
	ray = p;
	vec3 world = CAMERA_POSITION_WORLD + sky_room_basis(MODEL_MATRIX) * p * earth_radius;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

float n2(vec2 uv, float lod) {
	return textureLod(sky_noise, uv, lod).r;
}

// Earth's face where the ray d meets the ball (centre c, b = dot(d, c), angular radius's sine r).
vec3 earth_face(vec3 d, vec3 c, float b, float r, vec3 sun) {
	float disc = b * b - (1.0 - r * r);
	float t = b - sqrt(max(disc, 0.0));
	vec3 n_room = normalize(d * t - c);
	vec3 n = transpose(earth_basis) * n_room;
	float lat = asin(clamp(n.y, -1.0, 1.0));
	// East is to the right as seen, and Earth turns west to east: its face moves to the right.
	float lon = atan(n.x, n.z) - earth_spin;
	vec2 uv = vec2(fract(lon / (2.0 * SKY_PI) + 0.5), 0.5 - lat / SKY_PI);
	// The coast: the map's soft edge cut by noise, so it is not the outline's straight runs.
	vec2 nuv = vec2(uv.x * 3.0, uv.y * 1.5);
	float wobble = n2(nuv * 4.0, 0.0) - 0.5 + (textureLod(sky_noise, nuv * 11.0, 0.0).g - 0.5) * 0.6;
	vec4 m = textureLod(earth_map, uv, 0.0);
	float land = smoothstep(0.46, 0.54, m.r + wobble * 0.28);
	float shelf = smoothstep(0.08, 0.45, m.r + wobble * 0.2) * (1.0 - land);
	// The land: forest to grassland to desert by the map's dryness, mottled; mountains' darker grain.
	float mott = textureLod(sky_noise, nuv * 7.0 + vec2(0.37, 0.11), 0.0).b;
	float mott2 = textureLod(sky_noise, nuv * 17.0 + vec2(0.71, 0.29), 0.0).r;
	float dry = clamp(m.g * (0.75 + 0.5 * mott2) + (mott - 0.5) * 0.45, 0.0, 1.0);
	vec3 forest = vec3(0.035, 0.07, 0.025);
	vec3 grass = vec3(0.1, 0.11, 0.045);
	vec3 desert = mix(mix(vec3(0.36, 0.2, 0.1), vec3(0.5, 0.36, 0.2), mott), vec3(0.58, 0.48, 0.34), mott2 * mott2);
	vec3 ground = mix(mix(forest, grass, smoothstep(0.0, 0.35, dry + abs(lat) * 0.25)), desert,
			smoothstep(0.35, 0.8, dry));
	ground *= 0.8 + 0.4 * textureLod(sky_noise, nuv * 19.0, 0.0).a;
	vec3 ocean = mix(vec3(0.004, 0.016, 0.055), vec3(0.015, 0.07, 0.11), shelf);
	vec3 surf = mix(ocean, ground, land);
	float ice = smoothstep(0.35, 0.7, m.b + (mott - 0.5) * 0.3);
	surf = mix(surf, vec3(0.78, 0.82, 0.88), ice);
	// The clouds: two sizes of noise, swirled by a third, in bands by latitude; little over the deserts.
	float alat = abs(lat);
	vec2 cuv = vec2(uv.x * 2.0 + earth_spin * 0.004, uv.y);
	vec2 swirl = vec2(textureLod(sky_noise, cuv * vec2(2.0, 1.4) + vec2(0.2, 0.6), 0.0).r,
			textureLod(sky_noise, cuv * vec2(2.0, 1.4) + vec2(0.7, 0.3), 0.0).g) - 0.5;
	vec2 cw = cuv + swirl * vec2(0.35, 0.14) * (0.4 + 0.6 * smoothstep(0.35, 0.9, alat));
	float cn = textureLod(sky_noise, cw * vec2(3.0, 2.2), 0.0).r * 0.74
			+ textureLod(sky_noise, cw * vec2(9.0, 6.0) + vec2(0.3, 0.8), 0.0).a * 0.26;
	float cover = 0.38 + 0.22 * exp(-pow(lat / 0.13, 2.0)) - 0.2 * exp(-pow((alat - 0.45) / 0.13, 2.0))
			+ 0.14 * smoothstep(0.6, 0.95, alat) - 0.25 * smoothstep(0.4, 0.9, m.g) * land;
	float cloud = smoothstep(1.0 - cover - 0.1, 1.0 - cover + 0.2, cn);
	// The light: the day side's, softened at the terminator (the air scatters past it).
	float mu = dot(n_room, sun);
	float day = smoothstep(-0.08, 0.22, mu);
	float lamb = max(mu, 0.0);
	vec3 view = -d;
	float facing = clamp(dot(n_room, view), 0.0, 1.0);
	vec3 col = surf * (0.25 + 0.95 * pow(lamb, 0.8)) * day;
	// The glint: the sun mirrored in the sea, dulled by cloud.
	vec3 hv = normalize(sun + view);
	float spec = pow(max(dot(n_room, hv), 0.0), 600.0) * 0.9 + pow(max(dot(n_room, hv), 0.0), 50.0) * 0.1;
	col += vec3(1.0, 0.92, 0.8) * spec * (1.0 - land) * (1.0 - ice) * (1.0 - cloud) * day;
	vec3 cloud_col = vec3(0.9, 0.91, 0.93) * (0.2 + 0.95 * pow(lamb, 0.7));
	cloud_col *= mix(vec3(1.0), vec3(1.0, 0.62, 0.42), exp(-pow(mu / 0.1, 2.0)) * 0.8);
	col = mix(col, cloud_col * day, cloud * 0.92);
	// The night side: the cities' lights, points out of the density, under thin cloud.
	float night = 1.0 - smoothstep(-0.12, 0.04, mu);
	float pts = smoothstep(0.55, 0.85, textureLod(sky_noise, nuv * 23.0 + vec2(0.13, 0.71), 0.0).a);
	float lights = m.a * land * (0.35 + 0.9 * pts) * (1.0 - cloud * 0.75);
	col += vec3(1.0, 0.72, 0.38) * lights * night * 0.22 * city_level;
	// The atmosphere over the face: a blue veil, thickest towards the limb, on the lit side.
	float edge = pow(1.0 - facing, 2.5);
	col = mix(col, vec3(0.2, 0.38, 0.85) * (0.15 + 0.9 * lamb), clamp(edge * 0.75 + 0.06, 0.0, 1.0) * day);
	col += vec3(0.12, 0.22, 0.6) * pow(1.0 - facing, 6.0) * smoothstep(-0.2, 0.3, mu) * 0.8;
	return col;
}

void fragment() {
	vec3 d = normalize(ray);
	vec3 c = normalize(earth_dir);
	float b = dot(d, c);
	float r = earth_half / sqrt(1.0 + earth_half * earth_half);
	// The ray's nearest distance from Earth's centre, in Earth radii (1: it grazes the limb).
	float miss = sqrt(max(1.0 - b * b, 0.0)) / r;
	vec3 sun = normalize(sun_dir);
	if (miss >= 1.0) {
		// The atmosphere seen edge on beyond the limb: a thin glow, on the lit side (and a trace round the dark one,
		// the sunlight bent through the air there).
		vec3 out_dir = normalize(d - c * b);
		float lit = smoothstep(-0.35, 0.6, dot(out_dir, sun));
		float h = (miss - 1.0) / AIR;
		float glow = exp(-h * 3.2) * (1.0 - smoothstep(0.85, 1.0, h));
		vec3 col = mix(vec3(0.3, 0.12, 0.08) * 0.6, vec3(0.32, 0.55, 1.0), lit);
		ALBEDO = col * (0.08 + 0.95 * lit) * day_level;
		ALPHA = clamp(glow * (0.25 + 0.75 * lit), 0.0, 1.0);
	} else {
		ALBEDO = earth_face(d, c, b, r, sun) * day_level;
		ALPHA = 1.0;
	}
}
