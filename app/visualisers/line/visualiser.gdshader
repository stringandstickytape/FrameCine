// Line (visualiser.json): a line through the bands' levels (one point per band, at its middle), filled faintly below.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform int points = 32;
uniform float thickness = 4.0;
uniform float fill = 0.18;
uniform vec4 colour_low : source_color = vec4(0.45, 0.7, 1.0, 1.0);
uniform vec4 colour_high : source_color = vec4(1.0, 0.75, 0.4, 1.0);

float level_of(float i, float n) {
	i = clamp(i, 0.0, n - 1.0);
	return band_between(i / n, (i + 1.0) / n);
}

void fragment() {
	float n = float(points);
	vec2 px = UV * size;
	// The segment between the points either side of this column.
	float t = clamp(UV.x * n - 0.5, 0.0, n - 1.0);
	float i = min(floor(t), n - 2.0);
	vec2 a = vec2((i + 0.5) / n * size.x, size.y * (1.0 - level_of(i, n)));
	vec2 b = vec2((i + 1.5) / n * size.x, size.y * (1.0 - level_of(i + 1.0, n)));
	vec2 ab = b - a;
	float k = clamp(dot(px - a, ab) / dot(ab, ab), 0.0, 1.0);
	float line_a = fill_px(length(px - (a + ab * k)) - thickness * 0.5);
	float y = mix(a.y, b.y, clamp((px.x - a.x) / ab.x, 0.0, 1.0));
	bool inside = px.x >= size.x * 0.5 / n && px.x <= size.x * (1.0 - 0.5 / n) && px.y > y;
	COLOR = vec4(mix(colour_low.rgb, colour_high.rgb, t / n), max(line_a, inside ? fill : 0.0));
}
