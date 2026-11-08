// A cinema clock's face (scripts/env/systems/kit/streamline.gd; docs/environments.md, "Room: Streamline 1937"): frosted
// glass lit from behind, chevrons for the hours, faint sunburst rays, and two hands drawn here from their angles (the
// kit sets them from the real time each second: the hands move as slowly as a clock's do). Emission only, as the
// light system's lamps (room_lamp.gdshader): the house lights' level dims it with the film. UV: 0..1 across the face,
// (0.5, 0.5) its centre, v down. Since 2026-11-08.
shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled, ambient_light_disabled;

uniform vec3 colour : source_color = vec3(1.0, 0.86, 0.66);
uniform vec3 mark_colour : source_color = vec3(0.16, 0.1, 0.05);
uniform float energy = 1.0;
uniform float follows_house = 1.0;
uniform float house_reference = 0.05;
// Radians clockwise from twelve.
uniform float hour_angle = 0.0;
uniform float minute_angle = 0.0;
uniform bool bake_pass = false;
// The face (since 2026-11-08): 0 the moderne one above; 1 the 1970s one (the Palace of Culture's): a dark dial, lit
// bars for the hours (the quarters longer and broader), dots for the minutes, slim hands in the light's colour.
uniform int style = 0;

#include "res://shaders/env_spill.gdshaderinc"

// 1 inside a hand from the centre along angle a (clockwise from twelve), this long and half this wide.
float hand(vec2 p, float a, float len, float half_w, float tail) {
	vec2 dir = vec2(sin(a), cos(a));
	float along = dot(p, dir);
	float across = abs(dot(p, vec2(dir.y, -dir.x)));
	float taper = mix(1.0, 0.35, clamp(along / len, 0.0, 1.0));
	float aa = 0.006;
	return (1.0 - smoothstep(half_w * taper - aa, half_w * taper + aa, across))
			* smoothstep(-tail - aa, -tail + aa, along) * (1.0 - smoothstep(len - aa, len + aa, along));
}

void fragment() {
	float level = bake_pass ? 1.0 : clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	level *= level;
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y);
	float r = length(p);
	float ang = atan(p.x, p.y);
	if (style == 1) {
		float hour = ang / (TAU / 12.0);
		float k = round(hour);
		float across = abs((hour - k) * (TAU / 12.0)) * r;
		bool quarter = mod(k, 3.0) == 0.0;
		float lit = (1.0 - smoothstep(quarter ? 0.017 : 0.01, quarter ? 0.024 : 0.016, across))
				* step(quarter ? 0.3 : 0.34, r) * step(r, 0.44);
		float mins = ang / (TAU / 60.0);
		float md = length(vec2(abs(mins - round(mins)) * (TAU / 60.0) * r, r - 0.465));
		lit = max(lit, (1.0 - smoothstep(0.004, 0.008, md)) * 0.7);
		lit = max(lit, hand(p, hour_angle, 0.25, 0.018, 0.05));
		lit = max(lit, hand(p, minute_angle, 0.4, 0.012, 0.07));
		lit = max(lit, 1.0 - smoothstep(0.02, 0.028, r));
		vec3 dial = mark_colour * (1.0 + 0.4 * (1.0 - smoothstep(0.0, 0.5, r)));
		vec3 c1 = mix(dial, colour, lit);
		c1 *= 1.0 - 0.8 * smoothstep(0.48, 0.5, r);
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		EMISSION = c1 * energy * mix(1.0, level, follows_house);
	} else {
		// The glass: brighter towards the middle (the lamp behind it), faint rays of a sunburst.
		vec3 glass = colour * mix(1.0, 0.62, smoothstep(0.0, 0.46, r));
		float rays = 0.5 + 0.5 * cos(ang * 24.0);
		glass *= 1.0 - 0.12 * rays * smoothstep(0.1, 0.4, r);
		float ink = 0.0;
		// The hours: a chevron at twelve, three, six and nine, a bar at the others.
		float hour = ang / (TAU / 12.0);
		float k = round(hour);
		float da = (hour - k) * (TAU / 12.0);
		float along = r;
		float across = abs(da) * r;
		bool quarter = mod(k, 3.0) == 0.0;
		if (quarter) {
			// A chevron pointing in: two strokes meeting on the radius.
			float chev = abs(across - (0.43 - along) * 0.55);
			ink = max(ink, (1.0 - smoothstep(0.008, 0.016, chev)) * step(0.34, along) * step(along, 0.43));
		} else {
			ink = max(ink, (1.0 - smoothstep(0.008, 0.014, across)) * step(0.36, along) * step(along, 0.43));
		}
		// The minutes: fine ticks at the rim.
		float mins = ang / (TAU / 60.0);
		float mt = abs(mins - round(mins)) * (TAU / 60.0) * r;
		ink = max(ink, (1.0 - smoothstep(0.002, 0.005, mt)) * step(0.445, r) * step(r, 0.47) * 0.8);
		// The hands and the boss.
		ink = max(ink, hand(p, hour_angle, 0.25, 0.022, 0.04));
		ink = max(ink, hand(p, minute_angle, 0.38, 0.014, 0.06));
		ink = max(ink, 1.0 - smoothstep(0.022, 0.03, r));
		vec3 c = mix(glass, mark_colour, ink);
		// The rim: a dark ring where the glass meets the bezel.
		c *= 1.0 - 0.7 * smoothstep(0.47, 0.5, r);
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		EMISSION = c * energy * mix(1.0, level, follows_house);
	}
}
