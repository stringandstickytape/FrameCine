// The courtyard's lit windows (scripts/env/systems/kit/courtyard.gd; docs/environments.md, "Room: Atmospheric 1928"):
// a glimpse of a room behind each window, drawn here from the window's own coordinates, never from a picture. The
// light system's lamp material (house group: `energy` follows the house lamps) on this shader: emission only, so a
// lightmap bake takes the windows as emitters and their glow falls on the reveals, sills and shutters round them.
// Each window's vertex colour carries its width and height (r, g: metres / 4), its kind (b) and the moment it goes
// out as the courtyard goes to bed (a: 0..1). UV is metres from the window's bottom left corner (RoomMesh's charts).
//   kinds (b x 8): 0 a curtain drawn on the left, 1 on the right, 2 curtains both sides and a lamp, 3 a plant on
//   the sill, 4 inner shutters half closed (light through the slats), 5 an organ's pipes in a warm chamber; b over
//   0.95 a dark window (no one home): the glass shows a little of the sky.
//   night   0: every window lit; 1: most have gone out (each fades over about a twentieth of night's travel, so a cue
//           moving it over 8 s fades each window over 0.4 s, slower than the photosensitivity ceiling's fade)
//   ember   what a window that has gone out still shows
shader_type spatial;
render_mode cull_back, specular_disabled, shadows_disabled, ambient_light_disabled;

uniform vec3 colour : source_color = vec3(1.0, 0.72, 0.42);
uniform float energy = 1.0;
uniform float follows_house = 0.0;
uniform float house_reference = 0.05;
// The lamp material's own (unused here: the picture is drawn from the coordinates).
uniform sampler2D picture : source_color, filter_linear;
uniform bool use_picture = false;
uniform bool bake_pass = false;
uniform float night = 0.0;
uniform float ember = 0.15;
uniform float glow = 1.0;

#include "res://shaders/env_spill.gdshaderinc"

float hash1(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// A curtain's folds across x (0..1 of the curtain's width): bright where the cloth faces the lamp behind it.
float folds(float x, float seed) {
	float f = 0.5 + 0.5 * sin(x * 31.0 + seed * 6.0 + sin(x * 9.0 + seed) * 1.5);
	return mix(0.45, 1.0, f);
}

void fragment() {
	float level = bake_pass ? 1.0 : clamp(env_light / max(house_reference, 0.0001), 0.0, 2.0);
	level *= level;
	vec2 size = max(COLOR.rg * 4.0, vec2(0.05));
	vec2 uv = clamp(UV / size, vec2(0.0), vec2(1.0));
	float kind_f = COLOR.b;
	float seed = floor(kind_f * 97.0);
	vec3 c;
	if (kind_f > 0.95) {
		// No one home: dark glass, a little of the evening sky in its upper part.
		c = mix(vec3(0.012, 0.014, 0.022), vec3(0.03, 0.04, 0.07), smoothstep(0.3, 1.0, uv.y));
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		EMISSION = c * (bake_pass ? 0.0 : 1.0);
	} else {
		int kind = int(floor(kind_f * 8.0));
		// The room's back wall and ceiling lit by a lamp inside: brightest round the lamp, darker low down where the
		// furniture stands.
		vec2 lamp = vec2(0.3 + 0.4 * hash1(seed + 1.0), 0.72 + 0.12 * hash1(seed + 2.0));
		vec2 d = (uv - lamp) * vec2(size.x / max(size.y, 0.05), 1.0);
		float pool = exp(-dot(d, d) * 5.0);
		vec3 wall = colour * (0.4 + 0.85 * pool);
		// A ceiling's edge near the top, lit from below.
		wall *= mix(1.0, 1.25, smoothstep(0.86, 0.92, uv.y));
		// Furniture's dark line: a chest's or a sofa's back, its top wavering a little.
		float top = 0.22 + 0.06 * sin(uv.x * 7.0 + seed) + 0.04 * hash1(seed + 3.0);
		float low = smoothstep(top + 0.02, top - 0.02, uv.y);
		wall = mix(wall, colour * vec3(0.16, 0.11, 0.08), low * 0.85);
		c = wall;
		if (kind == 0 || kind == 1 || kind == 2) {
			// Curtains, backlit: their folds glow where the cloth is thin. Each house its own cloth.
			vec3 cloth = mix(vec3(0.75, 0.18, 0.1), vec3(0.85, 0.62, 0.25), hash1(seed + 5.0));
			cloth = mix(cloth, vec3(0.35, 0.55, 0.32), step(0.8, hash1(seed + 7.0)));
			float w = 0.26 + 0.08 * hash1(seed + 4.0);
			// Gathered towards the bottom, where a tie-back holds it.
			float gather = 1.0 - 0.35 * smoothstep(0.5, 0.25, uv.y) * smoothstep(0.0, 0.25, uv.y);
			float lx = uv.x;
			float rx = 1.0 - uv.x;
			float on_left = (kind == 0 || kind == 2) ? step(lx, w * gather) : 0.0;
			float on_right = (kind == 1 || kind == 2) ? step(rx, w * gather) : 0.0;
			float fx = on_left > 0.5 ? lx / (w * gather) : rx / (w * gather);
			vec3 lit = colour * cloth * 1.4 * folds(fx, seed) * (0.6 + 0.6 * pool);
			c = mix(c, lit, max(on_left, on_right));
		} else if (kind == 3) {
			// A plant on the sill: dark leaves against the lit room.
			vec2 p = (uv - vec2(0.5 + 0.2 * (hash1(seed + 8.0) - 0.5), 0.0)) * vec2(size.x / max(size.y, 0.05), 1.0);
			float leaves = 0.0;
			for (int i = 0; i < 5; i++) {
				float a = -1.1 + 0.55 * float(i) + 0.2 * hash1(seed + float(i));
				vec2 dir = vec2(sin(a), cos(a));
				vec2 q = p - dir * 0.16;
				float along = dot(q, dir);
				float across = dot(q, vec2(dir.y, -dir.x));
				leaves = max(leaves, step(across * across / 0.0016 + along * along / 0.022, 1.0));
			}
			float pot = step(abs(p.x), 0.07 - p.y * 0.12) * step(p.y, 0.11);
			c = mix(c, vec3(0.02, 0.025, 0.015), max(leaves, pot) * 0.92);
		} else if (kind == 4) {
			// Inner shutters half closed: light between their slats.
			float slat = smoothstep(0.35, 0.5, abs(fract(uv.y * 16.0) - 0.5) * 2.0);
			c = mix(colour * vec3(0.1, 0.07, 0.05), wall * 1.2, slat * 0.85);
		} else {
			// An organ's chamber: ranks of pipes before a dim warm glow, shorter towards the middle.
			float n = 11.0;
			float i = floor(uv.x * n);
			float px = fract(uv.x * n);
			float mid = abs((i + 0.5) / n - 0.5) * 2.0;
			float tip = 0.5 + 0.38 * mid + 0.04 * hash1(i);
			float body = step(uv.y, tip) * step(0.12, px) * step(px, 0.88);
			float shine = pow(sin((px - 0.12) / 0.76 * 3.14159), 0.7);
			float mouth = smoothstep(0.01, 0.0, abs(uv.y - 0.18) - 0.02);
			vec3 chamber = colour * vec3(0.5, 0.25, 0.12) * (0.5 + 0.6 * pool);
			vec3 pipe = colour * vec3(1.0, 0.82, 0.5) * (0.25 + 0.75 * shine) * (0.55 + 0.5 * pool);
			c = mix(chamber, pipe * (1.0 - 0.7 * mouth), body);
		}
		// The reveal's shadow round the edges: the window is a hole in a thick wall.
		vec2 m = min(uv, 1.0 - uv) * size;
		c *= mix(0.55, 1.0, smoothstep(0.0, 0.12, min(m.x, m.y)));
		// The courtyard going to bed: each window at its own moment.
		float moment = COLOR.a;
		float out_ = smoothstep(moment - 0.025, moment + 0.025, night);
		float shown = mix(1.0, ember, out_);
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		EMISSION = c * energy * glow * (bake_pass ? 1.0 : shown) * mix(1.0, level, follows_house);
	}
}
