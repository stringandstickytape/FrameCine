// The visualisers' flash limit, second pass (scripts/visualisers/visualiser_host.gd): one pixel per cell, CELLS
// (16 x 9), each the mean of its 8 x 8 sample points from visualiser_taps.gdshader.
// Out: r, g the cell's flicker (two bytes); b, a its luminance now (two bytes).
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D points : filter_nearest, repeat_disable;
uniform vec2 taps = vec2(128.0, 72.0);
uniform vec2 cells = vec2(16.0, 9.0);

void fragment() {
	vec2 per = taps / cells;
	vec2 cell = floor(UV * cells);
	float flicker = 0.0;
	float l = 0.0;
	for (int y = 0; y < int(per.y); y++) {
		for (int x = 0; x < int(per.x); x++) {
			vec4 t = texture(points, (cell * per + vec2(float(x), float(y)) + 0.5) / taps);
			flicker += t.b * t.b;
			l += t.a;
		}
	}
	float n = per.x * per.y;
	flicker = clamp(flicker / n, 0.0, 1.0);
	l = clamp(l / n, 0.0, 1.0);
	COLOR = vec4(floor(flicker * 255.0) / 255.0, fract(flicker * 255.0), floor(l * 255.0) / 255.0, fract(l * 255.0));
}
