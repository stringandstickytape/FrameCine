// A marquee's bulbs (scripts/env/systems/kit/drive_in_lot.gd; since 2026-11-08, the drive-in): round glows on quads,
// added over what is behind, each bulb's place in the run in UV2.x. `chase` 1: a slow wave runs along them (every bulb
// brightens and dims under once a second, smoothly: under the photosensitivity ceiling, room_schema.gd MAX_HZ); 0: all
// steady at their mean. `phase` is the run's clock (scripts advance it), `energy` the group's level.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

uniform vec3 colour : source_color = vec3(1.0, 0.85, 0.55);
uniform float energy = 1.0;
uniform float chase = 1.0;
uniform float phase = 0.0;
uniform sampler2D picture : source_color, filter_linear_mipmap;

void fragment() {
	// Three bulbs a wave: a bulb's light goes round a cosine as the wave passes.
	float w = 0.5 + 0.5 * cos(6.2831853 * (UV2.x / 3.0 - phase));
	float lit = mix(0.6, 0.18 + 0.82 * w * w, chase);
	ALBEDO = colour * texture(picture, UV).rgb * energy * lit;
}
