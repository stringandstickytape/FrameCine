// Halftone (visualiser.json): the cover printed in four inks (cyan, magenta, yellow, black), each a grid of dots at
// its own angle, as in a cheap colour print. A dot's size is how much of its ink the picture has under it, swollen by
// the sound at its place across the card (low notes left, high right). On a beat the magenta plate slips a little out
// of line and settles back. The cover pans slowly. Without a cover (or use_cover off) it prints a starburst panel.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float dot_size = 15.0;
uniform float swell = 0.4;
uniform float slip = 0.5;
uniform float speed = 0.5;
uniform vec4 paper : source_color = vec4(0.9, 0.86, 0.77, 1.0);
uniform bool use_cover = true;


vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// The picture being printed at p (in card heights: x 0..aspect, y 0..1).
vec3 picture(vec2 p) {
	float aspect = size.x / size.y;
	float t = drive * speed * 0.15;
	if (use_cover && has_cover > 0.5) {
		// The cover across the card's width, zoomed a little, drifting so all of it passes in time.
		vec2 c = vec2(0.5 + 0.04 * sin(t * 0.7), 0.5 + 0.2 * sin(t * 0.43));
		vec2 uv = c + (p - vec2(aspect, 1.0) * 0.5) / (aspect * 1.12);
		vec3 col = texture(cover, uv).rgb;
		// Pop: more saturated and contrasty than the cover.
		float g = dot(col, vec3(0.333));
		col = clamp(mix(vec3(g), col, 1.5), 0.0, 1.0);
		return smoothstep(0.05, 0.95, col);
	}
	// A starburst: rays in two colours round a moving middle, a disc and a ring in front.
	vec2 m = vec2(aspect * (0.62 + 0.06 * sin(t * 0.5)), 0.5 + 0.08 * cos(t * 0.37));
	vec2 q = p - m;
	float a = atan(q.y, q.x) / (2.0 * PI);
	// Soft edges: a dot on an edge changes size as the edge passes, rather than swapping colour at once.
	float ray = smoothstep(0.3, 0.7, abs(fract(a * 18.0 + t * 0.2) - 0.5) * 2.0);
	vec3 col = mix(vec3(0.93, 0.2, 0.17), vec3(1.0, 0.82, 0.2), ray);
	float r = length(q);
	float disc = 0.2 + 0.03 * bass;
	col = mix(col, vec3(0.97, 0.95, 0.9), smoothstep(disc + 0.05, disc + 0.02, r));
	col = mix(col, vec3(0.12, 0.33, 0.78), smoothstep(disc + 0.015, disc - 0.015, r));
	return col;
}

vec4 cmyk(vec3 c) {
	float k = 1.0 - max(c.r, max(c.g, c.b));
	float d = max(1.0 - k, 0.001);
	return vec4((1.0 - c.r - k) / d, (1.0 - c.g - k) / d, (1.0 - c.b - k) / d, k);
}

// One plate's coverage (0..1) at pixel px: its grid turned by angle, each dot's size from the picture at its middle.
float plate(vec2 px, float angle, int channel, vec2 offset) {
	vec2 pp = px - offset;
	vec2 q = rot(pp, angle) / dot_size;
	vec2 cell = floor(q) + 0.5;
	vec2 middle = rot(cell * dot_size, -angle);
	vec4 ink = cmyk(picture(middle / size.y));
	float v = channel == 0 ? ink.x : channel == 1 ? ink.y : channel == 2 ? ink.z : ink.w;
	float here = band(clamp(middle.x / size.x, 0.0, 1.0));
	float grow = 1.0 + swell * (here - 0.35) * 0.25;
	float r = sqrt(clamp(v, 0.0, 1.0)) * 0.72 * dot_size * grow;
	return fill_px(length(q - cell) * dot_size - r);
}

void fragment() {
	vec2 px = UV * size;
	// The magenta plate slips on a beat: a few pixels along a direction that changes with each beat.
	float a = beats * 2.4;
	vec2 off = vec2(cos(a), sin(a)) * beat * slip * dot_size * 0.1;
	float c = plate(px, radians(15.0), 0, vec2(0.0));
	float m = plate(px, radians(75.0), 1, off);
	float y = plate(px, 0.0, 2, vec2(0.0));
	float k = plate(px, radians(45.0), 3, vec2(0.0));
	// Inks multiply on the paper, as printed ones do.
	vec3 col = paper.rgb;
	col *= mix(vec3(1.0), vec3(0.0, 0.66, 0.92), c);
	col *= mix(vec3(1.0), vec3(0.92, 0.1, 0.55), m);
	col *= mix(vec3(1.0), vec3(1.0, 0.93, 0.05), y);
	col *= mix(vec3(1.0), vec3(0.13, 0.12, 0.14), k);
	COLOR = vec4(col * 0.85, 1.0);
}
