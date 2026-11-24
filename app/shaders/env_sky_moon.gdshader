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
	float h = mix(halo, 1.35, space);
	q = (UV * 2.0 - 1.0) * h;
	vec3 p = moon_dir + (moon_right * q.x + moon_up * q.y) * moon_half;
	vec3 world = CAMERA_POSITION_WORLD + sky_room_basis(MODEL_MATRIX) * p * model_radius;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	// Clouds over it hide it (not wholly: the Moon glows through thin cloud); in space, no atmospheric extinction.
	float cover = sky_cloud_cover(normalize(moon_dir), 3.0);
	float air_vis = (1.0 - 0.75 * cover) * mix(0.6, 1.0, smoothstep(0.05, 0.3, moon_dir.y));
	vis = moon * mix(air_vis, 1.0, space) * (1.0 - blackout);
}

void fragment() {
	float r = length(q);
	float disc = 1.0 - smoothstep(0.96, 1.04, r);
	vec3 n = vec3(q, sqrt(max(1.0 - r * r, 0.0)));
	vec3 l = normalize(sun);
	float ndl = dot(n, l);
	float lit = smoothstep(-0.04, 0.1, ndl);
	// The seas: darker basaltic maria from the sky's noise, fixed on the face; finer crater relief when large.
	float seas = texture(sky_noise, q * 0.21 + vec2(0.31, 0.62)).b;
	float detail = smoothstep(0.03, 0.14, moon_half);
	float maria = texture(sky_noise, q * 0.48 + vec2(0.14, 0.73)).r;
	float face = mix(0.72, 1.0, smoothstep(0.35, 0.7, seas));
	if (detail > 0.0) {
		float basin = smoothstep(0.32, 0.66, seas * 0.65 + maria * 0.35);
		float h0 = texture(sky_noise, q * 2.4 + vec2(0.41, 0.19)).g;
		float h1 = texture(sky_noise, q * 2.4 + l.xy * 0.035 + vec2(0.41, 0.19)).g;
		float fine = texture(sky_noise, q * 6.5 + vec2(0.09, 0.82)).a;
		float bump = clamp((h0 - h1) * 4.0, -0.45, 0.45);
		float highland = mix(0.42, 1.02, basin) * (0.86 + 0.24 * fine) + bump * 0.28 * smoothstep(-0.05, 0.35, ndl);
		face = mix(face, clamp(highland, 0.28, 1.18), detail);
	}
	// The limb a little darker, as a sphere's is (sharper airless lunar phase curve in space).
	face *= mix(0.78, 1.0, n.z);
	vec3 col = mix(moon_colour * 1.25, vec3(0.84, 0.85, 0.88) * (0.45 + 0.85 * max(ndl, 0.0)), space * 0.7) * face;
	// The unlit part: earthshine, faint; in space, dark enough to occlude stars behind the limb cleanly.
	vec3 shine = mix(vec3(0.11, 0.13, 0.19), vec3(0.015, 0.02, 0.03), space) * face;
	// The halo: a soft glow round the lit part, faded down in airless space.
	float lit_share = clamp(0.5 - 0.5 * l.z, 0.05, 1.0);
	float h = mix(halo, 1.35, space);
	float glow = exp(-max(r - 1.0, 0.0) * 2.4) * 0.22 * lit_share * (1.0 - disc) * (1.0 - 0.85 * space);
	glow *= 1.0 - smoothstep(h * 0.75, h, r);
	ALBEDO = mix(moon_colour * 0.85, mix(shine, col, lit), disc);
	float disc_a = mix(mix(0.35, 1.0, lit), 1.0, space);
	ALPHA = clamp(max(disc * disc_a, glow) * vis, 0.0, 1.0);
}
