// Glass in a built room (scripts/env/systems/kit/procedural.gd glass()): a dome's panes, a window, a windscreen. A
// faint tint and a brighter rim where the view grazes it, lit as the room is (the house lights' level and the
// screen's spill), blended over what is behind. Never blend_mul: the Mobile renderer divides what a shader writes by
// its luminance multiplier (2 with the 10-bit buffer), so a multiply would darken everything behind the glass.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

uniform vec3 colour = vec3(0.62, 0.74, 0.8);
uniform float alpha = 0.06;
uniform float rim = 0.22;
uniform float house_reference = 0.05;
// The sky seen in the glass where the view grazes it (a car's windscreen under an open sky: since 2026-11-08, the
// drive-in); sky_mix 0 (the default) leaves the glass as it was.
uniform vec3 sky_colour : source_color = vec3(0.0);
uniform float sky_mix = 0.0;
// The picture mirrored faintly where the glass faces the screen, and dust on the glass thickest at its foot (world y
// dust_floor) and gone two metres up: since 2026-11-08, the Crater's dome on the Moon. Both 0 (the default) leave the
// glass as it was.
uniform float screen_reflect = 0.0;
uniform float dust = 0.0;
uniform float dust_floor = 0.0;
uniform vec3 dust_colour : source_color = vec3(0.32, 0.31, 0.3);

// env_light, screen_center, screen_glow and the bias light's tint.
#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float level = clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	vec3 light = vec3(level * level * 0.5) + room_light_at(world_pos, 0.8) - vec3(env_light);
	float graze = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	ALBEDO = mix(colour * light, sky_colour, clamp(sky_mix * (0.3 + graze), 0.0, 1.0));
	ALPHA = clamp(alpha + rim * graze, 0.0, 0.5);
	if (screen_reflect > 0.0) {
		// The view mirrored in the pane: where it points at the screen, the picture's colour, soft.
		vec3 r = reflect(normalize(world_pos - CAMERA_POSITION_WORLD), normalize(world_normal));
		float k = pow(max(dot(r, normalize(screen_center - world_pos)), 0.0), 60.0) * screen_reflect * screen_glow;
		ALBEDO = mix(ALBEDO, spill_tint(screen_center) * 0.3, clamp(k * 2.0, 0.0, 1.0));
		ALPHA = clamp(ALPHA + k * 0.07, 0.0, 0.5);
	}
	if (dust > 0.0) {
		float d = dust * (1.0 - smoothstep(0.0, 2.2, world_pos.y - dust_floor));
		ALBEDO = mix(ALBEDO, dust_colour * light, clamp(d / max(ALPHA + d * 0.25, 0.001) * 0.25, 0.0, 1.0));
		ALPHA = clamp(ALPHA + d * 0.25, 0.0, 0.6);
	}
}
