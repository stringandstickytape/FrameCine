// The passing system's rotating volumetric beams (scripts/env/systems/passing.gd; docs/environments/passing.md):
// a lighthouse's twin slow-sweeping misty light shafts, drawn in one additive mesh (one draw, zero live lights).
// Each vertex holds its offset from the lantern pivot in VERTEX, the lantern height over the item's foot in UV2.x,
// and its phase offset in UV2.y; UV.x runs 0 at the Fresnel lens to 1 at the far tip. Smooth radial Fresnel fade
// softens the cone edges to zero from every viewing angle. No depth write.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

// Shared passing uniforms.
uniform vec3 along_dir = vec3(0.0, 0.0, -1.0);
uniform vec3 across_dir = vec3(1.0, 0.0, 0.0);
uniform float shown = 1.0;
uniform float light = 1.0;
uniform vec3 sky_top : source_color = vec3(0.106, 0.133, 0.212);
uniform vec3 sky_low : source_color = vec3(0.106, 0.133, 0.212);
uniform float mist = 0.0;
uniform vec3 mist_colour : source_color = vec3(0.227, 0.259, 0.314);
uniform float glow = 0.6;
uniform vec3 glow_colour : source_color = vec3(1.0, 0.761, 0.478);
uniform float glow_reach = 6.0;
uniform float glow_half_length = 3.0;
uniform float spill = 1.0;
uniform float lights = 1.0;
// Current rotation angle in radians (advanced smoothly on CPU, scaled by beam_spin and the Motion comfort setting).
uniform float beam_phase = 0.0;

#include "res://shaders/env_passing_place.gdshaderinc"

varying vec3 col;
varying float dist;

void vertex() {
	float grow;
	vec3 foot = passing_foot(CUSTOM0, CUSTOM1, grow);
	float a = beam_phase + UV2.y;
	float ca = cos(a);
	float sa = sin(a);
	vec3 rv = vec3(VERTEX.x * ca - VERTEX.z * sa, VERTEX.y, VERTEX.x * sa + VERTEX.z * ca);
	vec3 rn = vec3(NORMAL.x * ca - NORMAL.z * sa, NORMAL.y, NORMAL.x * sa + NORMAL.z * ca);
	vec3 q = foot + (vec3(0.0, UV2.x, 0.0) + rv) * grow;
	VERTEX = across_dir * q.x + vec3(0.0, 1.0, 0.0) * q.y + along_dir * q.z;
	NORMAL = normalize(across_dir * rn.x + vec3(0.0, 1.0, 0.0) * rn.y + along_dir * rn.z);
	col = passing_colour(COLOR.rgb) * COLOR.a;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	dist = distance(wp, CAMERA_POSITION_WORLD);
}

void fragment() {
	// Soft volumetric edge falloff from any angle + tight bright lens shaft fading smoothly into distant sea mist.
	float radial = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.75);
	float along_fade = smoothstep(0.0, 0.04, UV.x) * pow(max(1.0 - UV.x, 0.0), 1.85);
	float air = 0.55 + 0.85 * mist;
	float far_fade = 1.0 - smoothstep(135.0, far, dist);
	ALBEDO = col * radial * along_fade * air * lights * shown * far_fade;
}
