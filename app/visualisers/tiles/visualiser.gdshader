// Tiles (visualiser.json): a wall of square tiles, each a flat colour with one bold shape in another (a quarter
// disc, a half disc, an eye, a triangle, stripes, a quarter ring), in the manner of modernist posters. Each tile has
// its own number of beats between turns, so on any beat only a few turn a quarter, with an overshoot that settles
// (the beat's 0.3 s fall is the animation). Without beats they still turn now and then, on the music's clock. The
// shapes breathe with the sound at their place across the card.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform int rows = 5;
uniform float busy = 0.4;
uniform float breathe = 0.5;
uniform vec4 colour_a : source_color = vec4(0.78, 0.25, 0.18, 1.0);
uniform vec4 colour_b : source_color = vec4(0.91, 0.68, 0.18, 1.0);
uniform vec4 colour_c : source_color = vec4(0.14, 0.35, 0.62, 1.0);
uniform vec4 paper : source_color = vec4(0.89, 0.85, 0.77, 1.0);
uniform vec4 ink : source_color = vec4(0.11, 0.11, 0.12, 1.0);


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

// 0..1, the same for a tile and a salt every frame.
float tile_hash(vec2 tile, uint salt) {
	uint h = hash_u(uint(int(tile.x) + 4096) * 73856093u ^ uint(int(tile.y) + 4096) * 19349663u ^ salt * 83492791u);
	return float(h & 16777215u) / 16777215.0;
}

vec3 palette(float h) {
	int i = int(floor(h * 5.0));
	return i == 0 ? paper.rgb : i == 1 ? colour_a.rgb : i == 2 ? colour_b.rgb : i == 3 ? colour_c.rgb : ink.rgb;
}

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// The shape's signed distance (tile units, negative inside) at l (-0.5..0.5), grown by g.
float shape(int kind, vec2 l, float g) {
	if (kind == 0) {
		return length(l + 0.5) - 0.92 * g;
	} else if (kind == 1) {
		return length(l - vec2(0.0, 0.5)) - 0.46 * g;
	} else if (kind == 2) {
		float outer = length(l) - 0.34 * g;
		float pupil = length(l - vec2(0.13, -0.13)) - 0.11;
		return max(outer, -pupil);
	} else if (kind == 3) {
		return (l.x + l.y) * 0.7071 + 0.06 * (1.0 - g);
	} else if (kind == 4) {
		float s = abs(fract((l.y + 0.5) * 2.5 + 0.25) - 0.5) - 0.17 * g;
		return max(s / 2.5, l.x - 0.25 * g);
	}
	float r = length(l + 0.5);
	return abs(r - 0.62) - 0.16 * g;
}

// Ease out with an overshoot (0..1, passing 1 and settling back).
float snap(float x) {
	float u = x - 1.0;
	return 1.0 + 1.8 * u * u * u + 0.8 * u * u;
}

void fragment() {
	vec2 px = UV * size;
	float cell = size.y / float(rows);
	float cols = ceil(size.x / cell);
	float off = (size.x - cols * cell) * 0.5;
	vec2 g = vec2((px.x - off) / cell, px.y / cell);
	vec2 tile = floor(g);
	vec2 l = fract(g) - 0.5;

	vec3 bg = palette(tile_hash(tile, 1u));
	float hf = tile_hash(tile, 2u);
	vec3 fg = palette(fract(tile_hash(tile, 1u) + 0.2 + 0.6 * hf));
	int kind = int(floor(tile_hash(tile, 3u) * 6.0));

	// Turns on beats: every p beats, at the tile's own phase; the turn plays out over the beat's fall.
	float p = floor(mix(16.0, 3.0, busy) * (0.7 + 0.6 * tile_hash(tile, 4u))) + 1.0;
	float k = beats + floor(tile_hash(tile, 5u) * p);
	float turns = floor(k / p);
	if (beats > 0.0 && mod(k, p) < 0.5) {
		turns += snap(1.0 - beat) - 1.0;
	}
	// And slowly on the music's clock, so quiet music moves too.
	float dk = drive * 0.012 * (0.3 + busy) + tile_hash(tile, 6u) * 7.0;
	turns += floor(dk) - 1.0 + smoothstep(0.0, 0.04, fract(dk));
	float dir = tile_hash(tile, 7u) < 0.5 ? 1.0 : -1.0;
	vec2 lr = rot(l, turns * dir * PI * 0.5);

	float x = clamp((tile.x + 0.5) / cols, 0.0, 1.0);
	float grow = 1.0 + breathe * (band(x) - 0.3) * 0.22;
	float d = shape(kind, lr, grow) * cell;
	vec3 col = mix(bg, fg, fill_px(d));
	// A hairline of paper between tiles.
	vec2 edge = (0.5 - abs(l)) * cell;
	col = mix(col, paper.rgb * 0.8, 1.0 - clamp(min(edge.x, edge.y) - 0.5, 0.0, 1.0));
	COLOR = vec4(col * 0.9, 1.0);
}
