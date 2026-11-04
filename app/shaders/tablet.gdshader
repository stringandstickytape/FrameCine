shader_type spatial;
// The tablet's rounded rectangles (ui/tablet.gd): a pane's backdrop, or the time bar's track and played part. The fill
// inside a border, nothing outside the border; both colours carry their own opacity, and opacity fades it all. Edges
// are antialiased over one pixel.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec2 size = vec2(0.48, 0.26); // Metres: the quad.
uniform float corner_radius = 0.024; // Metres, the outer edge's.
uniform float border_width = 0.006; // Metres.
uniform vec4 fill_color : source_color = vec4(0.69, 0.878, 0.902, 0.5);
uniform vec4 border_color : source_color = vec4(0.69, 0.878, 0.902, 0.75);
uniform float opacity = 1.0; // The tablet's fade.

// Signed distance to a rounded rectangle centred at 0 with half-size h and corner radius r (negative inside).
float rounded_rect(vec2 p, vec2 h, float r) {
	vec2 q = abs(p) - h + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	float r = clamp(corner_radius, 0.0, 0.5 * min(size.x, size.y));
	float d = rounded_rect(p, 0.5 * size, r);
	float aa = max(fwidth(d), 1e-5);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	float fill = border_width > 0.0 ? 1.0 - smoothstep(-aa, aa, d + border_width) : inside;
	vec4 c = mix(border_color, fill_color, fill);
	ALBEDO = c.rgb;
	ALPHA = c.a * inside * opacity;
}
