shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// 2004 British GT laminated raked windscreen with subtle tinted sunband, delicate glistening rain droplets,
// and a live twin-blade wiper dry-arc clearing mask synced to the physical wiper arms!

uniform float rain = 0.0;
uniform float wet = 0.0;
uniform float wiper_phase = 0.0; // 0..1 continuous sweep cycle
uniform float day_level = 0.5;
uniform float time_sec = 0.0;
uniform vec3 sky_tint = vec3(0.45, 0.55, 0.72);

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.5);
	return fract(p.x * p.y);
}

// Compute how recently a wiper anchored at pivot (u, v) swept across point p.
// Returns 1.0 = freshly wiped crystal-clear dry glass, 0.0 = outside arc or re-wetted.
float wiper_clear(vec2 p, vec2 pivot, float radius, float ang_now, float sweep_dir) {
	vec2 d = p - pivot;
	float r = length(d);
	float in_arc = smoothstep(radius + 0.025, radius - 0.035, r) * smoothstep(0.08, 0.14, r);
	if (in_arc <= 0.001) {
		return 0.0;
	}
	float a = atan(-d.y, d.x);
	float in_span = smoothstep(0.22, 0.30, a) * smoothstep(2.74, 2.64, a);
	if (in_span <= 0.001) {
		return 0.0;
	}
	float behind = (a - ang_now) * (-sweep_dir);
	float freshness = behind >= -0.05 ? exp(-max(behind, 0.0) * 0.85) : 0.55 * exp(-abs(behind) * 0.55);
	return in_arc * in_span * clamp(freshness, 0.0, 1.0);
}

float rain_layer(vec2 uv, vec2 scale, float speed, float seed) {
	vec2 g = uv * scale;
	g.y += time_sec * speed;
	vec2 cell = floor(g);
	vec2 f = fract(g) - 0.5;
	float h1 = hash21(cell + seed);
	float h2 = hash21(cell * 1.37 + seed + 19.1);
	if (h1 < 0.62) {
		return 0.0;
	}
	vec2 off = vec2((h1 - 0.80) * 1.4, (h2 - 0.5) * 0.55);
	vec2 d = f - off;
	float r = 0.06 + (h1 - 0.62) * 0.18;
	float bead = smoothstep(r, r * 0.25, length(vec2(d.x * 1.35, d.y * 0.65)));
	float glint = smoothstep(r * 0.6, 0.0, length(d - vec2(-r * 0.22, -r * 0.24))) * 0.65;
	return bead * 0.55 + glint;
}

void fragment() {
	vec2 uv = UV;
	// Subtle factory automotive green-grey top tint band & edge glass sheen
	float sunband = smoothstep(0.18, 0.0, uv.y) * 0.20;
	float edge_sheen = (smoothstep(0.10, 0.0, uv.x) + smoothstep(0.90, 1.0, uv.x)) * 0.05;
	float base_alpha = 0.025 + sunband + edge_sheen;
	vec3 col = mix(vec3(0.06, 0.09, 0.12), sky_tint * (0.28 + 0.50 * day_level), 0.50);

	if (rain > 0.03 || wet > 0.08) {
		float cyc = fract(wiper_phase);
		float s_pos = cyc < 0.5 ? smoothstep(0.04, 0.46, cyc) : (1.0 - smoothstep(0.54, 0.96, cyc));
		float sweep_dir = cyc < 0.5 ? 1.0 : -1.0;
		float ang_now = mix(0.28, 2.38, s_pos);

		// Twin UK RHD tandem wiper arcs (aspect-corrected UV space)
		vec2 p_asp = vec2(uv.x * 2.15, uv.y);
		float c1 = wiper_clear(p_asp, vec2(0.54, 1.05), 0.98, ang_now, sweep_dir);
		float c2 = wiper_clear(p_asp, vec2(1.48, 1.05), 0.98, ang_now, sweep_dir);
		float cleared = clamp(max(c1, c2) * smoothstep(0.05, 0.15, rain), 0.0, 0.96);

		// Two organic staggered raindrop layers (sparse glistening beads — NEVER obscuring motorway signs!)
		float d1 = rain_layer(uv, vec2(26.0, 13.0), 1.6 + rain * 2.2, 3.1);
		float d2 = rain_layer(uv + vec2(0.37, 0.19), vec2(42.0, 22.0), 2.4 + rain * 3.0, 11.7) * 0.72;
		float drops_vis = clamp(d1 + d2, 0.0, 1.0) * rain * (1.0 - cleared * 0.94);
		float mist_film = (0.11 * rain + 0.04 * wet) * (1.0 - cleared * 0.92);

		vec3 drop_col = mix(vec3(0.42, 0.50, 0.62), vec3(0.88, 0.92, 0.98), 0.35 + 0.55 * day_level);
		col = mix(col, drop_col, clamp(mist_film * 2.2 + drops_vis * 0.75, 0.0, 0.92));
		base_alpha += mist_film * 0.48 + drops_vis * 0.24;
	}

	ALBEDO = col;
	ALPHA = clamp(base_alpha, 0.015, 0.36);
}
