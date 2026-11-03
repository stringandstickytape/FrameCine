// The zoom lens for 180 / 360 pictures (scripts/play/zoom_lens.gd, ideas #38): a round lens in front of the eyes on
// the line towards the aim. Each fragment looks along its own direction from the eye (per view, so the picture keeps
// its stereo depth), pulled towards the aim by the magnification, turned into the sphere's own space and mapped to
// the picture as the projection meshes map it (scripts/projection_meshes.gd). The picture itself is
// video_common.gdshaderinc's, with the screen's uniforms (the script copies them).
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, cull_disabled, shadows_disabled, specular_disabled;

#include "res://shaders/video_common.gdshaderinc"

// World -> the sphere's own space (its rotation, inverted).
uniform mat3 sphere_inverse = mat3(1.0);
// 0: 180 equirectangular, 1: 360 equirectangular, 2: fisheye (equidistant, fisheye_fov degrees), 3: dual fisheye 360
// (equidistant, the dfe_ values: scripts/play/dual_fisheye.gd, uniforms()).
uniform int projection = 1;
uniform float fisheye_fov = 180.0;
// Dual fisheye 360: per lens, world -> the lens's own turn (inverse), the circle (centre u, v; radius in u, in v) and
// half its field of view (radians); the seam's half band (radians) either side of 90 degrees off straight ahead.
uniform mat3 dfe_front_inverse = mat3(1.0);
uniform mat3 dfe_back_inverse = mat3(1.0);
uniform vec4 dfe_front_circle = vec4(0.25, 0.5, 0.25, 0.5);
uniform vec4 dfe_back_circle = vec4(0.75, 0.5, 0.25, 0.5);
uniform float dfe_front_half_fov = 1.658;
uniform float dfe_back_half_fov = 1.658;
uniform float dfe_blend = 0.05;
// The aim, a unit direction in world space, and the magnification.
uniform vec3 aim = vec3(0.0, 0.0, -1.0);
uniform float magnification = 3.0;
uniform float lens_opacity = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// A direction in the sphere's space -> the position in one eye's picture.
vec2 picture_uv(vec3 d) {
	if (projection == 2) {
		float theta = acos(clamp(-d.z, -1.0, 1.0));
		float phi = atan(d.y, d.x);
		float r = theta / radians(fisheye_fov * 0.5);
		return 0.5 + 0.5 * r * vec2(cos(phi), -sin(phi));
	}
	float span = projection == 0 ? PI : 2.0 * PI;
	float lon = atan(d.x, -d.z);
	float lat = asin(clamp(d.y, -1.0, 1.0));
	return vec2(0.5 + lon / span, 0.5 - lat / PI);
}

// A direction in one lens's own frame (z along the lens) -> its place in the frame.
vec2 circle_uv(vec3 l, vec4 circle, float half_fov) {
	float theta = acos(clamp(l.z, -1.0, 1.0));
	float phi = atan(l.y, l.x);
	float r = theta / half_fov;
	return circle.xy + r * vec2(circle.z * cos(phi), -circle.w * sin(phi));
}

// Dual fisheye 360: the front lens ahead, the back lens behind (its picture mirrored), cross-faded over the seam.
vec3 dual_pixel(vec3 d, int view) {
	vec3 f = dfe_front_inverse * d;
	vec3 b = dfe_back_inverse * d;
	float theta = acos(clamp(-d.z, -1.0, 1.0));
	float w = 1.0 - smoothstep(PI * 0.5 - dfe_blend, PI * 0.5 + dfe_blend, theta);
	vec3 rgb = vec3(0.0);
	if (w > 0.0) {
		vec2 uv = circle_uv(vec3(f.x, f.y, -f.z), dfe_front_circle, dfe_front_half_fov);
		rgb += w * clamp(video_pixel(uv, view), 0.0, 1.0);
	}
	if (w < 1.0) {
		vec2 uv = circle_uv(vec3(-b.x, b.y, b.z), dfe_back_circle, dfe_back_half_fov);
		rgb += (1.0 - w) * clamp(video_pixel(uv, view), 0.0, 1.0);
	}
	return rgb;
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float r = length(c);
	if (r > 1.0) {
		discard;
	}
	vec3 d = normalize(world_pos - CAMERA_POSITION_WORLD);
	vec3 m = normalize(aim + (d - aim) / magnification);
	vec3 rgb;
	if (projection == 3) {
		rgb = dual_pixel(sphere_inverse * m, int(VIEW_INDEX));
	} else {
		vec2 uv = picture_uv(sphere_inverse * m);
		rgb = (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) ? vec3(0.0)
				: clamp(video_pixel(uv, int(VIEW_INDEX)), 0.0, 1.0);
	}
	// A thin light rim, so the lens reads as an object.
	float rim = smoothstep(0.93, 0.97, r);
	ALBEDO = srgb_to_linear(mix(rgb, vec3(0.85), rim)) * brightness;
	ALPHA = lens_opacity;
}
