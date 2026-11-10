// The passing system's ground (scripts/env/systems/passing.gd; docs/environments/passing.md): strips of grass, field,
// path, snow, sand, stone or water beside the way. The strips stand still; their pattern goes by with the journey
// (it repeats over GROUND_PERIOD metres). Nearer the way's line than `nearest` (passing.gd still_within():
// FLOW_NEAREST, more for a faster journey) the pattern fades out, so the ground that passes closest shows nothing
// moving: the comfort limit holds for the ground too. Water takes the sky by Fresnel, rippled, and under a Moon its
// road (`moon`). Lit as the scenery is; the same mist and horizon.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;

#include "res://shaders/env_spill.gdshaderinc"

uniform vec3 along_dir = vec3(0.0, 0.0, -1.0);
uniform vec3 across_dir = vec3(1.0, 0.0, 0.0);
uniform float shown = 1.0;
uniform float light = 1.0;
uniform vec3 sky_top : source_color = vec3(0.106, 0.133, 0.212);
uniform vec3 sky_low : source_color = vec3(0.106, 0.133, 0.212);
uniform float mist = 0.0;
uniform vec3 mist_colour : source_color = vec3(0.227, 0.259, 0.314);
uniform float glow = 0.6;
uniform vec3 glow_colour : source_color = vec3(1.0, 0.761, 0.478);
uniform float glow_reach = 6.0;
uniform float glow_half_length = 3.0;
uniform float spill = 1.0;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// fposmod(travel, GROUND_PERIOD): how far the pattern has gone by.
uniform float ground_phase = 0.0;
// passing.gd still_within(): where the pattern would cross the eye too fast, it is not shown.
uniform float nearest = 3.0;
uniform float far = 188.0;
// The Moon over the water (sky.gd moon_shine(), by passing.gd): towards it in the room's frame, and how bright its
// road is (0: no Moon, no road).
uniform vec3 moon_dir = vec3(0.0, 1.0, 0.0);
uniform float moon = 0.0;

// passing.gd GROUND_PERIOD.
const float GROUND_PERIOD = 64.0;
// The kinds (passing.gd GROUND_KINDS): water is 0.
const int K_WATER = 0;
// The Moon's face (env_sky_moon.gdshader moon_colour, in linear light).
const vec3 MOON_COLOUR = vec3(1.0, 0.91, 0.71);
// How far the water's ripples tilt, as a slope (the spread of a bell curve): 0.12 is about 7 degrees, a river's or a
// canal's quiet water. It sets the road's shape: narrow, and long towards the eye. Rougher, and the road would be a
// broad dim fan; smoother, and it would be the Moon's own disc in a mirror.
const float MOON_ROUGH = 0.12;
// The road at its brightest against the Moon's face: half of it, and still the brightest thing on dark water.
const float MOON_ROAD = 0.5;

varying vec3 world_pos;
// From the ground to the eye, in the room's frame (the Moon's direction is given in it).
varying vec3 eye_room;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	eye_room = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz - VERTEX;
	// Written as every colour of a document is (sRGB): to linear light, as env_passing_place.gdshaderinc does it.
	COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) / 1.055, vec3(2.4)), COLOR.rgb / 12.92,
			lessThan(COLOR.rgb, vec3(0.04045)));
}

void fragment() {
	vec2 g = vec2(UV.x, UV.y + ground_phase);
	float still = smoothstep(nearest * 0.6, nearest, abs(UV.x));
	vec3 sky = sky_top * light * shown;
	// What comes out of the cabin's windows (as env_passing.gdshader): the lamps' light and the screen's alike.
	float from_windows = (1.0 - smoothstep(0.0, glow_reach, abs(UV.x)))
			* (1.0 - smoothstep(glow_half_length, glow_half_length + 2.0, abs(UV.y)));
	vec3 screen = (room_light_at(world_pos, spill) - vec3(env_light)) * shown * from_windows;
	vec3 cabin = glow_colour * glow * shown * from_windows;
	vec3 lit = sky + screen + cabin;
	vec3 c;
	if (int(UV2.x + 0.5) == K_WATER) {
		float ripple = texture(noise_tex, g / GROUND_PERIOD * 8.0).b - 0.5;
		vec3 e = normalize(CAMERA_POSITION_WORLD - world_pos);
		float fres = pow(1.0 - max(e.y, 0.0), 4.0);
		// Water does not take light as ground does: it mirrors, and what it mirrors towards someone inside the boat
		// is the sky and the far bank, never the boat's own windows. So the cabin's light and the screen's show on it
		// only as a glint on the ripples' crests, and a trace of scatter. (The first drawing lit it as a floor: a
		// floodlit cream slab round the boat, 2026-11-09.)
		float glint = max(ripple, 0.0) * 0.25 * still;
		// What it mirrors: looked at steeply, the sky overhead; looked along (the far water), what stands low on the
		// far side, which is the bank and its trees, dark. Without that the far water mirrored the bright horizon and
		// a canal at dusk was a sheet of snow.
		float open = smoothstep(0.06, 0.28, e.y);
		vec3 mirrored = mix(COLOR.rgb * 0.6, mix(sky_low, sky_top, 0.45), open) * light * shown;
		c = COLOR.rgb * light * shown + mirrored * fres * (1.0 + ripple * 0.8 * still)
				+ cabin * (0.04 + glint) + screen * (0.02 + glint * 0.5);
		// The Moon's road. A ripple throws the Moon to the eye when it faces half way between the two (`h`); the
		// further that is from straight up, the fewer ripples face so. So the road lies under the Moon, runs from the
		// far water towards the eye, and goes with whoever looks at it, as the real one does: it is no place on the
		// water, and nothing of it passes by. What does pass is the glitter in it, the crests themselves, and that
		// is held still where the ground's pattern is (`still`). Far off the crests are too small to tell apart
		// and the road is an even streak.
		vec3 h = normalize(eye_room) + moon_dir;
		vec2 tilt = h.xz / max(h.y, 0.05);
		float road = exp(-dot(tilt, tilt) / (2.0 * MOON_ROUGH * MOON_ROUGH));
		float crests = texture(noise_tex, g / GROUND_PERIOD * 8.0).a
				* texture(noise_tex, g.yx / GROUND_PERIOD * 5.0 + vec2(0.37)).g * 4.0;
		c += MOON_COLOUR * (moon * MOON_ROAD * road * fres * mix(1.0, crests, still) * shown);
	} else {
		float v = texture(noise_tex, g / GROUND_PERIOD * 4.0).g;
		c = COLOR.rgb * (1.0 + (v - 0.5) * 0.5 * still) * lit;
	}
	float d = distance(world_pos, CAMERA_POSITION_WORLD);
	float f = max(mist * smoothstep(15.0, 140.0, d), smoothstep(120.0, far, d) * 0.85);
	c = mix(c, mix(sky_low, mist_colour, mist) * light * shown, f);
	ALBEDO = c;
}
