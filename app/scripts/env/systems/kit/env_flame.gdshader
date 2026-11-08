// A flame, a neon tube's halo or another glow with soft edges in a built room (scripts/env/systems/kit/builder.gd
// _glow()): the picture's colours times colour and energy, added over what is behind (black adds nothing). Never
// blend_mul (the Mobile renderer's luminance multiplier); an add is safe. No depth write, both sides.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

uniform vec3 colour : source_color = vec3(1.0);
uniform float energy = 1.0;
uniform sampler2D picture : source_color, filter_linear_mipmap;
// The mesh's vertex colours times colour (halos of several colours in one draw: a drive-in's neon). Since 2026-11-08;
// off by default.
uniform bool use_vertex_colour = false;

void fragment() {
	ALBEDO = colour * texture(picture, UV).rgb * energy * (use_vertex_colour ? COLOR.rgb : vec3(1.0));
}
