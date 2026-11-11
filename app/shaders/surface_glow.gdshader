// The glow round a surface (app/ui/surface_frame.gd): light outside the outline of its picture, bar and side stack,
// never over them. A tight bright rim and a wide faint haze, both falling away with the distance from the outline,
// with a slow drift in the haze so that it reads as light and not as a border. Added to what is behind it.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, shadows_disabled, depth_draw_never;

// The quad's size in metres; the outline's two boxes as centre x, centre y, half width, half height against the
// quad's centre (a negative half size: no such box); how far the light reaches from the outline.
uniform vec2 quad_size = vec2(1.0, 1.0);
uniform vec4 box_a = vec4(0.0, 0.0, 0.4, 0.3);
uniform vec4 box_b = vec4(0.0, 0.0, -1.0, -1.0);
uniform float reach = 0.1;
uniform vec4 colour : source_color = vec4(0.61, 0.8, 0.91, 1.0);
// 0 none; about 0.4 pointed at; 1 selected.
uniform float level = 0.0;

float box(vec2 p, vec4 b) {
	vec2 q = abs(p - b.xy) - b.zw;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 0.5 - UV.y) * quad_size;
	float d = box(p, box_a);
	if (box_b.z > 0.0) {
		d = min(d, box(p, box_b));
	}
	// Outside only.
	float outside = step(0.0, d);
	float t = clamp(d / reach, 0.0, 1.0);
	// No hard line at the outline: the rim is itself soft, and most of the light is the haze.
	float rim = exp(-t * 9.0);
	float haze = exp(-t * 2.4) * (1.0 - t) * (1.0 - t);
	float drift = 0.78 + 0.22 * sin(TIME * 0.9 + p.x * 5.0 - p.y * 3.0) * sin(TIME * 0.53 + p.y * 4.0);
	ALBEDO = colour.rgb;
	ALPHA = outside * level * (rim * 0.45 + haze * 0.75) * drift;
}
