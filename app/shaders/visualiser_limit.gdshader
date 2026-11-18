// The visualisers' flash limit, last pass (scripts/visualisers/visualiser_host.gd, docs/visualisers.md, "The flash
// limit"): a 2 x 2 viewport (the engine's smallest), each pixel holding one result, from the 16 x 9 cells of
// visualiser_cells.gdshader and last frame's results (`previous`, the copy of this pass). Two rules:
//  - The whole picture's brightness: a floor follows the average down at once and up at most `rise` a second, and the
//    picture may stand at most `margin` over it (a gain on the whole picture).
//  - Flicker over an area: the cells' flicker, as a share of the card (`area_share`: the visualiser's area over the
//    card's), may total at most `flicker_max`. Over that, a cap `k` is found such that capping every cell's flicker at
//    k brings the total down to the limit; the card dims a cell with flicker C by k / C. The cap drops at once and
//    doubles every `recover` seconds back towards none (1).
// Out, (0, 0): r, g the floor (two bytes), b the measured average (square root), a the gain of the first rule.
//      (1, 0): r, g the cap k (two bytes).   (0, 1): r, g the flicker total as a share of the card (two bytes),
//      b the largest cell's flicker (square root).   (1, 1): as (0, 0).
shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D cells : filter_nearest, repeat_disable;
uniform sampler2D previous : filter_nearest, repeat_disable;
uniform vec2 grid = vec2(16.0, 9.0);
uniform float dt = 0.0167;
uniform float margin = 0.08;
uniform float rise = 0.2;
uniform float area_share = 1.0;
uniform float flicker_max = 0.02;
uniform float recover = 0.25;
uniform bool reset = true;

float two(vec4 c) {
	return c.r + c.g / 255.0;
}

vec2 enc(float v) {
	v = clamp(v, 0.0, 1.0);
	return vec2(floor(v * 255.0) / 255.0, fract(v * 255.0));
}

// The flicker total (a share of the card) with every cell capped at k.
float total(float k) {
	float s = 0.0;
	for (int y = 0; y < int(grid.y); y++) {
		for (int x = 0; x < int(grid.x); x++) {
			s += min(two(texture(cells, (vec2(float(x), float(y)) + 0.5) / grid)), k);
		}
	}
	return area_share * s / (grid.x * grid.y);
}

void fragment() {
	float raw = 0.0;
	float most = 0.0;
	for (int y = 0; y < int(grid.y); y++) {
		for (int x = 0; x < int(grid.x); x++) {
			vec4 c = texture(cells, (vec2(float(x), float(y)) + 0.5) / grid);
			raw += c.b + c.a / 255.0;
			most = max(most, two(c));
		}
	}
	raw /= grid.x * grid.y;
	// The whole picture's brightness.
	vec4 p = texture(previous, vec2(0.25, 0.25));
	float floor_was = reset ? raw : two(p);
	float shown = min(raw, floor_was + margin);
	float gain = raw > 0.0001 ? shown / raw : 1.0;
	float floor_now = clamp(min(shown, floor_was + rise * dt), 0.0, 1.0);
	// Flicker over an area: the largest cap that keeps the total at the limit (bisection).
	float flicker = total(1.0);
	float target = 1.0;
	if (flicker > flicker_max) {
		float lo = 0.0;
		float hi = most;
		for (int i = 0; i < 12; i++) {
			float mid = 0.5 * (lo + hi);
			if (total(mid) <= flicker_max) {
				lo = mid;
			} else {
				hi = mid;
			}
		}
		target = lo;
	}
	float k_was = reset ? 1.0 : two(texture(previous, vec2(0.75, 0.25)));
	float k = target < k_was ? target : min(target, k_was * exp2(dt / recover) + 0.0005);
	vec2 px = floor(UV * 2.0);
	if (px.x > 0.5 && px.y < 0.5) {
		COLOR = vec4(enc(k), 0.0, 1.0);
	} else if (px.x < 0.5 && px.y > 0.5) {
		COLOR = vec4(enc(flicker), sqrt(most), 1.0);
	} else {
		COLOR = vec4(enc(floor_now), sqrt(raw), gain);
	}
}
