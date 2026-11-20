// Kaleidoscope (visualiser.json): the view down a real kaleidoscope: three mirrors in a triangle and, at the far end,
// a turning cell of loose coloured glass over the track's cover. Each pixel is folded back across the mirrors until
// it lies in the one true triangle (counting the reflections: each dims the picture a little, as real mirrors do,
// and the joins show faintly); what is there is drawn once, so the whole field is that triangle mirrored.
// In the cell: sixteen pieces of glass (beads, shards, rods, crescents, rings) tumbling on the music's clock
// (drive), each a part of the spectrum, swelling and brightening with its part; they colour what lies behind them as
// glass does, and overlap into new colours. Seed beads glint with the high notes. The cover shows through, turning.
// Round it all, the dark of the tube. No memory.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float turn = 0.5;
uniform float scale = 0.5;
uniform float picture = 0.6;
uniform vec4 glass_a : source_color = vec4(1.0, 0.2, 0.35, 1.0);
uniform vec4 glass_b : source_color = vec4(0.15, 0.55, 1.0, 1.0);
uniform vec4 glass_c : source_color = vec4(1.0, 0.8, 0.15, 1.0);

const int PIECES = 16;


uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

vec3 hash3(float n) {
	uint h = hash_u(uint(int(n) + 1000) * 73856093u);
	uint h2 = h * 2654435761u + 12345u;
	h2 ^= h2 >> 15u;
	return vec3(float(h & 65535u), float(h >> 16u), float(h2 & 65535u)) / 65535.0;
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// A piece of glass of kind k and size s at q (in its own frame): its signed distance.
float piece_sd(vec2 q, int k, float s) {
	if (k == 0) {
		return length(q) - s * 0.7;
	} else if (k == 1) {
		// A three-cornered shard.
		float d = max(q.y - s * 0.5, max(dot(q, vec2(0.866, -0.5)), dot(q, vec2(-0.866, -0.5))) - s * 0.5);
		return d;
	} else if (k == 2) {
		vec2 d = abs(q) - vec2(s * 1.1, s * 0.22);
		return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - s * 0.08;
	} else if (k == 3) {
		return max(length(q) - s * 0.85, -(length(q - vec2(s * 0.4, 0.0)) - s * 0.75));
	}
	return abs(length(q) - s * 0.6) - s * 0.16;
}

void fragment() {
	float aspect = size.x / size.y;
	vec2 p = vec2(UV.x * aspect, 1.0 - UV.y) - vec2(aspect * 0.5, 0.5);
	float px = 1.0 / size.y;
	float tube = length(p);
	float r_in = 0.09 + 0.12 * scale;

	// Fold the point back across the three mirrors into the one triangle.
	vec2 q = rot(p, 0.08 * sin(drive * 0.03));
	float bounces = 0.0;
	for (int i = 0; i < 14; i++) {
		bool inside = true;
		for (int k = 0; k < 3; k++) {
			float a = PI * 0.5 + float(k) * TAU / 3.0;
			vec2 n = vec2(cos(a), sin(a));
			float over = dot(q, n) - r_in;
			if (over > 0.0) {
				q -= 2.0 * over * n;
				bounces += 1.0;
				inside = false;
			}
		}
		if (inside) {
			break;
		}
	}
	float seam = r_in;
	for (int k = 0; k < 3; k++) {
		float a = PI * 0.5 + float(k) * TAU / 3.0;
		seam = min(seam, r_in - dot(q, vec2(cos(a), sin(a))));
	}

	// The cell at the end: the cover (or a wash of the glass's colours) turning behind the pieces.
	float ang = drive * turn * 0.06;
	vec2 c = rot(q, ang);
	float cell_r = r_in * 2.0;
	vec3 wash = mix(mix(glass_b.rgb, glass_a.rgb, 0.5 + 0.5 * sin(c.x / cell_r * 3.0 + drive * 0.05)), glass_c.rgb, 0.5 + 0.5 * sin(c.y / cell_r * 4.0 - drive * 0.04)) * 0.35 + 0.25;
	vec3 art = texture(cover, clamp(c / (cell_r * 2.0) + 0.5, 0.0, 1.0)).rgb;
	vec3 col = mix(wash, mix(wash, art, has_cover), picture) * (0.75 + 0.3 * level);

	for (int i = 0; i < PIECES; i++) {
		float fi = float(i);
		vec3 h = hash3(fi * 7.0 + 3.0);
		float b = band(0.04 + fi / float(PIECES - 1) * 0.9);
		// Tumbling: each piece swings about the cell at its own pace and turns as it goes.
		vec2 pos = cell_r * 0.62 * vec2(sin(drive * turn * (0.05 + 0.06 * h.x) + h.y * TAU), cos(drive * turn * (0.04 + 0.07 * h.z) + h.x * TAU));
		float s = cell_r * (0.16 + 0.22 * h.y) * (0.9 + 0.25 * b);
		vec2 lq = rot(c - pos, drive * turn * (0.1 + 0.2 * h.z) * (h.x > 0.5 ? 1.0 : -1.0) + fi);
		if (dot(lq, lq) > s * s * 1.6) {
			continue;
		}
		float d = piece_sd(lq, i % 5, s);
		if (d < px) {
			vec3 g = i % 3 == 0 ? glass_a.rgb : (i % 3 == 1 ? glass_b.rgb : glass_c.rgb);
			g = mix(g, 0.5 + 0.5 * cos(TAU * (h.z + vec3(0.0, 0.33, 0.67))), 0.3);
			float alpha = smoothstep(px, -px, d);
			// Glass: it colours what is behind, brighter where its part sounds; a bright rim, a bubble inside.
			vec3 through = col * mix(vec3(1.0), g * 1.5, 0.85) + g * (0.08 + 0.25 * b);
			through += vec3(1.0) * smoothstep(0.012 * cell_r / 0.3 + px, 0.0, abs(d + 0.004)) * 0.35;
			through += vec3(1.0) * smoothstep(s * 0.12, 0.0, length(lq - vec2(-s * 0.2, s * 0.15))) * 0.3;
			col = mix(col, through, alpha);
		}
	}
	// Seed beads.
	for (int i = 0; i < 12; i++) {
		float fi = float(i);
		vec3 h = hash3(fi * 13.0 + 90.0);
		vec2 pos = cell_r * 0.8 * vec2(sin(drive * turn * (0.09 + 0.08 * h.x) + h.y * TAU), cos(drive * turn * (0.1 + 0.07 * h.z) + h.z * TAU)) * (0.4 + 0.6 * h.y);
		float l = length(c - pos);
		float r = cell_r * 0.03;
		col = mix(col, (0.5 + 0.5 * cos(TAU * (h.x + vec3(0.0, 0.33, 0.67)))) * (0.7 + 0.4 * treble), smoothstep(r + px, r - px, l));
		col += vec3(1.0) * smoothstep(r * 0.5, 0.0, length(c - pos - vec2(-r * 0.3, r * 0.3))) * (0.3 + 0.25 * treble);
	}

	// The mirrors: each reflection a little dimmer and cooler, the joins faint.
	col *= pow(0.91, bounces) * mix(vec3(1.0), vec3(0.94, 0.97, 1.0), clamp(bounces * 0.15, 0.0, 1.0));
	col *= 0.8 + 0.2 * smoothstep(0.0, 0.004, seam);

	// The tube: the round field of view, dark beyond, a faint ring where the eyepiece ends.
	float field_r = 0.485;
	col *= smoothstep(field_r, field_r - 0.02, tube);
	col += vec3(0.05, 0.045, 0.04) * smoothstep(0.012, 0.0, abs(tube - field_r - 0.012));
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
