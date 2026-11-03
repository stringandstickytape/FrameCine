// A 360 photo around the viewer as a room (scripts/env/skybox_room.gd, ideas #18): seen from inside a sphere whose UV
// is equirectangular; the photo's centre is straight ahead (-Z). Brightness follows the room's level (global
// env_light), so the room light setting and lights-down during playback dim it like any room.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, specular_disabled;

uniform sampler2D photo : source_color, filter_linear, repeat_enable;
// Turns the photo (fraction of a turn, + to the right).
uniform float yaw = 0.0;

global uniform float env_light;

void fragment() {
	// SphereMesh's U is 0.5 at -Z and falls towards +X; a photo's U rises to the right of its centre: mirror it.
	vec2 uv = vec2(1.0 - UV.x + yaw, UV.y);
	ALBEDO = texture(photo, uv).rgb * env_light;
}
