// The Screening room 1962's soft lights (scripts/env/systems/kit/screening_1962.gd; docs/environments.md, "Room:
// Screening room 1962"): every glow added over the room, in one mesh and one draw, each vertex naming its kind
// (UV2.x). Since 2026-11-08.
//   0  the pool's light rippling on the ceiling by the window: a web drifting slowly (caustic_map, two copies
//      drifting apart, brightest where their walls meet); COLOR.a how much of it reaches the point
//   1  a flame (UV 0..1 over its quad, y down): a tongue of fire whose edge licks slowly upward (the noise scrolled
//      up through it), white-gold at its root, orange, red at its tips; COLOR.rgb its tint, COLOR.a its own seed
//   2  the fire's glow on the hearth, the floor and the brick round the opening, and the embers' bed: COLOR.rgb its
//      colour, COLOR.a its strength
//   3  the city's lights far below in the valley (city_map; UV across the picture)
// Added over what is behind (black adds nothing), no depth write, both sides, never baked. Nothing here changes fast:
// a point of the web changes about once in four seconds, the fire's level wavers under 3 Hz (the kit's flicker, set
// from the code), the flames lick at a walking pace.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

uniform sampler2D caustic_map : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_map : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D city_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 pool_colour : source_color = vec3(0.3, 0.85, 0.9);
// The pool's lamps (the kit's glow), the fire (the accent lamps and the flicker), the city.
uniform float pool_level = 1.0;
uniform float fire_level = 1.0;
uniform float city_level = 1.0;
// The water's clock (seconds times the kit's water_motion: the Motion setting slows it) and the flames' own.
uniform float water_clock = 0.0;
uniform float flame_clock = 0.0;
// Metres a cell of the ripples' web spans.
uniform float ripple_scale = 0.8;

varying vec3 world_pos;
varying float kind;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	kind = UV2.x;
}

float web(vec2 p) {
	float t = water_clock * 0.05;
	vec2 q = p / (ripple_scale * 4.0);
	float a = 1.0 - smoothstep(0.0, 0.16, texture(caustic_map, q + vec2(t, t * 0.37)).r);
	float b = 1.0 - smoothstep(0.0, 0.16, texture(caustic_map, q * 1.31 + vec2(-t * 0.71, t * 0.53) + 0.37).r);
	return a * b + 0.25 * (a + b);
}

void fragment() {
	vec3 c = vec3(0.0);
	if (kind < 0.5) {
		c = pool_colour * COLOR.a * pool_level * (0.12 + 1.5 * web(world_pos.xz + world_pos.y * 0.6));
	} else if (kind < 1.5) {
		float seed = COLOR.a * 7.3;
		float h = 1.0 - UV.y;
		float x = UV.x - 0.5;
		float n1 = texture(noise_map, vec2(UV.x * 0.55 + seed, UV.y * 0.45 + flame_clock * 0.32)).g;
		float n2 = texture(noise_map, vec2(UV.x * 1.2 - seed, UV.y * 0.9 + flame_clock * 0.7)).b;
		float n = n1 * 0.6 + n2 * 0.4;
		// The tongue sways a little more towards its tip, and narrows; its edge breaks up with the noise.
		float sway = (n1 - 0.5) * 0.35 * h;
		float half_w = 0.42 * pow(max(1.0 - h, 0.0), 0.6) * (0.7 + 0.6 * n);
		float body = 1.0 - smoothstep(half_w * 0.35, half_w, abs(x - sway));
		body *= 1.0 - smoothstep(0.35 + 0.5 * n, 0.98, h);
		body *= smoothstep(0.0, 0.12, h);
		vec3 col = mix(vec3(1.0, 0.82, 0.48), vec3(1.0, 0.45, 0.12), smoothstep(0.08, 0.45, h));
		col = mix(col, vec3(0.75, 0.16, 0.04), smoothstep(0.45, 0.9, h));
		c = col * body * COLOR.rgb * fire_level;
	} else if (kind < 2.5) {
		c = COLOR.rgb * COLOR.a * fire_level;
	} else {
		c = texture(city_map, UV).rgb * COLOR.rgb * city_level;
	}
	ALBEDO = c;
}
