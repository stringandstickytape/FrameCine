// The Void's floor (scripts/env/systems/mirror_floor.gd): mirror-black, unlit, with up to four ripples, each a faint
// ring spreading from where the viewer moved. The floor reflection (floor_reflection.gd) is blended over it.
//   ripples[i]   x, z: the ring's centre (world); w: its strength (0: none); age in ripple_age[i] (seconds)
// A ring: radius = speed x age, a soft band `width` wide, fading out over `life` seconds. Its brightness changes
// slowly (a ring takes life seconds to fade): far under the photosensitivity ceiling.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled;

uniform vec3 albedo : source_color = vec3(0.01, 0.01, 0.012);
uniform vec3 ring_colour : source_color = vec3(0.55, 0.6, 0.7);
uniform vec4 ripples[4];
uniform float ripple_age[4];
uniform float speed = 0.6;
uniform float width = 0.05;
uniform float life = 2.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float ring = 0.0;
	for (int i = 0; i < 4; i++) {
		float s = ripples[i].w;
		if (s <= 0.0) {
			continue;
		}
		float age = ripple_age[i];
		float d = length(world_pos.xz - ripples[i].xz);
		float r = speed * age;
		float band = exp(-pow((d - r) / width, 2.0));
		float fade = clamp(1.0 - age / life, 0.0, 1.0);
		ring += band * fade * fade * s;
	}
	ALBEDO = albedo + ring_colour * clamp(ring, 0.0, 1.0) * 0.08;
}
