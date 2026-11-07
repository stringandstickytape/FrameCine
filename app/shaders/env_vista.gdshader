// The vista system's far scenery (scripts/env/systems/vista.gd; docs/environments.md, "The vista"): one mesh for all
// of a room's scenery, each vertex naming its material (UV2.x). Unshaded and cheap: lit by the sky's light (the sky
// system's colours overhead and at the horizon, by the surface's facing), the screen's spill where it is near enough to
// matter, floodlights on stone, lamps and a pool's glow. Fog applies, as it should far away.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;

#include "res://shaders/env_spill.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// The sky's light (sRGB colours): overhead and at the horizon.
uniform vec3 sky_top : source_color = vec3(0.03, 0.04, 0.08);
uniform vec3 sky_low : source_color = vec3(0.05, 0.05, 0.08);
uniform float sky_gain = 1.0;
uniform float spill = 1.0;
uniform float floodlight = 1.0;
uniform vec3 flood_colour : source_color = vec3(1.0, 0.72, 0.42);
uniform float town_lights = 0.6;
uniform float pool_glow = 1.0;
uniform vec3 pool_colour : source_color = vec3(0.18, 0.78, 0.88);
// The first pool, in the world: its centre, its axes (unit, along its length and its width) and half its size.
uniform vec3 pool_centre = vec3(0.0, -1000.0, 0.0);
uniform vec3 pool_x = vec3(1.0, 0.0, 0.0);
uniform vec3 pool_z = vec3(0.0, 0.0, 1.0);
uniform vec2 pool_half = vec2(1.0);
uniform float water_time = 0.0;
uniform float snow = 1.0;

// The materials (vista.gd M_*).
const int M_ROCK = 0;
const int M_BARK = 1;
const int M_FLOOD = 2;
const int M_FOLIAGE = 3;
const int M_GROUND = 4;
const int M_LAMP = 5;
const int M_TWIG = 6;
const int M_WATER = 7;
const int M_POOLSIDE = 8;

varying vec3 world_pos;
varying vec3 world_normal;
varying flat int mat;
varying float extra;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mat = int(UV2.x + 0.5);
	extra = UV2.y;
}

vec3 pool_light(vec3 p) {
	vec3 q = p - pool_centre;
	vec2 l = vec2(dot(q, pool_x), dot(q, pool_z));
	float d = length(max(abs(l) - pool_half, vec2(0.0)));
	float h = max(q.y, 0.0);
	return pool_colour * pool_glow * 0.7 / (1.0 + (d * d + h * h) / 3.0);
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 sky = mix(sky_low, sky_top, clamp(n.y * 0.5 + 0.5, 0.0, 1.0)) * sky_gain;
	vec3 screen = room_light_at(world_pos, spill) - vec3(env_light);
	vec3 albedo = COLOR.rgb;
	float hf = COLOR.a;
	vec3 c;
	if (mat == M_BARK) {
		float marks = smoothstep(0.66, 0.72, texture(noise_tex, vec2(UV.x * 0.25 + extra, UV.y * 0.3)).g);
		vec3 bark = mix(vec3(0.62, 0.6, 0.56), vec3(0.03, 0.03, 0.03), marks * 0.9);
		bark = mix(bark, vec3(0.06, 0.05, 0.045), 1.0 - smoothstep(0.0, 1.6, UV.y));
		c = bark * (sky * 1.4 + screen);
	} else if (mat == M_FLOOD) {
		vec3 to_eye = CAMERA_POSITION_WORLD - world_pos;
		float facing = 0.55 + 0.45 * max(dot(n, normalize(vec3(to_eye.x, 0.0, to_eye.z) + vec3(1e-4))), 0.0);
		vec3 flood = flood_colour * floodlight * (1.25 - 0.65 * hf) * facing;
		c = albedo * (sky + flood + screen);
	} else if (mat == M_FOLIAGE) {
		float v = texture(noise_tex, UV * vec2(3.0, 0.35) + vec2(extra, 0.0)).r;
		c = albedo * (0.6 + 0.8 * v) * (sky * 1.3 + screen + pool_light(world_pos));
	} else if (mat == M_GROUND) {
		float v = texture(noise_tex, world_pos.xz * 0.05).g;
		vec3 g = mix(albedo, vec3(0.78, 0.81, 0.88) * (0.92 + 0.16 * v), snow);
		c = g * (sky * 1.5 + screen + pool_light(world_pos));
	} else if (mat == M_LAMP) {
		c = albedo * town_lights;
	} else if (mat == M_TWIG) {
		c = albedo * (sky + screen);
	} else if (mat == M_WATER) {
		vec2 p = world_pos.xz;
		float c1 = texture(noise_tex, p * 0.13 + vec2(water_time * 0.011, 0.0)).b;
		float c2 = texture(noise_tex, p.yx * 0.17 - vec2(0.0, water_time * 0.009)).b;
		float ca = pow(1.0 - abs(c1 - c2), 8.0);
		c = pool_colour * pool_glow * (0.5 + 0.55 * ca) * (0.75 + 0.45 * extra);
	} else if (mat == M_POOLSIDE) {
		c = albedo * (sky + screen + pool_light(world_pos));
	} else {
		// Rock and the like: the sky's light, a little more on the tops.
		c = albedo * (sky * (0.8 + 0.5 * hf) + screen);
	}
	ALBEDO = c;
}
