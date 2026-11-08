// Cove light (scripts/env/systems/kit/streamline.gd; docs/environments.md, "Room: Streamline 1937"): plaster washed by
// a lamp hidden in a trough, the light graded across the curved surface as a real cove's is, from bright by the trough
// to nothing a few metres off, in a colour that can change live (the Streamline's coves go gold, rose, jade, blue).
// Since 2026-11-08 ("the coves are the star: soft graded colour washing up curved surfaces, not flat fog quads", the
// brief). Opaque and cheap: one noise fetch, no loop, no light pass; a bake does not take it (gi off).
// Vertex colour: rgb the surface's own colour (linear), a the cove's light on it there (0..1, worked out from the
// trough's place when the mesh is built: distance and facing).
// The rest of its light is the house shader's: the hemisphere fill at the house level (env_light over
// house_reference, squared, with a floor), the screen's spill with the bias light's colour (env_spill.gdshaderinc).
//   glow          the cove's energy now (the kit: its `cove` times the house lamps' level)
//   glow_colour   the cove's colour now (the kit: cove_colour toward cove_film_colour by cove_film)
shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled, ambient_light_disabled;

uniform vec3 glow_colour : source_color = vec3(1.0, 0.74, 0.42);
uniform float glow = 1.0;
uniform vec3 sky_top = vec3(0.3, 0.25, 0.2);
uniform vec3 sky_bottom = vec3(0.1, 0.08, 0.07);
uniform float house_reference = 0.05;
uniform float house_floor = 0.04;
uniform float spill = 1.0;
// A slow mottle in the plaster (sky.gd noise_texture(): four channels of seamless noise), metres a repeat.
uniform sampler2D mottle : filter_linear_mipmap, repeat_enable;
uniform float mottle_scale = 7.0;
uniform float mottle_amount = 0.05;
uniform bool bake_pass = false;

#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float level = bake_pass ? 1.0 : clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	level = max(level * level, house_floor);
	// The mottle, projected along the surface's main axis.
	vec3 a = abs(n);
	vec2 p = a.y > max(a.x, a.z) ? world_pos.xz : (a.x > a.z ? world_pos.zy : world_pos.xy);
	vec4 m = texture(mottle, p / mottle_scale);
	vec3 base = COLOR.rgb * (1.0 + mottle_amount * ((m.r + m.g) - 1.0));
	vec3 fill = mix(sky_bottom, sky_top, n.y * 0.5 + 0.5) * level;
	vec3 to = screen_center - world_pos;
	float d = length(to);
	float facing = clamp(dot(n, to / max(d, 0.001)) * 0.75 + 0.25, 0.0, 1.0);
	vec3 film = spill * screen_glow * spill_tint(world_pos) * facing / (1.0 + 0.05 * d * d);
	// The cove's light: its colour, a whiter core where it is strongest (a lamp close by), times the house level as
	// every house light is.
	float w = COLOR.a;
	vec3 cove = (glow_colour * w + mix(glow_colour, vec3(1.0), 0.45) * w * w * w * 0.8) * glow * level;
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	EMISSION = bake_pass ? vec3(0.0) : base * (fill + film + cove);
}
