// The sky system's Moon (scripts/env/systems/sky.gd `moon`; docs/environments.md, "The sky"): one quad round the camera
// where the Moon hangs, nearer than the stars so it hides them. A sphere lit from where the sun went down (`sun`, in
// the quad's frame: x right, y up, z towards the viewer): its crescent, the faint earthshine on the rest of its face,
// darker seas from the sky's noise, a soft halo round it, all dimmed where clouds pass over it. Nothing moves.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled,
		skip_vertex_transform;

#include "res://shaders/env_sky_common.gdshaderinc"

uniform float moon = 1.0;
uniform vec3 moon_dir = vec3(0.0, 0.7, -0.7);
uniform vec3 moon_right = vec3(1.0, 0.0, 0.0);
uniform vec3 moon_up = vec3(0.0, 1.0, 0.0);
// tan(half the Moon's size): its radius at unit distance. The quad reaches `halo` radii each way.
uniform float moon_half = 0.014;
uniform float halo = 3.0;
uniform vec3 sun = vec3(0.8, -0.3, -0.5);
uniform vec3 moon_colour : source_color = vec3(1.0, 0.96, 0.86);
uniform float model_radius = 178.0;

varying vec2 q;
varying float vis;

void vertex() {
	q = (UV * 2.0 - 1.0) * halo;
	vec3 p = moon_dir + (moon_right * q.x + moon_up * q.y) * moon_half;
	vec3 world = CAMERA_POSITION_WORLD + sky_room_basis(MODEL_MATRIX) * p * model_radius;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	// Clouds over it hide it (not wholly: the Moon glows through thin cloud); the air low down dims it a little.
	float cover = sky_cloud_cover(normalize(moon_dir), 3.0);
	vis = moon * (1.0 - 0.75 * cover) * mix(0.6, 1.0, smoothstep(0.05, 0.3, moon_dir.y));
}

void fragment() {
	float r = length(q);
	float disc = 1.0 - smoothstep(0.96, 1.04, r);
	vec3 n = vec3(q, sqrt(max(1.0 - r * r, 0.0)));
	vec3 l = normalize(sun);
	float lit = smoothstep(-0.04, 0.1, dot(n, l));
	// The seas: darker patches from the sky's noise, fixed on the face.
	float seas = texture(sky_noise, q * 0.21 + vec2(0.31, 0.62)).b;
	float face = mix(0.72, 1.0, smoothstep(0.35, 0.7, seas));
	// The limb a little darker, as a sphere's is.
	face *= mix(0.78, 1.0, n.z);
	vec3 col = moon_colour * 1.25 * face;
	// The unlit part: earthshine, faint; against a twilight sky it barely shows (a dark disc would read as a hole).
	vec3 shine = vec3(0.11, 0.13, 0.19) * face;
	// The halo: a soft glow round the lit part, fading over a radius or two.
	float lit_share = clamp(0.5 - 0.5 * l.z, 0.05, 1.0);
	float glow = exp(-max(r - 1.0, 0.0) * 2.4) * 0.22 * lit_share * (1.0 - disc);
	glow *= 1.0 - smoothstep(halo * 0.75, halo, r);
	ALBEDO = mix(moon_colour * 0.85, mix(shine, col, lit), disc);
	ALPHA = clamp(max(disc * mix(0.35, 1.0, lit), glow) * vis, 0.0, 1.0);
}
