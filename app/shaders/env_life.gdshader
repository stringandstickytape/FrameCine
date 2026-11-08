// Ambient life's bodies (scripts/env/systems/life.gd, docs/environments.md "Ambient life"): moths, birds, fish, the
// cat, the deer and the whale, low-poly meshes animated here in the vertex shader. Unlit: the room's light (ambient
// plus the screen's spill, env_spill.gdshaderinc) on the creature's colour, plus a light of its own where it flies
// through the projector's beam (lit). A fade (dithered, so the body stays opaque and sorts like any other) lets one
// come out of the dark and go again.
//
// The mesh carries weights: UV.x the wings (rotate about the body's long axis), UV.y the legs (0 at the hip, 1 at the
// foot: they swing in a diagonal gait), UV2.x the body's wave (fish, the whale's flukes, a cat's tail), UV2.y the head
// and neck (bow down to graze). Per instance (a MultiMesh's custom data, or single_custom for a single creature):
// x the animation's phase (cycles), y how much it moves (flap, gait), z the beam's light on it, w its pose (a bird's
// folded wings, a cat sitting, a deer grazing). The instance colour (or single_tint): a tint, its alpha the fade.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;

uniform vec3 colour : source_color = vec3(0.5);
// How much the body catches the screen's light.
uniform float spill = 1.0;
// The beam's light where lit is 1 (the projector's warm white).
uniform vec3 lit_colour : source_color = vec3(1.0, 0.95, 0.85);
// Wings: the flap's amplitude (radians), and how far the pose folds them in.
uniform float flap = 0.0;
uniform float fold = 0.0;
// Legs: how far a foot swings (metres).
uniform float stride = 0.0;
// The body's wave: sideways (metres at the tail) and waves along the body (radians a metre).
uniform float sway = 0.0;
uniform float waves = 0.0;
// The wave goes up and down instead (a whale's flukes).
uniform bool sway_up = false;
// Poses (radians at pose 1): sitting (the body pitched up about the rear hip), grazing (the head bowed at the neck).
uniform float sit = 0.0;
uniform vec3 pivot_rear = vec3(0.0);
uniform float graze = 0.0;
uniform vec3 pivot_neck = vec3(0.0);
// A single creature (a MeshInstance3D, not a MultiMesh): its instance data here.
uniform bool single = false;
uniform vec4 single_custom = vec4(0.0);
uniform vec4 single_tint = vec4(1.0);
// A paler underside (a ray's, a whale's throat and belly): mixed in by how much a face looks down (its model-space
// normal), times belly.
uniform float belly = 0.0;
uniform vec3 belly_colour : source_color = vec3(0.8);

#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;
varying vec4 tint;
varying float lit;
varying float under;

vec3 rotate_x(vec3 v, vec3 pivot, float a) {
	vec3 p = v - pivot;
	float c = cos(a);
	float s = sin(a);
	return pivot + vec3(p.x, p.y * c - p.z * s, p.y * s + p.z * c);
}

void vertex() {
	vec4 d = single ? single_custom : INSTANCE_CUSTOM;
	tint = single ? single_tint : COLOR;
	under = clamp(-NORMAL.y, 0.0, 1.0) * belly;
	lit = d.z;
	float ph = d.x * TAU;
	vec3 v = VERTEX;
	float wing = UV.x;
	if (wing > 0.0) {
		// Folded towards the body by the pose; flapping about the long axis.
		v.x *= 1.0 - fold * d.w * wing;
		float a = flap * d.y * sin(ph) * wing;
		v = vec3(v.x * cos(a), v.y + abs(v.x) * sin(a), v.z);
	}
	float leg = UV.y;
	if (leg > 0.0 && stride > 0.0) {
		// Diagonal pairs together (a walk's trot): front left with rear right.
		float side = ((v.x > 0.0) == (v.z > 0.0)) ? 0.0 : PI;
		float s = sin(ph + side);
		v.z += leg * stride * d.y * s;
		v.y += leg * stride * 0.35 * d.y * max(0.0, cos(ph + side));
	}
	float body = UV2.x;
	if (body > 0.0 && sway > 0.0) {
		float wave = body * sway * d.y * sin(ph - v.z * waves);
		if (sway_up) {
			v.y += wave;
		} else {
			v.x += wave;
		}
	}
	float head = UV2.y;
	if (head > 0.0 && graze > 0.0 && d.w > 0.0) {
		v = rotate_x(v, pivot_neck, -graze * d.w * head);
	}
	if (sit > 0.0 && d.w > 0.0) {
		vec3 r = rotate_x(v, pivot_rear, sit * d.w);
		if (leg > 0.0 && VERTEX.z < pivot_rear.z - 0.05) {
			// Front legs: the tops go with the body, the paws stay where they stood.
			r.y = mix(r.y, VERTEX.y, leg);
			r.z = mix(r.z, VERTEX.z, leg);
		}
		r.y = max(r.y, 0.0);
		v = r;
	}
	VERTEX = v;
	world_pos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
}

void fragment() {
	if (tint.a < 0.999) {
		// Interleaved gradient noise: an opaque dissolve.
		float n = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (tint.a <= n) {
			discard;
		}
	}
	vec3 light = room_light_at(world_pos, spill) + lit_colour * spill_tint(screen_center) * lit;
	ALBEDO = mix(colour, belly_colour, under) * tint.rgb * light;
}
