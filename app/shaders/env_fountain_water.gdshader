// A courtyard fountain's water (scripts/env/systems/kit/courtyard.gd; docs/environments.md, "Room: Atmospheric
// 1928"): the basin's surface and the jet that falls into it. Opaque and small. Vertex colour r: 0 the basin, 1 the
// jet; g, b: where the jet lands in the basin's UV (metres / 4). UV in metres (RoomMesh's charts; the jet's u runs
// along its fall). The basin: dark water holding a little of the sky and the lamps, rings spreading from where the
// jet lands; the jet: glassy streaks running down it. `clock` is seconds times the water's motion (kit.gd: the
// Motion setting stills it): a ring or a streak passes a point under once a second (0.83 and 0.88 Hz at full).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled, fog_disabled;

uniform float clock = 0.0;
uniform float motion = 1.0;
uniform float house_reference = 0.05;
uniform vec3 deep : source_color = vec3(0.03, 0.06, 0.07);
uniform vec3 sky : source_color = vec3(0.16, 0.22, 0.36);
uniform vec3 lamp : source_color = vec3(1.0, 0.7, 0.4);

#include "res://shaders/env_spill.gdshaderinc"

void fragment() {
	float level = clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	level = max(level * level, 0.08);
	vec3 c;
	if (COLOR.r > 0.5) {
		// The jet: clear water, so mostly the dark behind it and a little sky, with glints of the lamp running down
		// it (a pale solid stream read as a stick, 2026-11-08).
		float along = UV.x;
		float s1 = 0.5 + 0.5 * sin(along * 26.0 - clock * 5.0);
		float s2 = 0.5 + 0.5 * sin(along * 41.0 - clock * 5.5 + 1.7);
		float glint = pow(s1 * s2, 3.0);
		c = deep + sky * 0.45 + lamp * (0.12 + 0.75 * glint);
	} else {
		vec2 at = COLOR.gb * 4.0;
		float r = length(UV - at);
		// Rings from where the jet lands, fading outwards; a calm sheen beyond them.
		float ring = 0.5 + 0.5 * sin(r * 38.0 - clock * 5.2);
		ring *= exp(-r * 5.0);
		float sheen = 0.5 + 0.5 * sin(UV.x * 7.0 + UV.y * 5.0 + clock * 0.6);
		c = deep + sky * (0.25 + 0.15 * sheen) + lamp * ring * 0.45;
		c += lamp * 0.6 * exp(-r * r * 60.0);
	}
	ALBEDO = c * level;
}
