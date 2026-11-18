// Runner (visualiser.json): a side-scrolling pixel game that plays itself. Everything is worked out from the music's
// clock (drive), so it needs no memory: the world scrolls at speed game pixels per drive second (faster when loud),
// crates and spikes stand on every other tile of the ground, and the runner jumps each one on a parabola that clears
// it. Between them, it hops on every beat (the beat's fall is the hop). Coins on the other tiles vanish into a
// sparkle as the runner passes. Behind: a sky in bands, a striped sun, a city whose towers are the spectrum (low
// notes left), and hills scrolling at half speed. The score counts the beats.
shader_type canvas_item;
#include "res://visualisers/visualiser.gdshaderinc"

uniform float speed = 36.0;
uniform int pixel = 4;
uniform bool score = true;
uniform vec4 sky_top : source_color = vec4(0.1, 0.09, 0.25, 1.0);
uniform vec4 sky_low : source_color = vec4(0.78, 0.34, 0.48, 1.0);
uniform vec4 shirt : source_color = vec4(0.25, 0.65, 0.84, 1.0);

// Tiles of the ground: an obstacle may stand on the even ones, a coin on the odd ones.
const float TILE = 28.0;

uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 2146121005u;
	x ^= x >> 15u;
	x *= 2221713035u;
	x ^= x >> 16u;
	return x;
}

float hash2(float a, float b) {
	uint h = hash_u(uint(int(a)) * 73856093u ^ uint(int(b)) * 19349663u);
	return float(h & 16777215u) / 16777215.0;
}

// The obstacle on tile k: 0 none, 1 crate, 2 tall crate, 3 spikes.
int obstacle(float k) {
	if (mod(k, 2.0) > 0.5 || k < 2.0) {
		return 0;
	}
	float h = hash2(k, 1.0);
	return h < 0.25 ? 0 : h < 0.6 ? 1 : h < 0.8 ? 2 : 3;
}

vec2 obstacle_size(int o) {
	return o == 1 ? vec2(7.0, 7.0) : o == 2 ? vec2(7.0, 12.0) : o == 3 ? vec2(9.0, 4.0) : vec2(0.0);
}

// How high the runner is over the ground when its middle is at world x c.
float lift(float c) {
	float best = 0.0;
	float k0 = floor(c / TILE);
	for (int i = -1; i <= 1; i++) {
		float k = k0 + float(i);
		int o = obstacle(k);
		if (o == 0) {
			continue;
		}
		vec2 s = obstacle_size(o);
		float half_len = 9.0 + s.x * 0.5 + s.y * 0.4;
		float x = (c - (k * TILE + TILE * 0.5)) / half_len;
		if (abs(x) < 1.0) {
			best = max(best, (s.y + 4.0) * (1.0 - x * x) * 1.15);
		}
	}
	if (best > 0.0) {
		return floor(best);
	}
	// Between obstacles: a hop on the beat.
	return floor(4.0 * beat * (1.0 - beat) * 5.0);
}

// 3 x 5 digits, a row of 3 bits each, the top row highest.
int glyph(int d) {
	return d == 0 ? 31599 : d == 1 ? 11415 : d == 2 ? 29671 : d == 3 ? 29647 : d == 4 ? 23497 : d == 5 ? 31183
			: d == 6 ? 31215 : d == 7 ? 29257 : d == 8 ? 31727 : 31695;
}

// 1 where the six-digit score is lit at game pixel g (its top left at o).
float digits(vec2 g, vec2 o, float value) {
	vec2 q = g - o;
	if (q.x < 0.0 || q.y < 0.0 || q.y >= 5.0 || q.x >= 24.0) {
		return 0.0;
	}
	float i = floor(q.x / 4.0);
	float cx = mod(q.x, 4.0);
	if (cx > 2.5) {
		return 0.0;
	}
	int d = int(mod(floor(value / pow(10.0, 5.0 - i)), 10.0));
	int bit = (4 - int(q.y)) * 3 + (2 - int(cx));
	return float((glyph(d) >> bit) & 1);
}

void fragment() {
	float pix = float(max(pixel, 1));
	vec2 g = floor(UV * size / pix);
	vec2 dim = floor(size / pix);
	float ground = floor(dim.y * 0.82);
	float scroll = floor(drive * speed);
	float wx = g.x + scroll;

	// The sky, in eight bands.
	float b = floor(clamp(g.y / ground, 0.0, 1.0) * 8.0) / 7.0;
	vec3 col = mix(sky_top.rgb, sky_low.rgb, b);
	if (g.y < ground * 0.6 && hash2(g.x, g.y) > 0.996) {
		col = mix(col, vec3(1.0, 0.95, 0.85), 0.8);
	}
	// The sun: a disc with gaps across its lower half.
	vec2 sun = vec2(floor(dim.x * 0.72), floor(ground * 0.5));
	float sr = floor(dim.y * 0.2);
	vec2 sd = g - sun;
	if (length(sd) < sr) {
		float gap = sd.y > 0.0 && mod(sd.y, 4.0) < 1.0 + sd.y / sr * 2.0 ? 1.0 : 0.0;
		col = mix(mix(vec3(1.0, 0.85, 0.35), vec3(1.0, 0.45, 0.4), clamp(sd.y / sr * 0.5 + 0.5, 0.0, 1.0)), col, gap);
	}
	// The city: towers 5 wide whose heights are the spectrum, with lit windows.
	float towers = floor(dim.x / 5.0);
	float ti = floor(g.x / 5.0);
	float tx = mod(g.x, 5.0);
	float th = floor((0.12 + 0.75 * band((ti + 0.5) / towers)) * ground * 0.75);
	if (tx < 4.0 && g.y >= ground - th && g.y < ground) {
		col = vec3(0.16, 0.11, 0.24);
		if ((tx == 1.0 || tx == 2.0) && mod(g.y, 3.0) == 1.0 && hash2(ti, floor(g.y / 3.0) + 50.0) > 0.55) {
			col = vec3(1.0, 0.82, 0.45);
		}
	}
	// Hills at half speed.
	float hx = g.x + floor(scroll * 0.5);
	float hill = floor(ground - dim.y * (0.05 + 0.08 * (0.5 + 0.5 * sin(hx * 0.05) * sin(hx * 0.013 + 1.0))));
	if (g.y >= hill && g.y < ground) {
		col = g.y == hill ? vec3(0.22, 0.5, 0.3) : vec3(0.13, 0.33, 0.22);
	}
	// The ground: grass, then earth with a faint speckle fixed to the world.
	if (g.y >= ground) {
		col = g.y == ground ? vec3(0.4, 0.78, 0.33) : g.y == ground + 1.0 ? vec3(0.27, 0.6, 0.25)
				: vec3(0.42, 0.27, 0.17) * (0.92 + 0.08 * hash2(wx, g.y));
	}

	// Obstacles.
	float k = floor(wx / TILE);
	int o = obstacle(k);
	if (o != 0) {
		vec2 s = obstacle_size(o);
		float ox = wx - (k * TILE + TILE * 0.5 - floor(s.x * 0.5));
		float oy = g.y - (ground - s.y);
		if (ox >= 0.0 && ox < s.x && oy >= 0.0 && oy < s.y) {
			if (o == 3) {
				// Spikes: two triangles.
				float m = mod(ox, s.x * 0.5) - s.x * 0.25;
				if (oy >= abs(m) * 2.0 - 1.0) {
					col = oy < 1.0 ? vec3(0.95) : vec3(0.68, 0.7, 0.75);
				}
			} else {
				bool rim = ox < 1.0 || ox >= s.x - 1.0 || oy < 1.0 || oy >= s.y - 1.0;
				bool cross = abs(ox - oy * (s.x - 1.0) / (s.y - 1.0)) < 0.8;
				col = rim ? vec3(0.45, 0.27, 0.12) : cross ? vec3(0.55, 0.35, 0.16) : vec3(0.78, 0.54, 0.28);
			}
		}
	}
	// Coins: on the odd tiles, gone once the runner has passed (a sparkle rises where each was).
	float runner_x = floor(dim.x * 0.22) + scroll;
	float middle = runner_x + 2.0;
	float ck = k;
	if (mod(ck, 2.0) > 0.5 && hash2(ck, 2.0) < 0.75) {
		float cx = ck * TILE + TILE * 0.5;
		float cy = ground - 5.0;
		float spin = mod(floor(vis_time * 8.0 + ck), 4.0);
		float w = spin == 0.0 ? 1.5 : spin == 2.0 ? 0.5 : 1.0;
		if (cx > middle + 1.0) {
			if (abs(wx - cx) <= w && abs(g.y - cy) <= 1.5) {
				col = abs(wx - cx) > w - 0.6 ? vec3(0.85, 0.6, 0.1) : vec3(1.0, 0.85, 0.25);
			}
		} else {
			float since = middle - cx;
			if (since < 14.0) {
				float sy = cy - 2.0 - floor(since * 0.5);
				bool plus = (wx == cx && abs(g.y - sy) <= 1.0) || (g.y == sy && abs(wx - cx) <= 1.0);
				if (plus) {
					col = mix(vec3(1.0, 0.95, 0.6), col, since / 14.0);
				}
			}
		}
	}

	// The runner: 5 x 8, its middle at world x middle.
	float up = lift(middle);
	float rx = wx - runner_x;
	float ry = g.y - (ground - 8.0 - up);
	if (rx >= 0.0 && rx < 5.0 && ry >= 0.0 && ry < 8.0) {
		bool air = up > 0.0;
		bool step_a = mod(floor(middle / 3.0), 2.0) < 0.5;
		vec3 c = vec3(-1.0);
		if (ry < 1.0) {
			c = rx >= 1.0 && rx < 4.0 ? vec3(0.2, 0.12, 0.08) : c;
		} else if (ry < 3.0) {
			c = rx >= 1.0 && rx < 4.0 ? (rx == 3.0 && ry < 2.0 ? vec3(0.1) : vec3(0.98, 0.78, 0.62)) : c;
		} else if (ry < 4.0) {
			c = shirt.rgb;
		} else if (ry < 5.0) {
			c = rx >= 1.0 && rx < 4.0 ? shirt.rgb : c;
		} else if (ry < 6.0) {
			c = rx >= 1.0 && rx < 4.0 ? vec3(0.2, 0.22, 0.4) : c;
		} else {
			// Legs: spread in the air; two steps on the ground.
			bool leg = air ? ry < 7.0 && (rx == 0.0 || rx == 4.0)
					: step_a ? rx == 1.0 || rx == 3.0
					: ry < 7.0 ? rx >= 1.0 && rx <= 3.0 : rx == 2.0;
			c = leg ? vec3(0.2, 0.22, 0.4) : c;
		}
		if (c.r >= 0.0) {
			col = c;
		}
	}
	// The score.
	if (score && digits(g, vec2(3.0, 3.0), beats * 10.0) > 0.5) {
		col = vec3(1.0, 0.97, 0.88);
	}
	COLOR = vec4(col, 1.0);
}
