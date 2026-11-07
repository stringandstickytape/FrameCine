// A puddle that reflects the film (scripts/env/systems/weather.gd): a quad on the floor with a ragged edge, dark water
// blended over the floor, and in it the part of the picture a mirror there would show (the eye mirrored under the
// water, as video_reflection.gdshader; the picture from video_common.gdshaderinc with the screen's own uniforms,
// which the script copies). While it rains, rings spread from where drops land and bend the reflection. Without a
// picture (no film, a test) the water takes the film's colours from the bias light instead.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

#include "res://shaders/video_common.gdshaderinc"
#include "res://shaders/env_spill.gdshaderinc"

// World -> the screen's local space (centre at the origin, the picture in the XY plane, facing +Z).
uniform mat4 screen_inverse;
uniform vec2 screen_size = vec2(3.0, 1.7);
uniform float water_y = 0.0;
// The puddle's half size in metres (the quad's), and its edge's seed.
uniform vec2 half_size = vec2(1.0, 0.7);
uniform float seed = 0.0;
// How much of the picture the water gives back (0..1), rain falling now (0..1), and whether there is a picture.
uniform float strength = 0.6;
uniform float rain = 0.0;
uniform bool has_picture = false;
uniform vec3 water : source_color = vec3(0.012, 0.014, 0.018);

varying vec3 world_pos;
varying vec2 local;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local = VERTEX.xz;
}

float puddle_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float puddle_noise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(puddle_hash(i), puddle_hash(i + vec2(1, 0)), f.x),
			mix(puddle_hash(i + vec2(0, 1)), puddle_hash(i + vec2(1, 1)), f.x), f.y);
}

// Rings where drops land: one per cell, at its own moment in a short cycle. Returns the slope (a 2D push).
vec2 ripples(vec2 m, float amount) {
	vec2 push = vec2(0.0);
	for (int k = 0; k < 2; k++) {
		vec2 q = m / 0.22 + float(k) * 0.5;
		vec2 id = floor(q);
		float h = puddle_hash(id + float(k) * 13.0);
		if (h > amount) {
			continue;
		}
		float t = fract(TIME * (0.9 + 0.5 * h) + h * 7.0);
		vec2 at = id + 0.25 + 0.5 * vec2(puddle_hash(id + 3.0), puddle_hash(id + 5.0));
		vec2 d = q - at;
		float r = length(d);
		float ring = sin((r - t * 0.45) * 55.0) * (1.0 - smoothstep(0.0, 0.08, abs(r - t * 0.45))) * (1.0 - t);
		push += normalize(d + 1e-4) * ring;
	}
	return push;
}

void fragment() {
	// The ragged edge: an ellipse pushed in and out by noise.
	vec2 e = local / half_size;
	float edge = length(e) + (puddle_noise(local * 2.2 + seed) - 0.5) * 0.45 + (puddle_noise(local * 6.0 + seed) - 0.5) * 0.12;
	float mask = 1.0 - smoothstep(0.72, 0.9, edge);
	vec2 push = ripples(world_pos.xz, clamp(rain, 0.0, 1.0) * 0.85) * 0.012;
	vec3 eye = CAMERA_POSITION_WORLD;
	vec3 mirrored = vec3(eye.x, 2.0 * water_y - eye.y, eye.z);
	vec3 pe = (screen_inverse * vec4(mirrored, 1.0)).xyz;
	vec3 pq = (screen_inverse * vec4(world_pos + vec3(push.x, 0.0, push.y), 1.0)).xyz;
	float t = pe.z / max(pe.z - pq.z, 1e-4);
	vec3 s = pe + t * (pq - pe);
	vec2 uv = vec2(s.x / screen_size.x + 0.5, 0.5 - s.y / screen_size.y);
	// Soft at the picture's edges: rippled water blurs them.
	vec2 soft = smoothstep(vec2(-0.02), vec2(0.04), uv) * (1.0 - smoothstep(vec2(0.96), vec2(1.02), uv));
	float inside = t < 1.0 ? 0.0 : soft.x * soft.y;
	vec3 picture;
	if (has_picture) {
		picture = srgb_to_linear(clamp(video_pixel(clamp(uv, 0.0, 1.0), int(VIEW_INDEX)), 0.0, 1.0)) * brightness;
	} else {
		vec3 across = screen_axis * (clamp(uv.x, 0.0, 1.0) - 0.5) / max(dot(screen_axis, screen_axis), 1e-6);
		picture = vec3(screen_glow * 0.12) * spill_tint(screen_center + across);
	}
	// Water gives back more at a grazing view (a cheap Fresnel).
	vec3 v = normalize(eye - world_pos);
	float fresnel = mix(0.35, 1.0, pow(1.0 - clamp(v.y, 0.0, 1.0), 3.0));
	float k = strength * fresnel * inside;
	ALBEDO = mix(water * min(room_light_at(world_pos, 0.5) + vec3(0.2), vec3(1.0)), picture, k);
	ALPHA = mask * mix(0.7, 1.0, k);
}
