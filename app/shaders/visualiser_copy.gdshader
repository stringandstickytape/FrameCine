// The visualisers' flash limit, remembering half (scripts/visualisers/visualiser_host.gd): copies the measuring
// viewport's pixel (all four are the same) unchanged, so next frame's measure can read this frame's floor.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D source : filter_nearest, repeat_disable;

void fragment() {
	COLOR = texture(source, vec2(0.5));
}
