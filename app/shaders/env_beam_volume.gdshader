// A projector's beam as light in hazy air (screen_frame.gd beam_style "volume"; since 2026-11-08, the drive-in): each
// pixel the beam covers adds the light scattered along the view ray's path through it, worked out exactly for the
// beam's pyramid (the lens at the apex, the screen's corners at its base: a ray against five planes), so it reads as
// a shaft of light from below, from the side or from inside, with no slices or fans. The light per metre falls with
// the square of the distance from the lens (the same light spread wider), so the shaft glows over the booth and fades
// towards the screen; across the beam it takes the picture's colours (the bias light's copy, as the spill), and a slow
// drift of haze moves through it. One face is drawn a pixel (the far side: cull_front), so a pixel is lit once.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_front, shadows_disabled, specular_disabled, fog_disabled;

uniform vec3 colour : source_color = vec3(1.0, 0.95, 0.85);
uniform float strength = 0.004;
uniform float house_reference = 0.05;
// The pyramid in the beam's own frame (the lens at the origin): the four sides' outward normals, the screen's plane
// (normal, distance), the axis (unit, towards the screen), its length, and the right and up half sizes at the screen.
uniform vec3 side_n0 = vec3(1.0, 0.0, 0.0);
uniform vec3 side_n1 = vec3(-1.0, 0.0, 0.0);
uniform vec3 side_n2 = vec3(0.0, 1.0, 0.0);
uniform vec3 side_n3 = vec3(0.0, -1.0, 0.0);
uniform vec4 far_plane = vec4(0.0, 0.0, -1.0, 60.0);
uniform vec3 axis = vec3(0.0, 0.0, -1.0);
uniform float axis_len = 60.0;
uniform vec3 right = vec3(1.0, 0.0, 0.0);
uniform float half_w = 12.0;
// The haze's drift (metres a second, from the script's clock) and its texture.
uniform float haze_time = 0.0;
uniform sampler2D haze : filter_linear_mipmap, repeat_enable;

#include "res://shaders/env_spill.gdshaderinc"

varying vec3 local_pos;
varying vec3 local_eye;

void vertex() {
	local_pos = VERTEX;
	local_eye = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

// Nearer the lens than this (a share of the axis) the light per metre is held.
const float BEAM_NEAR = 0.11;

// The light per metre, 1 / max(s, BEAM_NEAR)^2, summed over s from a to b (a <= b).
float beam_sum(float a, float b) {
	float q = BEAM_NEAR * BEAM_NEAR;
	float sum = 0.0;
	if (a < BEAM_NEAR) {
		sum += (min(b, BEAM_NEAR) - a) / q;
	}
	if (b > BEAM_NEAR) {
		sum += 1.0 / max(a, BEAM_NEAR) - 1.0 / b;
	}
	return sum;
}

// Clip the ray's span [u0, u1] by the half-space n.p <= d.
void clip(vec3 o, vec3 dir, vec3 n, float d, inout float u0, inout float u1) {
	float den = dot(n, dir);
	float num = d - dot(n, o);
	if (abs(den) < 1e-6) {
		if (num < 0.0) {
			u1 = -1.0;
		}
	} else if (den > 0.0) {
		u1 = min(u1, num / den);
	} else {
		u0 = max(u0, num / den);
	}
}

void fragment() {
	vec3 o = local_eye;
	vec3 dir = normalize(local_pos - local_eye);
	float u0 = 0.0;
	float u1 = 1e6;
	clip(o, dir, side_n0, 0.0, u0, u1);
	clip(o, dir, side_n1, 0.0, u0, u1);
	clip(o, dir, side_n2, 0.0, u0, u1);
	clip(o, dir, side_n3, 0.0, u0, u1);
	clip(o, dir, far_plane.xyz, far_plane.w, u0, u1);
	float chord = max(u1 - u0, 0.0);
	vec3 m = o + dir * (u0 + u1) * 0.5;
	float s = clamp(dot(m, axis) / axis_len, 0.0, 1.0);
	float level = clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	float dark = clamp(1.25 - level, 0.2, 1.0);
	// The light along the chord: per metre as the square of the beam's narrowing towards the lens (held near it),
	// summed exactly between the chord's ends (a midpoint's value drew rings where the chord ran along the beam).
	float sa = clamp(dot(o + dir * u0, axis) / axis_len, 0.0, 1.0);
	float sb = clamp(dot(o + dir * u1, axis) / axis_len, 0.0, 1.0);
	float per_m = 1.0 / max(s * s, BEAM_NEAR * BEAM_NEAR);
	if (abs(sb - sa) > 1e-4 && chord > 0.0) {
		per_m = beam_sum(min(sa, sb), max(sa, sb)) / abs(sb - sa);
	}
	// It thins out towards the screen, so the picture keeps its edges clean.
	float fade = 1.0 - smoothstep(0.45, 0.97, s);
	float h = texture(haze, m.xz * 0.045 + vec2(haze_time * 0.011, haze_time * 0.004)).g;
	float h2 = texture(haze, m.zy * 0.09 - vec2(haze_time * 0.007, 0.0)).b;
	// Taken at the chord's middle, the haze is right for a short chord (the beam seen from the side); along a long
	// one (from inside the beam, looking along it) the drifts average out, and the middle's sample would sweep across
	// the view in rings, so it goes to its mean.
	float hz = mix(0.55 + 0.9 * h * h2, 0.78, smoothstep(3.0, 14.0, chord));
	// The picture's colour across the beam.
	float across = dot(m, right) / max(s * half_w, 0.01);
	vec3 film = vec3(1.0);
	if (screen_tint > 0.0) {
		float u = clamp(0.5 + 0.5 * across, 0.125, 0.875);
		film = mix(vec3(1.0), min(spill_srgb_to_linear(textureLod(screen_thumb, vec2(u, 0.5), 0.0).rgb)
				/ SPILL_REFERENCE, vec3(SPILL_MAX)), screen_tint);
	}
	vec3 c = colour * film * (strength * dark * per_m * chord * fade * hz);
	// A dither of a 10-bit buffer's step or so where there is light: the dim gradient would otherwise show steps.
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	vec3 sc = sqrt(max(c, vec3(0.0)));
	sc = max(sc + n * 3.0 / 255.0 * smoothstep(0.002, 0.02, sc.g), vec3(0.0));
	ALBEDO = sc * sc;
}
