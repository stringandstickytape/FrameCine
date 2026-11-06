shader_type canvas_item;
// The test lab's sharpness cards (scripts/video/lab_card.gd; docs/test-lab.md), drawn once into the card's frame:
//   0  zone plate   rings whose spacing shrinks from the centre out, to half a cycle a pixel at the corners: every
//                   frequency the frame can hold. A good filter shows smooth rings fading to grey; a poor one shows
//                   false rings (moiré) where the frequency passes what the display can show.
//   1  starfield    single-pixel stars, a few in a thousand pixels, of random brightness: what shimmers and drops out
//                   when a frame shrunk on the display skips texels.
//   2  gradient     dark ramps left to right, grey above and blue below, smooth here: the card's 8-bit viewport and
//                   the 8-bit encode then quantise them into the bands 8-bit video shows in a dark sky.
// Pixel-exact: each output pixel is one frame pixel (px_size is the frame's size in pixels).

uniform vec2 px_size = vec2(3840.0, 2160.0);
uniform int kind = 0;

// A 32-bit integer hash (PCG-style): the same stars on every GPU, no float precision loss at 8K coordinates.
uint hash2(uvec2 p) {
	uint h = p.x * 747796405u + p.y * 2891336453u + 12345u;
	h = ((h >> ((h >> 28u) + 4u)) ^ h) * 277803737u;
	return (h >> 22u) ^ h;
}

void fragment() {
	vec2 p = floor(UV * px_size);
	vec3 col;
	if (kind == 0) {
		vec2 c = p + 0.5 - px_size * 0.5;
		float rmax = length(px_size * 0.5);
		// Local frequency r / (2 rmax) cycles a pixel: half a cycle at the corners.
		col = vec3(0.5 + 0.5 * cos(PI * dot(c, c) / (2.0 * rmax)));
	} else if (kind == 2) {
		col = UV.y < 0.5 ? vec3(mix(0.02, 0.14, UV.x)) : mix(vec3(0.01, 0.02, 0.05), vec3(0.04, 0.08, 0.2), UV.x);
	} else {
		uint h = hash2(uvec2(p));
		col = vec3((h % 1000u) < 3u ? 0.35 + 0.65 * float((h >> 10u) % 256u) / 255.0 : 0.0);
	}
	COLOR = vec4(col, 1.0);
}
