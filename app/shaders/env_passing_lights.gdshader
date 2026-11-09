// The passing system's points of light (scripts/env/systems/passing.gd; docs/environments/passing.md): a far
// village's windows, lamps along the way. Each light is four vertices at one point (passing/shape_mesh.gd light()),
// carried along the way as env_passing.gdshader carries its item, then spread to face the eye as
// env_lunar_lights.gdshader does it: UV2.x metres in radius, but never under a tenth of a degree, so a far light stays
// a few pixels wide and never shimmers. A soft round point, added over what is behind. No depth write.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled,
		skip_vertex_transform;

// The uniforms every passing shader takes (passing.gd sets them each tick; some only the scenery uses).
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
// The placing, as env_passing.gdshader's.
uniform float phase[10];
uniform float landmark_along[12];
uniform float travel = 0.0;
uniform float route = 0.0;
uniform float endless_half = 3600.0;
uniform sampler2D presence_tex : filter_linear, repeat_disable;
uniform float band_count = 1.0;
uniform float far = 188.0;
uniform float edge = 0.82;
uniform float lights = 1.0;

// A tenth of a degree: the least a light's radius is, against its distance.
const float MIN_ANGLE = 0.001745;

varying vec3 col;
varying float dist;

void vertex() {
	float loop = CUSTOM1.x;
	float pace = CUSTOM1.y;
	int index = int(CUSTOM1.z + 0.5);
	float t;
	float grow = 1.0;
	if (CUSTOM1.w > 0.5) {
		t = landmark_along[index];
	} else {
		float half_loop = loop * 0.5;
		t = mod(CUSTOM0.z - phase[index] + half_loop, loop) - half_loop;
		grow = 1.0 - smoothstep(half_loop * edge, half_loop, abs(t));
		float s = travel + t / pace;
		float u = route > 0.0 ? clamp(s / route, 0.0, 1.0) : 1.0 - exp2(-max(s, 0.0) / endless_half);
		float p = textureLod(presence_tex, vec2(u, (float(index) + 0.5) / band_count), 0.0).r;
		if (CUSTOM0.w > 0.0 && p < CUSTOM0.w) {
			grow = 0.0;
		}
	}
	vec3 foot = vec3(CUSTOM0.x, CUSTOM0.y, t);
	if (length(foot.xz) > far) {
		grow = 0.0;
	}
	vec3 q = foot + VERTEX * grow;
	vec3 p_room = across_dir * q.x + vec3(0.0, 1.0, 0.0) * q.y + along_dir * q.z;
	vec4 c = MODELVIEW_MATRIX * vec4(p_room, 1.0);
	float d = length(c.xyz);
	// UNDECIDED (brief): a light grows from nothing with its item (grow), as the scenery does, so one that is not
	// there is not drawn at the tenth of a degree either.
	float size = max(UV2.x, d * MIN_ANGLE) * grow;
	c.xy += UV * size;
	VERTEX = c.xyz;
	col = COLOR.rgb * COLOR.a;
	dist = d;
}

void fragment() {
	// UNDECIDED (brief): the soft round point's profile is env_lunar_lights.gdshader's (a soft glow and a core).
	float r = length(UV);
	float k = pow(max(1.0 - r, 0.0), 3.0) + smoothstep(0.3, 0.0, r) * 1.5;
	ALBEDO = col * k * lights * shown * (1.0 - 0.6 * mist * smoothstep(15.0, 140.0, dist));
}
