// A car's lit instruments (scripts/env/systems/vehicle.gd; since 2026-11-08): room_lamp.gdshader's glow (emission
// only, a light group's level, the bake's view) of a picture of the dials' faces, and the clock's two hands drawn
// over it at the time the sky shows (`hour`, so the clock on the dashboard keeps the night's time as the stars turn).
shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled, ambient_light_disabled;

uniform vec3 colour : source_color = vec3(1.0);
uniform float energy = 1.0;
uniform float follows_house = 0.0;
uniform float house_reference = 0.05;
uniform sampler2D picture : source_color, filter_linear_mipmap;
uniform bool use_picture = true;
uniform bool bake_pass = false;
// The clock's face in the picture (UV centre and radius) and the time (hours, 0..24).
uniform vec2 clock_centre = vec2(0.75, 0.75);
uniform float clock_radius = 0.2;
uniform float hour = 21.0;
uniform vec3 hand_colour : source_color = vec3(0.9, 1.0, 0.95);

#include "res://shaders/env_spill.gdshaderinc"

// How much of a hand (from the centre at angle a, clockwise from 12) covers p: its length and half width in radii.
float hand(vec2 p, float a, float len, float half_w) {
	vec2 dir = vec2(sin(a), -cos(a));
	float t = clamp(dot(p, dir), -0.12, len);
	float d = length(p - dir * t);
	float w = half_w * (1.0 - 0.5 * max(t, 0.0) / len);
	return 1.0 - smoothstep(w, w + 0.025, d);
}

void fragment() {
	float level = bake_pass ? 1.0 : clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	level *= level;
	vec3 c = colour;
	if (use_picture) {
		c *= texture(picture, UV).rgb;
	}
	// The picture is twice as wide as high: the clock's round face in UV stretched back to a circle.
	vec2 p = (UV - clock_centre) * vec2(2.0, 1.0) / clock_radius;
	if (dot(p, p) < 1.0) {
		float h = mod(hour, 12.0);
		float m = fract(hour);
		float k = max(hand(p, h / 12.0 * 6.2831853, 0.5, 0.07), hand(p, m * 6.2831853, 0.8, 0.045));
		c = mix(c, colour * hand_colour, k);
	}
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	EMISSION = c * energy * mix(1.0, level, follows_house);
}
