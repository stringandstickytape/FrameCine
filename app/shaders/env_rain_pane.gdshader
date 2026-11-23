// Rain on a window pane (scripts/env/systems/weather.gd): drops on the glass drawn over whatever is behind it (a sky,
// a vista, the dark). All procedural, from a few grids: small beads that come and go while it rains and stay a while
// after (wet), and drops that run down in wavering paths, each leaving a trail of beads. A drop is a small lens: a
// dark rim and a bright spot low in it where the room's light and the film's spill come through. No screen texture
// (it would cost a copy every frame on the Mobile renderer). Blended with alpha.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

// Rain falling now and the glass still wet (0..1 each).
uniform float rain = 0.0;
uniform float wet = 0.0;
// The pane's size in metres (fallback for single QuadMesh; merged panes carry their own size in UV2).
uniform vec2 pane_size = vec2(1.2, 1.0);
uniform vec3 colour : source_color = vec3(0.8, 0.85, 0.95);
uniform float opacity = 0.55;
// Dried sea-salt spray rime near window seals (0..1) and sideways wind drift blowing rain streaks aft (-2..2).
uniform float salt = 0.0;
uniform float drift = 0.0;

#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;
varying vec2 p_size;
varying float p_seed;
varying float p_aft;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	bool merged = UV2.x > 0.01;
	p_size = merged ? UV2 : pane_size;
	p_seed = merged ? COLOR.r * 37.0 : 0.0;
	p_aft = merged ? (COLOR.g * 2.0 - 1.0) : 1.0;
}

float pane_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float pane_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = pane_hash(i);
	float b = pane_hash(i + vec2(1.0, 0.0));
	float c = pane_hash(i + vec2(0.0, 1.0));
	float d = pane_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// One bead per cell of a grid `cells` metres apart: x lens shade (0..1), y its mask. present: share of cells with one.
vec2 beads(vec2 m, float cells, float present, float t, float seed) {
	vec2 q = m / cells;
	vec2 id = floor(q);
	vec2 f = fract(q) - 0.5;
	float h = pane_hash(id + seed);
	// Each bead lives over a slow cycle of its own: born while it rains, gone again later.
	float life = fract(t * (0.02 + 0.03 * pane_hash(id + seed + 4.0)) + h);
	float here = step(h * 0.999, present) * (1.0 - smoothstep(0.75, 1.0, life)) * smoothstep(0.0, 0.05, life);
	vec2 at = (vec2(pane_hash(id + seed + 1.0), pane_hash(id + seed + 2.0)) - 0.5) * 0.5;
	float r = mix(0.12, 0.3, pane_hash(id + seed + 3.0));
	float d = length(f - at) / r;
	float mask = (1.0 - smoothstep(0.85, 1.0, d)) * here;
	float spot = 1.0 - smoothstep(0.0, 0.55, length((f - at) / r - vec2(0.0, -0.35)));
	return vec2(spot, mask);
}

// Drops running down in columns `width` metres wide: x lens shade, y mask (the drop and its trail of beads).
vec2 runners(vec2 m, float width, float amount, float t, float span_y, float seed) {
	float col = floor(m.x / width);
	float h = pane_hash(vec2(col, 17.0 + seed));
	if (h > amount) {
		return vec2(0.0);
	}
	float speed = mix(0.06, 0.16, pane_hash(vec2(col, 5.0 + seed)));
	float span = span_y + 0.6;
	float head = span_y + 0.3 - mod(t * speed + h * span, span);
	// The path wavers as the drop picks its way down.
	float path = (col + 0.5) * width + width * 0.28 * sin(m.y * 9.0 + h * 30.0) * sin(m.y * 3.7 + h * 11.0);
	float dx = (m.x - path) / width;
	float dy = m.y - head;
	float drop = 1.0 - smoothstep(0.7, 1.0, length(vec2(dx * 3.2, dy / 0.012)));
	float spot = drop * (1.0 - smoothstep(0.0, 0.6, length(vec2(dx * 3.2, (dy + 0.004) / 0.008))));
	// The trail: beads above the head, fewer further up.
	float trail_len = 0.25 + 0.3 * h;
	float above = dy > 0.0 && dy < trail_len ? 1.0 - dy / trail_len : 0.0;
	float bead_y = fract(m.y / 0.018 + h * 7.0) - 0.5;
	float bead = (1.0 - smoothstep(0.15, 0.3, length(vec2(dx * 2.0, bead_y * 0.6))))
			* step(0.45, pane_hash(vec2(col, floor(m.y / 0.018 + h * 7.0))));
	float trail = bead * above;
	return vec2(spot, max(drop, trail * 0.8));
}

void fragment() {
	vec2 m = vec2(UV.x, 1.0 - UV.y) * p_size;
	float present = clamp(max(rain, wet * 0.7), 0.0, 1.0);
	float marine = step(0.001, salt);
	vec2 a = beads(m, 0.024, present * mix(0.5, 0.28, marine), TIME, p_seed);
	vec2 b = beads(m + 0.37, 0.048, present * mix(0.35, 0.2, marine), TIME * 0.8, 9.0 + p_seed);
	// Wind-driven sideways shear blows rain streaks bow-to-stern while the cabin moves.
	vec2 mr = vec2(m.x + m.y * drift * p_aft * 0.42, m.y);
	vec2 r = runners(mr, 0.05, clamp(rain, 0.0, 1.0) * 0.55, TIME, p_size.y, p_seed);
	float mask = max(max(a.y, b.y), r.y);
	float spot = max(max(a.x * a.y, b.x * b.y), r.x);
	// Dried sea-salt spray rime clinging near the rubber gaskets and bottom sills, keeping centre glass clear.
	float salt_mask = 0.0;
	if (salt > 0.001) {
		float edge_d = min(min(m.x, p_size.x - m.x), min(m.y, p_size.y - m.y));
		float sill_weight = mix(0.55, 1.0, smoothstep(0.45, 0.0, UV.y));
		float rim_band = smoothstep(0.16, 0.0, edge_d) * sill_weight;
		float n_rime = pane_noise(m * 16.0 + vec2(p_seed, p_seed * 0.7)) * 0.6
				+ pane_noise(m * 38.0 + vec2(p_seed * 1.9, 3.0)) * 0.4;
		float n_streak = pane_noise(vec2(m.x * 3.5 + m.y * p_aft * 1.4, m.y * 20.0) + p_seed);
		salt_mask = salt * clamp(rim_band * smoothstep(0.28, 0.78, n_rime) * 0.95
				+ smoothstep(0.76, 0.96, n_streak) * 0.09, 0.0, 1.0);
	}
	// A drop's edge refracts what is behind it; its low spot gathers the light.
	vec3 light = min(room_light_at(world_pos, 0.8) * 1.6 + vec3(0.03), vec3(1.4));
	vec3 rim = mix(vec3(0.01), vec3(0.16, 0.21, 0.26) * max(light, vec3(0.18)), marine);
	vec3 shade = mix(rim, colour * light * 1.6, spot);
	// Wet glass & salt rime: faint marine glass sheen plus pale sea-salt residue near the seals.
	vec3 glass_col = mix(colour * light, vec3(0.8, 0.86, 0.9) * max(light, vec3(0.14)), salt_mask);
	float sheen = 0.035 * wet + 0.015 * marine + salt_mask * 0.28;
	ALBEDO = mix(glass_col, shade, step(0.001, mask));
	ALPHA = clamp(opacity * mask * (mix(0.45, 0.18, marine) + mix(0.55, 0.78, marine) * spot) + sheen, 0.0, 1.0);
}
