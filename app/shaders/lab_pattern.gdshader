shader_type canvas_item;
// The test lab's sharpness cards (scripts/video/lab_card.gd; docs/test-lab.md), drawn once into the card's frame:
//   0  zone plate   rings whose spacing shrinks from the centre out, to half a cycle a pixel at the corners: every
//                   frequency the frame can hold. A good filter shows smooth rings fading to grey; a poor one shows
//                   false rings (moiré) where the frequency passes what the display can show.
//   1  starfield    single-pixel stars, a few in a thousand pixels, of random brightness: what shimmers and drops out
//                   when a frame shrunk on the display skips texels.
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
	float v;
	if (kind == 0) {
		vec2 c = p + 0.5 - px_size * 0.5;
		float rmax = length(px_size * 0.5);
		// Local frequency r / (2 rmax) cycles a pixel: half a cycle at the corners.
		v = 0.5 + 0.5 * cos(PI * dot(c, c) / (2.0 * rmax));
	} else {
		uint h = hash2(uvec2(p));
		v = (h % 1000u) < 3u ? 0.35 + 0.65 * float((h >> 10u) % 256u) / 255.0 : 0.0;
	}
	COLOR = vec4(vec3(v), 1.0);
}
