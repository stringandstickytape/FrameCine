// Surfaces of an assistant's room with real lighting (scripts/assistant/assistant_room.gd, the room document's
// light.key / light.sky / light.screen / lights): lit by the engine's lights (the key light, sun or moon, with its
// shadows; a few point lights), plus, added here as emission (no light pass, nearly free):
//   - a hemisphere fill (light.sky): one colour from above, one from below, blended by the surface's normal, so the
//     shade side is not flat;
//   - the screen's light (light.screen): the film's colour and brightness, from the bias light's smoothed 4 x 2 copy
//     of the picture (0.25 s: never faster than the photosensitivity ceiling), falling off with distance and facing;
//   - a darkening where a surface meets the floor (contact occlusion), so parts sit on the ground.
// The base room's own surfaces get it too when the room is lit. No tone mapping (the film must stay exact): the
// energies are bounded so a lit surface stays below 1.0 (docs/assistant.md, "Lighting").
// Compiled again with ALPHA_CUT or ALPHA_BLEND for transparent pictures (as env_unlit_tex.gdshader).
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;
#ifdef ALPHA_CUT
render_mode alpha_to_coverage;
#endif

uniform vec3 albedo : source_color = vec3(1.0);
uniform float alpha = 1.0;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_texture = false;
uniform vec3 emission : source_color = vec3(0.0);
uniform float roughness = 0.85;
// Specular highlights: 0 for paintings and pictures (their colours exact), a little for stone and wood.
uniform float specular = 0.2;
// The fill's colours as picked (#rrggbb read as they look, times light.sky.energy), not converted to linear light:
// a fill is a mood, and "#4a5878 at 0.35" should read as a visible blue shade, not black.
uniform vec3 sky_top = vec3(0.0);
uniform vec3 sky_bottom = vec3(0.0);
uniform float screen_light = 0.0;
// How far contact occlusion reaches up from the floor (metres) and how dark it gets at the floor.
uniform float contact_height = 0.5;
uniform float contact_strength = 0.35;
uniform float floor_y = 0.0;

#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// The picture's colour nearest p (its left or right half), as linear light, scaled so a typical film reads as 1.
vec3 film_colour(vec3 p) {
	float u = clamp(0.5 + dot(p - screen_center, screen_axis), 0.125, 0.875);
	vec3 c = spill_srgb_to_linear(textureLod(screen_thumb, vec2(u, 0.5), 0.0).rgb);
	return min(c / SPILL_REFERENCE, vec3(SPILL_MAX));
}

void fragment() {
	vec4 tex = use_texture ? texture(albedo_texture, UV) : vec4(1.0);
	vec3 base = albedo * tex.rgb;
	ALBEDO = base;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	vec3 n = normalize(world_normal);
	float occlusion = mix(1.0 - contact_strength, 1.0, smoothstep(0.0, contact_height, world_pos.y - floor_y));
	vec3 fill = mix(sky_bottom, sky_top, n.y * 0.5 + 0.5);
	vec3 film = vec3(0.0);
	if (screen_light > 0.0) {
		vec3 to = screen_center - world_pos;
		float d = length(to);
		float facing = clamp(dot(n, to / max(d, 0.001)) * 0.75 + 0.25, 0.0, 1.0);
		film = film_colour(world_pos) * screen_light * facing / (1.0 + 0.08 * d * d);
	}
	EMISSION = base * (fill + film) * occlusion + emission;
	AO = occlusion;
	AO_LIGHT_AFFECT = 0.6;
#if defined(ALPHA_CUT)
	ALPHA = alpha * tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_texture, 0));
#elif defined(ALPHA_BLEND)
	ALPHA = alpha * tex.a;
#endif
}
