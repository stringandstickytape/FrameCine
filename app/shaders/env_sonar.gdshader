// A sonar scope on a dome hall's console (scripts/env/systems/kit/dome_fittings.gd): a round green screen, faint range
// rings and a cross, a sweep turning once in `period` seconds with a fading trail, and echoes that light as the sweep
// passes them and fade over the turn (a school drifting slowly, a few rocks still). The sweep is slow (a turn in 6 s:
// any point brightens once in 6 s, far under the photosensitivity ceiling); `glow` is the system's live `sonar`.
// Unshaded: it gives light and takes none.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

uniform vec3 colour : source_color = vec3(0.35, 1.0, 0.55);
uniform float glow = 1.0;
uniform float period = 6.0;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float r = length(p);
	if (r > 1.0) {
		ALBEDO = vec3(0.01, 0.012, 0.01);
	} else {
		float a = atan(p.x, p.y);
		float sweep = fract(TIME / period);
		// 0 on the sweep line, rising behind it round the turn.
		float behind = fract(sweep - (a / TAU + 0.5));
		float trail = pow(1.0 - behind, 5.0);
		float line = 1.0 - smoothstep(0.0, 0.012, behind);
		float rings = 1.0 - smoothstep(0.0, 0.04, abs(fract(r * 3.0 + 0.5) - 0.5));
		float cross = (1.0 - smoothstep(0.0, 0.008, abs(p.x))) + (1.0 - smoothstep(0.0, 0.008, abs(p.y)));
		float echoes = 0.0;
		for (int i = 0; i < 7; i++) {
			float fi = float(i);
			// A school (the first three) drifts round slowly; the rest stay put.
			float ang = hash(fi) * TAU + (i < 3 ? TIME * 0.01 : 0.0);
			float dist = 0.25 + 0.65 * hash(fi + 7.0);
			vec2 at = vec2(sin(ang), cos(ang)) * dist;
			float since = fract(sweep - (ang / TAU + 0.5));
			float spot = exp(-dot(p - at, p - at) * (i < 3 ? 900.0 : 500.0));
			echoes += spot * pow(1.0 - since, 2.0);
		}
		float edge = smoothstep(0.9, 1.0, r);
		vec3 c = colour * (0.06 + 0.12 * rings + 0.08 * cross + 0.55 * trail + 0.9 * line + 1.6 * echoes);
		ALBEDO = mix(c * glow, vec3(0.02, 0.03, 0.02), edge * 0.8);
	}
}
