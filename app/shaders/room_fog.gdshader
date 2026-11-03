// Low fog near the floor (scripts/assistant/assistant_room.gd, the room document's "atmosphere": {"fog": ...}):
// a few thin horizontal layers stacked up to the fog's height, thicker near the floor, all cut from one slowly
// drifting noise field (each layer a little further along it), so the wisps stack into soft volumes instead of
// averaging out. Faint each, so where a layer meets a chair the line is faint too. Inside a room whose walls are
// known the layers end a little short of the walls and fade out over the last metre (no lines on the walls); in an
// open room they fade out radially. Faded where the eye looks along a layer; dithered against banding. No depth
// texture: on the Mobile renderer that would cost a copy every frame.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, specular_disabled, fog_disabled;

uniform vec3 fog_color : source_color = vec3(0.75, 0.8, 0.85);
// The layer's share of the fog's opacity.
uniform float opacity = 0.1;
uniform float speed = 0.3;
// The layer's place in the stack, 0 (floor) to 1 (top).
uniform float level = 0.0;
// Half the layer's size in metres; boxed: fade towards the sides (walls), else radially.
uniform vec2 half_size = vec2(5.0);
uniform bool boxed = false;

#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;
varying vec2 local;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The quad is 2 x 2 units, scaled to the layer's size: local runs -1..1 to its edges.
	local = VERTEX.xz;
}

float fog_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float fog_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(fog_hash(i), fog_hash(i + vec3(1, 0, 0)), f.x),
			mix(fog_hash(i + vec3(0, 1, 0)), fog_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(fog_hash(i + vec3(0, 0, 1)), fog_hash(i + vec3(1, 0, 1)), f.x),
			mix(fog_hash(i + vec3(0, 1, 1)), fog_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec2 drift = vec2(TIME * speed * 0.08, TIME * speed * 0.03);
	// One field for the stack: the layer's height is a slow third axis.
	vec3 p = vec3(world_pos.xz * 0.8 + drift, level * 0.9 + TIME * 0.015);
	float n = fog_noise(p) * 0.55 + fog_noise(p * 2.1 + vec3(5.2, 1.3, 0.0)) * 0.3
			+ fog_noise(p * 4.3 + vec3(2.7, 8.1, 0.0)) * 0.15;
	float wisps = smoothstep(0.32, 0.78, n);
	vec2 m = abs(local) * half_size;
	float edge;
	if (boxed) {
		vec2 room = smoothstep(vec2(0.0), vec2(1.0), half_size - m);
		edge = room.x * room.y;
	} else {
		edge = 1.0 - smoothstep(0.35, 1.0, length(local));
	}
	// Looking along the layer it would pile up into a line: fade it as the view grazes it.
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float graze = smoothstep(0.03, 0.25, abs(v.y));
	float a = opacity * (0.12 + 0.88 * wisps) * edge * graze;
	a += (fog_hash(vec3(FRAGCOORD.xy, level * 13.0)) - 0.5) / 255.0;
	// Lit by the room: pale in a bright room, dim in a dark one.
	ALBEDO = fog_color * min(room_light_at(world_pos, 0.6) * 1.5 + 0.1, vec3(1.2));
	ALPHA = clamp(a, 0.0, 1.0);
}
