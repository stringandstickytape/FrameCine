// The water outside a glass dome (scripts/env/systems/dome_hall.gd, docs/environments.md "dome_hall"), shared by the
// shaders that draw it and what lies in it: the water all round (env_water_outside.gdshader), the sea floor, its rocks
// and fronds (env_seabed.gdshader), marine snow and bubbles (env_water_motes.gdshader) and the floodlights' beams
// (env_water_beam.gdshader). One water, so a rock 20 m off fades into exactly the colour the water shows behind it.
//   water_colour(dir)     what the eye sees looking along dir through open water: the deep below, the lit water above
//                         and, with sun > 0, the light from the surface: Snell's window overhead (the sky squeezed
//                         into a bright disc 49 degrees round the zenith) and shafts slanting down from it
//   in_water(c, p, eye)   a colour at p seen from eye through `murk` (per metre): it fades into the water behind it
//   caustic(xz)           the surface's light focused on the floor: two copies of a cellular map (caustic_map) drifting
//                         apart, their brighter web where they meet. 0..1
//   flood_light(p, n)     the floodlights on the drum (up to FLOODS spot lamps: position, aim, cone) at p facing n
//   film_light(p)         the film's light through the glass: the screen's spill in the picture's colour (the bias
//                         light), only on the side of the screen that faces the room
// Every motion here is slow: the shafts sway and the caustics drift at under 0.3 Hz at any point, far under the
// photosensitivity ceiling (room_schema.gd MAX_HZ), and the Motion setting scales them (water_motion).

#include "res://shaders/env_spill.gdshaderinc"

#define FLOODS 4

uniform vec3 water_top : source_color = vec3(0.02, 0.09, 0.16);
uniform vec3 water_deep : source_color = vec3(0.0, 0.008, 0.02);
// The light from the surface: 0 in the abyss, 1 in the sunlit shallows.
uniform float sun = 0.0;
uniform vec3 sun_colour : source_color = vec3(0.55, 0.85, 0.95);
// How fast the shafts sway and the caustics drift (the room's Motion setting scales it).
uniform float water_motion = 1.0;
uniform float murk = 0.07;
uniform sampler2D caustic_map : hint_default_black, filter_linear_mipmap, repeat_enable;
// Metres a caustic cell spans.
uniform float caustic_scale = 1.6;
uniform int flood_count = 0;
uniform vec4 flood_pos[FLOODS];
// xyz the aim, w the cosine of the cone's half angle.
uniform vec4 flood_aim[FLOODS];
uniform vec3 flood_colour : source_color = vec3(1.0, 0.9, 0.75);
uniform float flood = 0.0;
// The screen's facing (its normal into the room) and how far its light carries into the water.
uniform vec3 screen_normal = vec3(0.0, 0.0, 1.0);
uniform float film_reach = 1.0;

vec3 water_colour(vec3 dir) {
	float e = dir.y;
	vec3 c = mix(water_deep, water_top, smoothstep(-0.55, 0.8, e));
	if (sun > 0.0) {
		float az = atan(dir.x, dir.z);
		float t = TIME * 0.06 * water_motion;
		// Shafts: narrow streaks round the zenith that sway slowly, brightest looking up and out, gone below the
		// horizon. Three waves of the angle multiplied, sharpened: a few strong shafts, many faint ones.
		float r = 0.5 + 0.5 * sin(az * 9.0 + 1.6 * sin(az * 3.0 + t * 2.1) + t);
		r *= 0.5 + 0.5 * sin(az * 23.0 - t * 1.4 + 1.7 * sin(az * 5.0 - t));
		r *= 0.6 + 0.4 * sin(az * 41.0 + t * 0.9);
		r = pow(r, 2.5);
		float band = smoothstep(-0.2, 0.5, e) * (1.0 - smoothstep(0.6, 0.78, e));
		// Snell's window: the sky above squeezed into a disc 49 degrees round the zenith; through it the surface's
		// waves (the caustic map laid on the surface's plane), its rim wavering with them and brightest just inside.
		float rim = e + 0.008 * sin(az * 13.0 + t * 4.0) + 0.006 * sin(az * 7.0 - t * 3.0);
		float window = smoothstep(0.64, 0.68, rim);
		vec2 surf = dir.xz / max(dir.y, 0.25) * 0.35 + vec2(t * 0.4, t * 0.25);
		float waves = 1.0 - smoothstep(0.0, 0.3, texture(caustic_map, surf).r);
		float edge = smoothstep(0.64, 0.7, rim) * (1.0 - smoothstep(0.7, 0.8, rim));
		c += sun_colour * sun * (r * band * 0.42 + window * (0.28 + 0.22 * waves + 0.35 * edge
				+ 0.3 * smoothstep(0.9, 1.0, e)) + smoothstep(-0.2, 1.0, e) * 0.06);
	}
	return c;
}

vec3 in_water(vec3 c, vec3 p, vec3 eye) {
	vec3 d = p - eye;
	float dist = length(d);
	float f = 1.0 - exp(-dist * murk);
	return mix(c, water_colour(d / max(dist, 0.001)), f);
}

float caustic(vec2 xz) {
	float t = TIME * 0.045 * water_motion;
	vec2 uv = xz / (caustic_scale * 4.0);
	// The map is the distance to a cell's wall: near 0 on the walls. Two copies drifting apart; where their walls
	// meet the light gathers most.
	float a = 1.0 - smoothstep(0.0, 0.28, texture(caustic_map, uv + vec2(t, t * 0.37)).r);
	float b = 1.0 - smoothstep(0.0, 0.28, texture(caustic_map, uv * 1.31 + vec2(-t * 0.71, t * 0.53) + 0.37).r);
	return clamp(0.5 * (a * a + b * b) + 1.5 * a * b, 0.0, 1.5);
}

vec3 flood_light(vec3 p, vec3 n) {
	vec3 sum = vec3(0.0);
	if (flood <= 0.0) {
		return sum;
	}
	for (int i = 0; i < min(flood_count, FLOODS); i++) {
		vec3 to = p - flood_pos[i].xyz;
		float d2 = dot(to, to);
		vec3 l = to * inversesqrt(max(d2, 0.0001));
		float c = dot(l, flood_aim[i].xyz);
		float cone = smoothstep(flood_aim[i].w, mix(flood_aim[i].w, 1.0, 0.5), c);
		float facing = clamp(-dot(n, l) * 0.8 + 0.2, 0.0, 1.0);
		sum += cone * facing * flood_pos[i].w * 2.5 / (1.0 + d2 * 0.03);
	}
	return sum * flood_colour * flood;
}

vec3 film_light(vec3 p) {
	vec3 to = p - screen_center;
	float d = length(to);
	float front = clamp(dot(to / max(d, 0.001), screen_normal) * 0.8 + 0.2, 0.0, 1.0);
	return screen_glow * spill_tint(p) * front * film_reach / (1.0 + 0.012 * d * d);
}
