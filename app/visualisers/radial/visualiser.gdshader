// Radial (visualiser.json): spokes out from a circle in the middle of the area, low bands at the top, clockwise, and
// a thin ring just inside them.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform int spokes = 32;
uniform float radius = 0.24;
uniform vec4 colour_low : source_color = vec4(0.45, 0.7, 1.0, 1.0);
uniform vec4 colour_high : source_color = vec4(1.0, 0.75, 0.4, 1.0);

const float FULL_TURN = 6.28318530718;

void fragment() {
	float n = float(spokes);
	vec2 d = UV * size - size * 0.5;
	float side = min(size.x, size.y);
	float r0 = side * radius;
	float reach = side * (0.5 - radius) * 0.98;
	// The nearest spoke: angle 0 straight up, growing clockwise (y runs down).
	float ang = mod(atan(d.x, -d.y), FULL_TURN);
	float i = mod(floor(ang / FULL_TURN * n + 0.5), n);
	float a = i / n * FULL_TURN;
	vec2 dir = vec2(sin(a), -cos(a));
	float along = dot(d, dir);
	float across = abs(d.x * dir.y - d.y * dir.x);
	float len = max(reach * band_between(i / n, (i + 1.0) / n), 2.0);
	float half_w = max(r0 * FULL_TURN / n * 0.55, 2.0) * 0.5;
	float spoke = fill_px(max(max(r0 - along, along - (r0 + len)), across - half_w));
	float ring = fill_px(abs(length(d) - (r0 - 3.0)) - 1.0);
	vec3 c = spoke >= ring ? mix(colour_low.rgb, colour_high.rgb, i / n) : vec3(0.3, 0.32, 0.38);
	COLOR = vec4(c, max(spoke, ring));
}
