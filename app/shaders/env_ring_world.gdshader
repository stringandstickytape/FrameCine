// Procedural O'Neill cylinder space habitat interior world shader (Orbital ring).
// Opaque and unshaded (zero blend overdraw, 1 draw for the entire rotating cylinder shell,
// structural tension rings, longitudinal window girders, alpine mountain end-caps, and axial solar hubs).
//
// Vertex attributes:
//   UV     - kind 0.0 (land strips): x = across strip (0..1), y = along cylinder length (0..1)
//            kind 0.35 (end-cap mountain ring): x = radial inward (0..1), y = circumference (0..3)
//            kind 1.0 (structural titanium ring-ribs & girders): x = profile across (0..1), y = span along
//            kind 2.0 (axial solar/docking hub core): x = radial (0..1), y = azimuth (0..1)
//   UV2.x  - surface kind: 0.0 land valley, 0.35 end-cap mountains, 1.0 titanium structure, 2.0 axial hub
//   UV2.y  - land strip index (0.0, 1.0, 2.0) for distinct coastlines, rivers, fields, and city grids
//   COLOR  - rgb subtle structural/elevation tint, a elevation hint (0 valley .. 1 high end-cap ridge)
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled, fog_disabled;

uniform sampler2D noise_map : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float clock = 0.0;
// 0.0 = Night city lights, 1.0 = Golden hour, 2.0 = Twilight glow.
uniform float time_mood = 0.0;
// Smooth normalized blend weights: x = night, y = golden hour, z = twilight glow.
uniform vec3 mood_weights = vec3(1.0, 0.0, 0.0);
// Gentle cinema dimming while a film plays (keeps the upside-down world visible without competing).
uniform float film_dim = 1.0;
uniform float spill_strength = 0.32;
uniform vec3 cylinder_axis = vec3(0.0, 68.0, 0.0);

#include "res://shaders/env_spill.gdshaderinc"

varying vec3 world_pos;
varying vec3 world_normal;
varying vec2 v_uv;
varying vec2 v_meta;
varying vec4 v_col;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_uv = UV;
	v_meta = UV2;
	v_col = COLOR;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 rot2(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// Sculpted alpine mountain-ring end-cap: lush conifer foothills, broad painterly directional granite mountain massifs,
// crisp snow-crowned summit ridges (zero high-frequency speckle!), and delicate winding hillside mountain-pass lights.
vec3 shade_endcap(vec2 uv, float sid, float elev_hint, vec3 wpos, vec3 wnrm, vec3 view_dir, vec3 cam_pos) {
	vec3 mw = mood_weights / max(mood_weights.x + mood_weights.y + mood_weights.z, 0.001);
	float w_night = mw.x;
	float w_golden = mw.y;
	float w_twilight = mw.z;

	// uv.x = radial inward from cylinder rim (0.0) to sky collar (1.0); uv.y = azimuth around circumference (0..3).
	float r_in = uv.x;
	float ang = uv.y * 2.094395; // 0 .. TAU
	vec2 polar = vec2(cos(ang), sin(ang)) * (1.15 + r_in * 0.85) + vec2(sid * 0.27, sid * 0.41);

	// Broad, majestic macro mountain massifs (low-frequency octaves so distant ridges read cleanly without speckle!).
	vec4 n0 = texture(noise_map, polar * 0.34);
	vec4 n1 = texture(noise_map, polar * 0.86 + vec2(0.31, 0.17));
	vec4 n2 = texture(noise_map, polar * 1.85 - vec2(0.19, 0.43));

	float r1 = 1.0 - abs(n0.b * 2.0 - 1.0);
	float r2 = 1.0 - abs(n1.b * 2.0 - 1.0);
	float ridge = r1 * r1 * 0.65 + r2 * r2 * 0.35;
	float alt = clamp(r_in * 0.88 + ridge * 0.36 + (elev_hint - 0.5) * 0.14 - 0.14, 0.0, 1.0);

	// Clean broad topographic slope normal for dramatic sunlit/moonlit mountain faces and deep glacial valleys.
	float eps = 0.045;
	float h_c = n0.r * 0.65 + n1.g * 0.35;
	float h_x = texture(noise_map, (polar + vec2(eps, 0.0)) * 0.34).r * 0.65
			+ texture(noise_map, (polar + vec2(eps, 0.0)) * 0.86 + vec2(0.31, 0.17)).g * 0.35;
	float h_y = texture(noise_map, (polar + vec2(0.0, eps)) * 0.34).r * 0.65
			+ texture(noise_map, (polar + vec2(0.0, eps)) * 0.86 + vec2(0.31, 0.17)).g * 0.35;
	vec3 crag_n = normalize(wnrm + vec3((h_c - h_x) * 3.8, (h_c - h_y) * 3.8, 0.0));

	// Painterly alpine elevation biomes: conifer forest foothills -> dark granite cliffs -> crisp high-ridge snowcaps!
	vec3 pine = mix(vec3(0.055, 0.145, 0.09), vec3(0.13, 0.24, 0.14), n1.r);
	vec3 meadow = vec3(0.24, 0.34, 0.18);
	vec3 granite = mix(vec3(0.14, 0.165, 0.21), vec3(0.30, 0.31, 0.33), smoothstep(0.28, 0.78, n2.r));
	vec3 snow = vec3(0.86, 0.90, 0.96);

	vec3 albedo = mix(pine, meadow, smoothstep(0.38, 0.74, n0.g) * (1.0 - smoothstep(0.18, 0.46, alt)));
	albedo = mix(albedo, granite, smoothstep(0.34, 0.62, alt));
	// Snow crowns ONLY the upper alpine ridge spines (`r_in > 0.45`, high `alt` and `ridge`), never noisy speckle!
	float snow_mask = smoothstep(0.68, 0.84, alt + ridge * 0.14) * smoothstep(0.38, 0.68, r_in);
	albedo = mix(albedo, snow, snow_mask);

	// Crisp directional light across the broad mountain massifs.
	vec3 sun_g = normalize(vec3(0.60, 0.46, 0.65));
	vec3 sun_t = normalize(vec3(-0.52, 0.40, 0.75));
	vec3 moon_n = normalize(vec3(0.35, 0.65, 0.67));
	float lg = clamp(dot(crag_n, sun_g), 0.0, 1.0);
	float lt = clamp(dot(crag_n, sun_t), 0.0, 1.0);
	float ln = clamp(dot(crag_n, moon_n), 0.0, 1.0);

	vec3 col_n = albedo * mix(vec3(0.05, 0.085, 0.16), vec3(0.24, 0.34, 0.52), pow(ln, 0.9))
			+ vec3(0.12, 0.18, 0.29) * snow_mask * (0.25 + 0.75 * ln);
	vec3 col_g = albedo * mix(vec3(0.15, 0.20, 0.31), vec3(1.12, 0.80, 0.46), pow(lg, 0.9))
			+ vec3(0.26, 0.18, 0.08) * snow_mask * lg;
	vec3 col_t = albedo * mix(vec3(0.085, 0.09, 0.22), vec3(0.90, 0.44, 0.44), pow(lt, 0.9))
			+ vec3(0.22, 0.12, 0.16) * snow_mask * lt;
	vec3 col = col_n * w_night + col_g * w_golden + col_t * w_twilight;

	// Delicate winding alpine mountain-pass lights & foothill terrace villages along the lower green rim (`r_in < 0.38`)!
	float ring_road = 1.0 - smoothstep(0.008, 0.022, abs(r_in - (0.14 + 0.045 * sin(ang * 6.0 + n0.r * 2.0))));
	float hill_towns = smoothstep(0.60, 0.84, n1.g) * (1.0 - smoothstep(0.10, 0.40, r_in));
	vec2 vcell = floor(vec2(ang * 30.0, r_in * 44.0));
	vec2 vfrac = fract(vec2(ang * 30.0, r_in * 44.0));
	float vdot = (1.0 - smoothstep(0.12, 0.34, length(vfrac - 0.5))) * step(0.45, hash21(vcell + sid * 13.0));
	float pass_dots = smoothstep(0.45, 0.85, sin(ang * 84.0 + n2.r * 5.0)) * ring_road;
	float night_glow = w_night * 0.95 + w_golden * 0.04 + w_twilight * 0.65;
	col += vec3(1.0, 0.74, 0.36) * (pass_dots * 0.65 + vdot * hill_towns * 1.15) * night_glow;

	// Subtle alpine valley mist pooling gently near the outer foothills + restrained aerial depth perspective!
	float dist = length(wpos - cam_pos);
	float foot_mist = (1.0 - smoothstep(0.0, 0.26, r_in)) * 0.16;
	float haze_f = smoothstep(78.0, 195.0, dist) * 0.22 + foot_mist;
	vec3 haze_col = vec3(0.024, 0.046, 0.10) * w_night
			+ vec3(0.56, 0.39, 0.21) * w_golden
			+ vec3(0.22, 0.12, 0.26) * w_twilight;
	col = mix(col, haze_col, clamp(haze_f, 0.0, 0.42));
	return col * film_dim;
}

// Analytical + shared-noise valley terrain, winding silver rivers, agricultural patchwork, and organic night cities.
vec3 shade_land(vec2 uv, float sid, float elev_hint, vec3 wpos, vec3 wnrm, vec3 view_dir, vec3 cam_pos) {
	vec3 mw = mood_weights / max(mood_weights.x + mood_weights.y + mood_weights.z, 0.001);
	float w_night = mw.x;
	float w_golden = mw.y;
	float w_twilight = mw.z;

	float u = uv.x;
	float v = uv.y;
	vec2 seed_off = vec2(sid * 0.371 + 0.13, sid * 0.583 + 0.29);

	vec4 n0 = texture(noise_map, vec2(u * 1.35, v * 3.1) + seed_off);
	vec4 n1 = texture(noise_map, vec2(u * 3.6, v * 9.2) + seed_off * 1.7);
	vec4 n2 = texture(noise_map, vec2(u * 9.5, v * 24.0) - seed_off * 0.9);
	float h_here = n0.r * 0.55 + n1.g * 0.30 + n2.b * 0.15;
	float h_dx = texture(noise_map, vec2(u * 1.35 + 0.015, v * 3.1) + seed_off).r * 0.55
			+ texture(noise_map, vec2(u * 3.6 + 0.03, v * 9.2) + seed_off * 1.7).g * 0.30;
	float h_dy = texture(noise_map, vec2(u * 1.35, v * 3.1 + 0.015) + seed_off).r * 0.55
			+ texture(noise_map, vec2(u * 3.6, v * 9.2 + 0.03) + seed_off * 1.7).g * 0.30;

	// Sculpted foothills & mountain ridges framing both longitudinal window borders and both ends of the strip.
	float edge_d = min(u, 1.0 - u);
	float end_d = min(v, 1.0 - v);
	float ridge_noise = 1.0 - abs(n1.b * 2.0 - 1.0);
	float border_mtn = smoothstep(0.18, 0.015, edge_d) * (0.55 + 0.45 * ridge_noise);
	float end_mtn = smoothstep(0.11, 0.01, end_d) * (0.55 + 0.45 * ridge_noise);
	float mtn_elev = clamp(max(border_mtn, end_mtn) + elev_hint * 0.30 + max(n0.r - 0.64, 0.0) * 1.1, 0.0, 1.0);

	// Smooth sinuous silver river + graceful coastal lake widenings + branching valley tributary.
	float river_c = 0.50 + 0.16 * sin(v * 7.8 + sid * 2.15) + 0.075 * sin(v * 16.4 - sid * 1.5)
			+ 0.032 * (n0.g - 0.5);
	float river_d = abs(u - river_c);
	float bay_widen = smoothstep(0.60, 0.86, n0.b) * 0.036;
	float river_w = 0.020 + bay_widen + 0.008 * sin(v * 12.5 + sid * 3.1);
	float trib_c = 0.50 + (sid < 1.5 ? 0.22 : -0.20) + 0.095 * sin(v * 10.5 + sid * 4.2 + 0.9);
	float trib_d = abs(u - trib_c);
	float trib_mask = smoothstep(0.18, 0.34, v) * (1.0 - smoothstep(0.70, 0.84, v));
	float water_main = 1.0 - smoothstep(river_w * 0.68, river_w * 1.08, river_d);
	float water_trib = (1.0 - smoothstep(0.007, 0.015, trib_d)) * trib_mask * 0.90;
	float is_water = clamp(max(water_main, water_trib) * (1.0 - smoothstep(0.42, 0.62, border_mtn)), 0.0, 1.0);
	float shore_band = clamp((1.0 - smoothstep(river_w * 0.95, river_w * 1.48, river_d)) * (1.0 - is_water), 0.0, 1.0);

	// Patchwork agricultural valley fields (subtle rotated parcels with hedgerows & emerald forest groves).
	vec2 farm_uv = rot2(vec2(u * 26.0, v * 72.0), 0.26 + sid * 0.45);
	vec2 fcell = floor(farm_uv);
	vec2 ffrac = fract(farm_uv);
	float f_id = hash21(fcell + sid * 17.0);
	float f_id2 = hash21(fcell * 0.5 + vec2(3.1, 7.7) + sid * 9.0);
	float hedge = 1.0 - smoothstep(0.03, 0.09, min(min(ffrac.x, 1.0 - ffrac.x), min(ffrac.y, 1.0 - ffrac.y)));
	float farm_zone = (1.0 - smoothstep(0.22, 0.48, mtn_elev)) * (1.0 - is_water) * smoothstep(0.28, 0.68, n0.g + 0.12);

	vec3 field_col = mix(vec3(0.21, 0.38, 0.17), vec3(0.50, 0.44, 0.22), smoothstep(0.25, 0.78, f_id));
	field_col = mix(field_col, vec3(0.32, 0.44, 0.20), smoothstep(0.55, 0.85, f_id2) * 0.55);
	field_col *= mix(1.0, 0.68, hedge * 0.65);
	vec3 forest_col = mix(vec3(0.06, 0.16, 0.10), vec3(0.13, 0.25, 0.14), n1.r);
	vec3 rock_col = mix(vec3(0.18, 0.20, 0.23), vec3(0.36, 0.34, 0.31), n2.a);
	vec3 snow_col = vec3(0.76, 0.81, 0.88);

	vec3 terrain = mix(forest_col, field_col, farm_zone);
	terrain = mix(terrain, vec3(0.42, 0.38, 0.30), shore_band * 0.38);
	terrain = mix(terrain, rock_col, smoothstep(0.38, 0.70, mtn_elev));
	terrain = mix(terrain, snow_col, smoothstep(0.76, 0.94, mtn_elev + n1.b * 0.12));

	// Directional solar/moon relief lighting.
	vec3 sun_dir_golden = normalize(vec3(0.48, 0.52, -0.70));
	vec3 sun_dir_twilight = normalize(vec3(-0.35, 0.38, -0.85));
	vec3 moon_dir_night = normalize(vec3(0.25, 0.75, -0.60));
	vec3 slope_n = normalize(wnrm + vec3((h_here - h_dx) * 4.8, (h_here - h_dy) * 4.8, 0.0));

	float ndl_n = clamp(dot(slope_n, moon_dir_night) * 0.5 + 0.5, 0.18, 1.0);
	float ndl_g = clamp(dot(slope_n, sun_dir_golden) * 0.65 + 0.35, 0.15, 1.0);
	float ndl_t = clamp(dot(slope_n, sun_dir_twilight) * 0.55 + 0.45, 0.16, 1.0);

	// Rich deep moonlit indigo-emerald valleys at night so city lights glow like real jewels against dark terrain!
	vec3 land_night = terrain * vec3(0.095, 0.155, 0.265) * (0.50 + 0.80 * ndl_n)
			+ vec3(0.008, 0.015, 0.032) * (0.3 + 0.7 * mtn_elev);
	vec3 land_golden = terrain * mix(vec3(0.24, 0.30, 0.42), vec3(1.16, 0.84, 0.50), ndl_g) * 0.94;
	vec3 land_twilight = terrain * mix(vec3(0.13, 0.14, 0.29), vec3(0.88, 0.44, 0.44), ndl_t) * 0.74;
	vec3 land_lit = land_night * w_night + land_golden * w_golden + land_twilight * w_twilight;

	// Silvery-sapphire / champagne-gold / rose-twilight curved river sheen!
	float ndv = clamp(abs(dot(wnrm, view_dir)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, 2.0);
	float river_rip = 0.5 + 0.5 * sin(v * 150.0 + u * 55.0 + clock * 0.42);
	float center_glint = 1.0 - smoothstep(0.0, river_w * 0.85, river_d);
	vec3 water_night = mix(vec3(0.025, 0.065, 0.145), vec3(0.24, 0.42, 0.66), 0.26 + 0.55 * fresnel)
			+ vec3(0.32, 0.46, 0.64) * center_glint * (0.28 + 0.42 * fresnel) * (0.65 + 0.35 * river_rip);
	vec3 water_golden = mix(vec3(0.07, 0.22, 0.32), vec3(0.98, 0.76, 0.40), 0.38 + 0.55 * fresnel)
			+ vec3(1.0, 0.88, 0.58) * center_glint * (0.45 + 0.45 * river_rip) * 0.75;
	vec3 water_twilight = mix(vec3(0.05, 0.09, 0.21), vec3(0.82, 0.44, 0.56), 0.34 + 0.52 * fresnel)
			+ vec3(0.96, 0.62, 0.54) * center_glint * (0.35 + 0.40 * river_rip) * 0.60;
	vec3 water_col = water_night * w_night + water_golden * w_golden + water_twilight * w_twilight;

	// Organic photographic high-altitude night cities: dense blazing riverside downtown cores fading naturally into
	// branching suburban avenues, dark green parkland pockets, and scattered hillside farmhouses (zero uniform waffle!).
	float city_nodes = 0.0;
	float core_nodes = 0.0;
	for (int k = 0; k < 4; k++) {
		float fk = float(k);
		float cv = fract(0.15 + fk * 0.23 + sid * 0.11);
		float side_s = mod(fk + sid, 2.0) < 0.5 ? 1.0 : -1.0;
		float cu = clamp(river_c + side_s * (river_w + 0.07 + 0.04 * sin(fk * 2.9 + sid)), 0.20, 0.80);
		vec2 dvec = vec2((u - cu) * (1.25 + 0.2 * sin(fk)), (v - cv) * 2.65);
		float g = exp(-dot(dvec, dvec) * 28.0);
		city_nodes = max(city_nodes, g);
		core_nodes = max(core_nodes, exp(-dot(dvec, dvec) * 105.0));
	}
	// Organic noise carving parks, dark river bends & natural suburban sprawl fingers!
	float park_cut = smoothstep(0.28, 0.78, n1.r * 0.65 + n2.g * 0.35);
	float sprawl_mask = smoothstep(0.50, 0.82, n0.r * 0.60 + n1.g * 0.40) * (1.0 - smoothstep(0.06, 0.26, river_d));
	float urban = clamp(max(city_nodes * (0.45 + 0.70 * park_cut), sprawl_mask * 0.65), 0.0, 1.0)
			* (1.0 - is_water) * (1.0 - smoothstep(0.28, 0.52, mtn_elev));

	// Two district-rotated fine street networks so neighborhoods feel authentically organic, never a giant grid!
	float dist_ang = 0.24 * sin(sid * 2.1 + floor(v * 5.0) * 1.7) + 0.18 * (n0.g - 0.5);
	vec2 city_p = rot2(vec2(u * 56.0, v * 155.0), dist_ang);
	vec2 grid_id = floor(city_p);
	vec2 grid_f = fract(city_p);
	float block_alive = smoothstep(0.22, 0.72, hash21(grid_id + sid * 19.0) + urban * 0.42);
	float road_x = (1.0 - smoothstep(0.018, 0.062, min(grid_f.x, 1.0 - grid_f.x))) * block_alive;
	float road_y = (1.0 - smoothstep(0.018, 0.062, min(grid_f.y, 1.0 - grid_f.y))) * block_alive;
	float avenues = max(road_x, road_y) * smoothstep(0.24, 0.72, urban);

	// Fine jewel-like sparkling building lights inside dense cores + delicate sparse rural villages across the valley.
	vec2 blk_p = city_p * 3.2;
	vec2 blk_id = floor(blk_p);
	vec2 blk_f = fract(blk_p);
	float bh = hash21(blk_id + sid * 31.0);
	float bh2 = hash21(blk_id * 1.37 + vec2(11.3, 5.7));
	float pin = 1.0 - smoothstep(0.08, 0.34, length(blk_f - 0.5));
	float urban_pins = pin * smoothstep(0.46, 0.88, bh + urban * 0.36) * smoothstep(0.14, 0.62, urban);
	float rural_pins = pin * step(0.955, bh) * (1.0 - is_water) * (1.0 - smoothstep(0.32, 0.56, mtn_elev)) * 0.55;
	float slow_twinkle = 0.88 + 0.12 * sin(clock * 0.85 + bh2 * 6.28318);

	// Thin illuminated transit arteries linking the valley towns + glowing bridges across the silver river!
	float hwy1 = 1.0 - smoothstep(0.0018, 0.0052, abs(u - (river_c + river_w + 0.042)));
	float hwy2 = 1.0 - smoothstep(0.0018, 0.0052, abs(u - (river_c - river_w - 0.042)));
	float hwy_dash = 0.45 + 0.55 * smoothstep(0.2, 0.8, sin(v * 210.0 + sid * 2.0));
	float highways = max(hwy1, hwy2) * (1.0 - is_water) * (1.0 - smoothstep(0.32, 0.52, mtn_elev)) * hwy_dash * 0.42;
	float bridge_line = (1.0 - smoothstep(0.0025, 0.0075, abs(fract(v * 7.0 + sid * 0.33) - 0.5))) * is_water
			* smoothstep(0.22, 0.58, city_nodes);

	// Jewel-toned city illumination: warm sodium-amber streets, bright ivory downtown spires, cyan waterfront lights!
	vec3 ave_col = vec3(1.0, 0.64, 0.24);
	vec3 spire_col = mix(vec3(1.0, 0.78, 0.42), vec3(1.0, 0.94, 0.84), smoothstep(0.55, 0.92, bh2 + core_nodes * 0.35));
	float waterfront = smoothstep(river_w * 2.2, river_w * 0.95, river_d);
	vec3 dot_col = mix(spire_col, vec3(0.46, 0.88, 1.0), waterfront * 0.62 * step(0.48, bh2));
	vec3 city_glow = ave_col * avenues * 0.58
			+ dot_col * (urban_pins * (1.15 + 0.65 * core_nodes) + rural_pins) * slow_twinkle
			+ vec3(1.0, 0.62, 0.22) * core_nodes * (1.0 - is_water) * 0.26
			+ vec3(1.0, 0.74, 0.34) * (highways + bridge_line * 1.15);

	float city_power = w_night * 1.05 + w_golden * 0.05 + w_twilight * 0.68;
	float water_city_refl = is_water * smoothstep(0.18, 0.68, city_nodes) * (0.40 + 0.60 * river_rip) * city_power;

	vec3 col = mix(land_lit, water_col, is_water);
	col += city_glow * city_power;
	col += vec3(0.95, 0.66, 0.30) * water_city_refl * 0.30;

	// Soft cylindrical atmospheric depth haze towards the far ends.
	float dist = length(wpos - cam_pos);
	float haze_f = smoothstep(58.0, 185.0, dist) * 0.24;
	vec3 haze_col = vec3(0.025, 0.045, 0.095) * w_night
			+ vec3(0.58, 0.40, 0.22) * w_golden
			+ vec3(0.24, 0.13, 0.28) * w_twilight;
	col = mix(col, haze_col, clamp(haze_f, 0.0, 0.42));

	// Gentle film screen spill only on nearest lower valley edges.
	float d_scr = distance(wpos, screen_center);
	vec3 spill = spill_strength * screen_glow / (1.0 + 0.0022 * d_scr * d_scr) * spill_tint(wpos) * 0.24;
	return (col + spill) * film_dim;
}

// Structural titanium tension rings, longitudinal space-window edge girders, and radial end-cap spokes.
vec3 shade_structure(vec2 uv, vec3 wpos, vec3 wnrm, vec3 view_dir) {
	vec3 mw = mood_weights / max(mood_weights.x + mood_weights.y + mood_weights.z, 0.001);
	float w_night = mw.x;
	float w_golden = mw.y;
	float w_twilight = mw.z;

	vec3 sun_g = normalize(vec3(0.42, 0.55, -0.72));
	vec3 sun_t = normalize(vec3(-0.30, 0.42, -0.85));
	float ndl_g = clamp(dot(wnrm, sun_g) * 0.5 + 0.5, 0.15, 1.0);
	float ndl_t = clamp(dot(wnrm, sun_t) * 0.5 + 0.5, 0.15, 1.0);
	float rim = pow(1.0 - clamp(abs(dot(wnrm, view_dir)), 0.0, 1.0), 2.5);

	float edge_bevel = smoothstep(0.32, 0.49, abs(uv.x - 0.5));
	vec3 base = v_col.rgb * mix(vec3(0.075, 0.095, 0.135), vec3(0.17, 0.20, 0.26), edge_bevel * 0.7);
	vec3 col_night = base * (0.72 + 0.55 * rim);
	vec3 col_golden = base * mix(vec3(0.42, 0.46, 0.56), vec3(1.50, 1.14, 0.72), ndl_g) * 1.40 + vec3(0.26, 0.18, 0.09) * rim;
	vec3 col_twilight = base * mix(vec3(0.28, 0.28, 0.46), vec3(1.18, 0.70, 0.74), ndl_t) * 1.12 + vec3(0.16, 0.11, 0.20) * rim;
	vec3 col = col_night * w_night + col_golden * w_golden + col_twilight * w_twilight;

	float seg = fract(uv.y * 18.0);
	float beacon = (1.0 - smoothstep(0.0, 0.065, abs(seg - 0.5))) * (1.0 - smoothstep(0.0, 0.16, abs(uv.x - 0.5)));
	float warm_pick = step(0.5, fract(floor(uv.y * 18.0) * 0.5));
	vec3 bcol = mix(vec3(0.42, 0.88, 1.0), vec3(1.0, 0.76, 0.36), warm_pick);
	float b_vis = w_night * 0.92 + w_golden * 0.20 + w_twilight * 0.68;
	col += bcol * beacon * b_vis * 0.82;

	float d_scr = distance(wpos, screen_center);
	col += spill_strength * screen_glow / (1.0 + 0.004 * d_scr * d_scr) * spill_tint(wpos) * 0.18;
	return col * film_dim;
}

// End-cap central axial solar-mirror & docking hub core.
vec3 shade_hub(vec2 uv) {
	vec3 mw = mood_weights / max(mood_weights.x + mood_weights.y + mood_weights.z, 0.001);
	float r = clamp(uv.x, 0.0, 1.0);
	float a = uv.y * 6.283185;
	float ring_inner = 1.0 - smoothstep(0.02, 0.075, abs(r - 0.26));
	float ring_mid = 1.0 - smoothstep(0.018, 0.06, abs(r - 0.58));
	float ring_outer = 1.0 - smoothstep(0.02, 0.065, abs(r - 0.90));
	float vanes = 0.5 + 0.5 * cos(a * 12.0);
	float core_disc = 1.0 - smoothstep(0.0, 0.22, r);

	vec3 night_hub = vec3(0.035, 0.055, 0.10) + vec3(0.42, 0.82, 1.0) * (ring_outer * 0.62 + ring_inner * 0.82)
			+ vec3(1.0, 0.76, 0.38) * ring_mid * 0.72 + vec3(0.75, 0.88, 1.0) * core_disc * 0.52;
	vec3 golden_hub = vec3(0.40, 0.26, 0.12) * (0.7 + 0.3 * vanes)
			+ vec3(1.0, 0.88, 0.62) * (core_disc * 1.15 + ring_inner * 0.95 + ring_mid * 0.72 + ring_outer * 0.48);
	vec3 twilight_hub = vec3(0.16, 0.09, 0.20) * (0.7 + 0.3 * vanes)
			+ vec3(1.0, 0.62, 0.44) * (core_disc * 0.92 + ring_mid * 0.82)
			+ vec3(0.55, 0.82, 1.0) * (ring_inner * 0.68 + ring_outer * 0.58);

	return (night_hub * mw.x + golden_hub * mw.y + twilight_hub * mw.z) * film_dim;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float kind = v_meta.x;
	vec3 col;
	if (kind > 1.5) {
		col = shade_hub(v_uv);
	} else if (kind > 0.75) {
		col = shade_structure(v_uv, world_pos, n, v);
	} else if (kind > 0.18) {
		col = shade_endcap(v_uv, v_meta.y, v_col.a, world_pos, n, v, CAMERA_POSITION_WORLD);
	} else {
		col = shade_land(v_uv, v_meta.y, v_col.a, world_pos, n, v, CAMERA_POSITION_WORLD);
	}
	float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	vec3 s = sqrt(max(col, vec3(0.0))) + dither / 255.0;
	ALBEDO = max(s, vec3(0.0)) * max(s, vec3(0.0));
}
