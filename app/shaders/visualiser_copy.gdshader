// The visualisers' flash limit, remembering (scripts/visualisers/visualiser_host.gd): copies a pass's pixels
// unchanged into a viewport of the same size, so the pass can read this frame's results next frame.
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D source : filter_nearest, repeat_disable;

void fragment() {
	COLOR = texture(source, UV);
}
