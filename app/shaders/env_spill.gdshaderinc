// The screen's light on the room, shared by the environment shaders (env_unlit, env_unlit_tex, grid). The room's
// brightness is its ambient level (global env_light) plus a fall-off "spill" from the screen (screen_center,
// screen_glow). With the bias light (scripts/env/bias_light.gd, ideas #29) the spill takes the picture's colour
// and brightness: screen_thumb is a tiny, time-smoothed copy of the picture (4 x 2 cells, each the mean of its part),
// and a point takes the colour of the picture's side nearest to it (screen_axis: the screen's right direction over
// its width). screen_tint 0 leaves the spill white, as before.

global uniform float env_light;
global uniform vec3 screen_center;
global uniform float screen_glow;
global uniform sampler2D screen_thumb : filter_linear;
global uniform float screen_tint;
global uniform vec3 screen_axis;

// A picture of this mean linear brightness lights the room as designed (a typical film's: sRGB about 0.38).
const float SPILL_REFERENCE = 0.12;
const float SPILL_MAX = 2.5;

vec3 spill_srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// The colour (and brightness) of the screen's spill at world position p: white without the bias light.
vec3 spill_tint(vec3 p) {
	if (screen_tint <= 0.0) {
		return vec3(1.0);
	}
	float u = clamp(0.5 + dot(p - screen_center, screen_axis), 0.125, 0.875);
	vec3 c = spill_srgb_to_linear(textureLod(screen_thumb, vec2(u, 0.5), 0.0).rgb);
	return mix(vec3(1.0), min(c / SPILL_REFERENCE, vec3(SPILL_MAX)), screen_tint);
}

// The room's light at p: ambient plus the screen's spill (catch: how much the surface catches it).
vec3 room_light_at(vec3 p, float catch) {
	float d = distance(p, screen_center);
	return vec3(env_light) + catch * screen_glow / (1.0 + 0.05 * d * d) * spill_tint(p);
}
