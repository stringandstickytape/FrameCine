// The passing system's scenery (scripts/env/systems/passing.gd; docs/environments/passing.md): every band and landmark
// of a room in one mesh, one draw. Each vertex says which item it belongs to and where that item's foot stands
// (passing/shape_mesh.gd has the format); here the item is carried along the way: a band's items round their loop by
// the band's phase, a landmark to its place on the route. An item near its loop's ends grows from nothing, and one its
// band's presence does not reach here stays at nothing. Unshaded: lit by the sky's light, the screen's spill and the
// cabin's own glow on what passes close; mist and the horizon take the far scenery.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled;

#include "res://shaders/env_spill.gdshaderinc"

// The way's directions in the room's frame.
uniform vec3 along_dir = vec3(0.0, 0.0, -1.0);
uniform vec3 across_dir = vec3(1.0, 0.0, 0.0);
// 1 - the blink's dark: every term of light is multiplied by it.
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
uniform float windows = 1.0;

#include "res://shaders/env_passing_place.gdshaderinc"

// The materials (ShapeMesh.M_*).
const int M_PLAIN = 0;
const int M_LEAF = 1;
const int M_STEM = 2;
const int M_BARK = 3;
const int M_WINDOW = 4;

varying vec3 world_pos;
varying vec3 world_normal;
varying flat int mat;
varying float extra;
varying float across;
varying float along;

void vertex() {
	float grow;
	vec3 foot = passing_foot(CUSTOM0, CUSTOM1, grow);
	vec3 q = foot + VERTEX * grow;
	COLOR.rgb = passing_colour(COLOR.rgb);
	VERTEX = across_dir * q.x + vec3(0.0, 1.0, 0.0) * q.y + along_dir * q.z;
	NORMAL = across_dir * NORMAL.x + vec3(0.0, 1.0, 0.0) * NORMAL.y + along_dir * NORMAL.z;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	mat = int(UV2.x + 0.5);
	extra = UV2.y;
	across = abs(q.x);
	along = q.z;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 sky = mix(sky_low, sky_top, clamp(n.y * 0.5 + 0.5, 0.0, 1.0)) * light * shown;
	vec3 screen = (room_light_at(world_pos, spill) - vec3(env_light)) * shown;
	vec3 cabin = glow_colour * glow * shown * (1.0 - smoothstep(0.0, glow_reach, across))
			* (1.0 - smoothstep(glow_half_length, glow_half_length + 2.0, abs(along)));
	vec3 lit = sky + screen + cabin;
	vec3 c;
	if (mat == M_LEAF) {
		c = COLOR.rgb * (0.75 + 0.5 * extra) * (sky * (1.0 + 0.3 * max(n.y, 0.0)) + screen + cabin);
	} else if (mat == M_STEM) {
		c = COLOR.rgb * (0.8 + 0.4 * UV.y) * lit;
	} else if (mat == M_WINDOW) {
		c = COLOR.rgb * windows * shown;
	} else {
		// M_PLAIN and M_BARK.
		c = COLOR.rgb * lit;
	}
	// Mist and the horizon.
	float d = distance(world_pos, CAMERA_POSITION_WORLD);
	float f = max(mist * smoothstep(15.0, 140.0, d), smoothstep(120.0, far, d) * 0.85);
	if (mat != M_WINDOW) {
		c = mix(c, mix(sky_low, mist_colour, mist) * light * shown, f);
	}
	ALBEDO = c;
}
