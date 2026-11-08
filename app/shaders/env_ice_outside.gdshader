// The night outside the Ice cinema (scripts/env/systems/kit/ice_hall.gd; docs/environments.md, "Room: Ice cinema"):
// the snowfield, its drifts and the path from the doorway, spruces under snow, the fells on the horizon and a cabin
// far off with its windows lit. One mesh, one draw, unshaded and cheap: lit by the Moon (low in the south-east,
// raking the drifts), the sky's light overhead and at the horizon (the sky system's colours), and the aurora's green
// on whatever faces it, as strong as the aurora is now. Not dimmed by the house lights: it is the night's light.
// Vertex colour: the surface's own colour (linear); alpha 1 a lit surface, 0 a lit window (its colour times glow).
// Snow glitters a little where a facet catches the Moon: still in the world, it changes only as the head moves.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled;

uniform vec3 sky_top : source_color = vec3(0.03, 0.04, 0.08);
uniform vec3 sky_low : source_color = vec3(0.06, 0.07, 0.1);
uniform float sky_gain = 1.0;
// The Moon: its direction (world), its light (colour times level).
uniform vec3 moon_dir = vec3(0.0, 0.3, -1.0);
uniform vec3 moon_light = vec3(0.0);
// The aurora: its direction (world, horizontal), its colour and level now.
uniform vec3 aurora_dir = vec3(-1.0, 0.0, 0.0);
uniform vec3 aurora_light = vec3(0.0);
// Lit windows (a cabin far off).
uniform float glow = 1.0;
uniform float glitter = 1.0;
// Far things fade towards the horizon's colour.
uniform float haze = 0.004;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 local_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	local_pos = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 albedo = COLOR.rgb;
	vec3 c;
	if (COLOR.a < 0.5) {
		c = albedo * glow;
	} else {
		vec3 sky = mix(sky_low, sky_top, clamp(n.y * 0.5 + 0.5, 0.0, 1.0)) * sky_gain;
		float moon = max(dot(n, moon_dir), 0.0);
		// The aurora is a wide light low over the east: what faces it and what faces up take it.
		float aur = clamp(dot(n, aurora_dir) * 0.6 + n.y * 0.4 + 0.15, 0.0, 1.0);
		c = albedo * (sky * 2.5 + moon_light * (0.3 + 0.7 * moon) + aurora_light * aur);
		// Glitter: a few facets of the snow (white surfaces only) catch the Moon towards the eye.
		float white = smoothstep(0.55, 0.75, min(albedo.r, albedo.b));
		if (glitter > 0.0 && white > 0.0) {
			vec3 cell = floor(local_pos * 40.0);
			float h = hash(cell);
			if (h > 0.985) {
				vec3 facet = normalize(n + (vec3(hash(cell + 1.7), hash(cell + 3.1), hash(cell + 5.3)) - 0.5) * 0.9);
				vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
				float g = pow(max(dot(reflect(-moon_dir, facet), v), 0.0), 60.0);
				float near = 1.0 - smoothstep(6.0, 25.0, length(CAMERA_POSITION_WORLD - world_pos));
				c += moon_light * g * glitter * white * near * 6.0;
			}
		}
	}
	float d = length(world_pos - CAMERA_POSITION_WORLD);
	c = mix(c, sky_low * sky_gain, 1.0 - exp(-d * haze));
	ALBEDO = c;
}
