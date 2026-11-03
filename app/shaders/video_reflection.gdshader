// The screen's reflection on the floor (scripts/env/floor_reflection.gd, ideas #62): drawn on one flat quad lying on
// the floor in front of the screen, blended over the floor. Each floor point shows the part of the picture a mirror
// there would: the line from the eye mirrored under the floor through the point meets the screen's plane at that
// part (per view, so it has the right depth in stereo). Fades out with the distance from the screen's bottom edge.
// The picture comes from video_common.gdshaderinc with the screen's own uniforms (the script copies them).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;

#include "res://shaders/video_common.gdshaderinc"

// World -> the screen's local space (centre at the origin, the picture in the XY plane, facing +Z).
uniform mat4 screen_inverse;
// The flat picture's size in metres.
uniform vec2 screen_size = vec2(3.0, 1.7);
uniform float floor_y = 0.0;
// Reflectance at the bottom edge (0..1), and how much of the picture's height shows (from its bottom).
uniform float strength = 0.25;
uniform float fade = 0.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 eye = CAMERA_POSITION_WORLD;
	vec3 mirrored = vec3(eye.x, 2.0 * floor_y - eye.y, eye.z);
	vec3 e = (screen_inverse * vec4(mirrored, 1.0)).xyz;
	vec3 q = (screen_inverse * vec4(world_pos, 1.0)).xyz;
	float t = e.z / max(e.z - q.z, 1e-4);
	vec3 s = e + t * (q - e);
	vec2 uv = vec2(s.x / screen_size.x + 0.5, 0.5 - s.y / screen_size.y);
	float a = strength * smoothstep(1.0 - fade, 1.0, uv.y);
	if (t < 1.0 || uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		a = 0.0;
	}
	ALBEDO = srgb_to_linear(clamp(video_pixel(uv, int(VIEW_INDEX)), 0.0, 1.0)) * brightness;
	ALPHA = a;
}
