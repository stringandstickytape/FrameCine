// Animated reflective water pool / flooded marble surface for Other Worlds rooms (Cenote cavern, Sunken rotunda,
// Cloud temple reflecting basin, Orbital ring infinity pool). Opaque and unshaded (zero blend overdraw, 1 draw):
// combines deep/shallow water tinting, animated dual-layer caustics web, Fresnel sky reflection, film screen spill
// via env_spill.gdshaderinc, and soft moon/lantern specular glints. Vertex COLOR.r = shallow/edge share (0..1),
// COLOR.g = extra pool glow / moonlight shaft pool (0..1).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled, fog_disabled;

uniform sampler2D caustic_map : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float clock = 0.0;
uniform float house_reference = 0.05;
uniform vec3 deep_colour : source_color = vec3(0.02, 0.14, 0.19);
uniform vec3 shallow_colour : source_color = vec3(0.08, 0.38, 0.42);
uniform vec3 sky_colour : source_color = vec3(0.16, 0.28, 0.38);
uniform vec3 caustic_colour : source_color = vec3(0.36, 0.88, 0.92);
uniform float caustic_level = 0.85;
uniform float ripple_scale = 2.4;
uniform float spill_strength = 0.65;
uniform vec3 glint_dir = vec3(0.0, 0.65, -0.76);
uniform vec3 glint_colour : source_color = vec3(0.75, 0.92, 1.0);
uniform float glint_level = 0.55;
uniform float ambient_floor = 0.35;

#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float caustic_web(vec2 p, float t) {
	vec2 q = p / max(ripple_scale, 0.2);
	float a = 1.0 - smoothstep(0.0, 0.19, texture(caustic_map, q + vec2(t * 0.032, t * 0.019)).r);
	float b = 1.0 - smoothstep(0.0, 0.19, texture(caustic_map, q * 1.29 + vec2(-t * 0.025, t * 0.029) + 0.37).r);
	return a * b * 1.3 + 0.25 * (a + b);
}

void fragment() {
	float level = clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	float vis = max(ambient_floor, level * 0.85);
	vec2 p = world_pos.xz;
	float w1 = sin(p.x * 2.1 + p.y * 1.4 + clock * 1.15);
	float w2 = sin(p.x * -1.7 + p.y * 2.5 - clock * 0.92);
	float w3 = cos((p.x + p.y) * 3.4 + clock * 0.74);
	vec3 n = normalize(vec3((w1 + w3 * 0.5) * 0.045, 1.0, (w2 - w3 * 0.5) * 0.045));
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, 3.2);

	float web = caustic_web(p, clock);
	vec3 body = mix(deep_colour, shallow_colour, clamp(COLOR.r, 0.0, 1.0));
	body += caustic_colour * web * caustic_level * (0.45 + 0.75 * COLOR.r + 0.85 * COLOR.g);

	vec3 refl = sky_colour * (0.28 + 0.72 * fresnel);
	// Film screen spill rippling softly across the water surface.
	float d = distance(world_pos, screen_center);
	vec3 film = spill_strength * screen_glow / (1.0 + 0.035 * d * d) * spill_tint(world_pos);
	refl += film * (0.25 + 0.75 * fresnel) * (0.78 + 0.22 * (w1 * w2));

	// Soft specular shimmer from moonlight shaft, oculus, or lanterns.
	vec3 hvec = normalize(normalize(glint_dir) + v);
	float spec = pow(clamp(dot(n, hvec), 0.0, 1.0), 42.0) * glint_level;
	vec3 col = mix(body, refl, clamp(0.18 + fresnel * 0.62, 0.0, 0.85)) + glint_colour * spec;
	col += caustic_colour * COLOR.g * 0.42 * (0.75 + 0.25 * web);
	ALBEDO = col * vis;
}
