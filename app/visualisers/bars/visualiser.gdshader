// Bars (visualiser.json): one bar per band, rising from the bottom.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform int bars = 32;
uniform float gap = 0.3;
uniform vec4 colour_low : source_color = vec4(0.45, 0.7, 1.0, 1.0);
uniform vec4 colour_high : source_color = vec4(1.0, 0.75, 0.4, 1.0);

void fragment() {
	float n = float(bars);
	float i = min(floor(UV.x * n), n - 1.0);
	float h = max(band_between(i / n, (i + 1.0) / n) * size.y, 2.0);
	vec2 px = UV * size;
	float w = size.x / n;
	float x0 = i * w + w * gap * 0.5;
	float x1 = (i + 1.0) * w - w * gap * 0.5;
	float d = max(max(x0 - px.x, px.x - x1), (size.y - h) - px.y);
	COLOR = vec4(mix(colour_low.rgb, colour_high.rgb, i / n), fill_px(d));
}
