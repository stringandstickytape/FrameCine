// Cloud temple sky-sea & distant floating sky-island ruins shader (scripts/env/systems/kit/cloud_temple.gd).
// Opaque and unshaded (zero blend overdraw, 1 draw per mesh):
//   UV2.x < 0.5  Endless 360-degree billowing cloud sea (layered domain-warped FBM cumulus tops with sunward
//                directional self-shadowing, warm apricot/gold rim light toward glow_dir, velvet indigo-violet
//                leeward valleys, glacial drift scaled by clock, seamless horizon merge into the sky dome, and
//                smooth transition from golden sunset to silver-blue starlight as dusk advances).
//   UV2.x >= 0.5 Distant floating white-marble sky-island arches & obelisks bathed in sunward golden rim light,
//                warm cloud-sea bounce from below, starlight silver fill at night, and atmospheric haze.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled, fog_disabled;

#include "res://shaders/env_spill.gdshaderinc"

uniform sampler2D noise_map : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float clock = 0.0;
uniform float dusk = 0.18;
uniform float afterglow = 0.9;
uniform float sea_radius = 185.0;
uniform vec3 glow_dir = vec3(0.74, 0.0, -0.67);
uniform vec3 glow_colour : source_color = vec3(1.0, 0.60, 0.29);
uniform vec3 twilight_zenith : source_color = vec3(0.14, 0.22, 0.48);
uniform vec3 twilight_horizon : source_color = vec3(0.92, 0.52, 0.31);
uniform vec3 belt_colour : source_color = vec3(0.68, 0.36, 0.46);
uniform vec3 night_zenith : source_color = vec3(0.015, 0.022, 0.055);
uniform vec3 night_horizon : source_color = vec3(0.055, 0.075, 0.14);

varying vec3 world_pos;
varying vec3 world_normal;
varying float r_norm;
varying float kind;

float cloud_height(vec2 p, vec2 drift) {
	vec2 warp = (texture(noise_map, p * 0.0065 + drift * 0.40).rg - 0.5) * 16.5;
	float c1 = texture(noise_map, (p + warp) * 0.0095 + drift * 0.65).r;
	float c2 = texture(noise_map, (p - warp * 0.48) * 0.024 + drift * 1.08 + vec2(0.37, 0.19)).g;
	float c3 = texture(noise_map, (p + warp * 0.22) * 0.056 + drift * 1.48 + vec2(0.11, 0.63)).b;
	float c4 = texture(noise_map, p * 0.115 + drift * 1.92 + vec2(0.53, 0.29)).a;
	float puffs = c1 * 0.48 + c2 * 0.30 + c3 * 0.14 + c4 * 0.08;
	float h = smoothstep(0.14, 0.84, puffs);
	return mix(h, sqrt(h), 0.42);
}

// Exact match to env_sky_common.gdshaderinc sky_base() at the horizon (d.y = 0) so the cloud sea merges seamlessly
// into the sky dome at every compass bearing and dusk level.
vec3 sky_horizon_colour(vec2 horiz) {
	float g = dot(horiz, normalize(glow_dir.xz + vec2(1e-5)));
	vec3 h0 = mix(mix(twilight_zenith, twilight_horizon, 0.4) * 0.7, twilight_horizon, smoothstep(-1.0, 1.0, g));
	float anti = smoothstep(-0.1, -0.85, g);
	vec3 rich = mix(h0, twilight_zenith * 0.55 + h0 * 0.12, anti * 0.75);
	vec3 tw = mix(h0, rich, afterglow);
	tw += glow_colour * pow(max(g, 0.0), 6.0) * 0.9;
	return mix(tw, night_horizon, smoothstep(0.0, 1.0, dusk));
}

void vertex() {
	kind = UV2.x;
	vec3 pos = VERTEX;
	r_norm = clamp(length(pos.xz) / max(sea_radius, 1.0), 0.0, 1.0);
	if (kind < 0.5) {
		vec2 drift = vec2(0.0026, 0.0014) * clock;
		float macro = textureLod(noise_map, pos.xz * 0.009 + drift * 0.65, 1.0).r;
		float mid = textureLod(noise_map, pos.xz * 0.022 + drift * 1.05 + vec2(0.23, 0.41), 1.0).g;
		float wave = (macro * 0.65 + mid * 0.35 - 0.5) * 3.6;
		pos.y += wave * (1.0 - smoothstep(0.38, 0.88, r_norm));
	}
	world_pos = (MODEL_MATRIX * vec4(pos, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	VERTEX = pos;
}

void fragment() {
	vec3 to_p = world_pos - CAMERA_POSITION_WORLD;
	float dist = length(to_p);
	vec2 horiz = normalize(to_p.xz + vec2(1e-5));
	vec2 gdir = normalize(glow_dir.xz + vec2(1e-5));
	float sun_align = dot(horiz, gdir);
	vec3 sky_h = sky_horizon_colour(horiz);
	float dk = smoothstep(0.06, 0.96, dusk);
	vec3 col;

	if (kind < 0.5) {
		vec2 drift = vec2(0.0026, 0.0014) * clock;
		vec2 p = world_pos.xz;
		float h = cloud_height(p, drift);
		float h_sun = cloud_height(p + gdir * 4.8, drift);
		float sun_lit = clamp((h - h_sun) * 3.4 + 0.46, 0.0, 1.0);
		float crest = smoothstep(0.38, 0.92, h);
		float detail = texture(noise_map, p * 0.088 + drift * 1.85).a;

		// Golden-rose sunset cloud sea palette (linear light).
		vec3 sunset_valley = mix(vec3(0.055, 0.042, 0.125), vec3(0.11, 0.065, 0.145), smoothstep(-0.6, 0.8, sun_align));
		vec3 sunset_mid = mix(vec3(0.34, 0.15, 0.24), vec3(0.68, 0.28, 0.22), smoothstep(-0.5, 0.85, sun_align));
		vec3 sunset_crest = mix(vec3(0.76, 0.40, 0.34), vec3(1.18, 0.62, 0.24), smoothstep(-0.3, 0.9, sun_align));
		vec3 sunset_rim = glow_colour * (1.25 + 0.55 * pow(max(sun_align, 0.0), 3.0));

		vec3 day_col = mix(sunset_valley, sunset_mid, smoothstep(0.10, 0.62, h));
		day_col = mix(day_col, sunset_crest, crest * (0.45 + 0.55 * sun_lit));
		float rim_k = pow(crest, 1.5) * smoothstep(0.42, 0.95, sun_lit) * (0.32 + 0.68 * smoothstep(-0.35, 0.95, sun_align));
		day_col += sunset_rim * rim_k * (0.42 + 0.22 * detail);
		// Subtle warm golden glow on wispy leeward tops from the Belt of Venus.
		day_col += belt_colour * crest * (1.0 - smoothstep(-0.2, 0.5, sun_align)) * 0.14;

		// Starlight & moonlight cloud sea palette (linear light).
		vec3 night_valley = vec3(0.008, 0.013, 0.034);
		vec3 night_mid = vec3(0.028, 0.044, 0.092);
		vec3 night_crest = vec3(0.095, 0.135, 0.235);
		vec3 star_col = mix(night_valley, night_mid, smoothstep(0.12, 0.65, h));
		star_col = mix(star_col, night_crest, crest * (0.48 + 0.52 * sun_lit));
		star_col += vec3(0.16, 0.21, 0.34) * pow(crest, 2.0) * (0.28 + 0.24 * detail);
		// Gentle lingering amber ember kiss at the western horizon under late dusk.
		star_col += glow_colour * crest * pow(max(sun_align, 0.0), 4.0) * (1.0 - smoothstep(0.75, 1.0, dusk)) * 0.22;

		col = mix(day_col, star_col, dk);

		// Subtle whisper of the cinema screen's colour on the nearest cloud billows below the sanctuary.
		float sd = distance(world_pos, screen_center);
		vec3 film = 0.16 * screen_glow / (1.0 + 0.006 * sd * sd) * spill_tint(world_pos);
		col += film * (0.35 + 0.65 * crest);

		// Seamless horizon merge into the sky dome.
		float fog_k = pow(smoothstep(0.24, 0.98, r_norm), 1.35);
		col = mix(col, sky_h, fog_k);
	} else {
		// Distant floating marble sky-island ruin arches, columns and obelisks.
		vec3 n = normalize(world_normal);
		vec3 sun_d = normalize(vec3(gdir.x, 0.22, gdir.y));
		float ndl = max(dot(n, sun_d), 0.0);
		float up = clamp(n.y * 0.5 + 0.5, 0.0, 1.0);
		float under = clamp(-n.y, 0.0, 1.0);
		vec3 albedo = COLOR.rgb;
		float ao = COLOR.a;

		vec3 sun_key = mix(glow_colour * 1.45 + vec3(0.45, 0.28, 0.14), vec3(0.08, 0.11, 0.20), dk);
		vec3 sky_fill = mix(twilight_zenith * 0.55 + vec3(0.14, 0.10, 0.18), night_zenith * 1.6 + vec3(0.04, 0.06, 0.12), dk);
		vec3 cloud_bounce = mix(vec3(0.58, 0.26, 0.15), vec3(0.045, 0.065, 0.12), dk);

		vec3 lit = albedo * (sky_fill * (0.48 + 0.62 * up) + sun_key * pow(ndl, 0.90) + cloud_bounce * under * 0.78) * ao;
		// Atmospheric perspective softens distant marble into the horizon glow, and cloud-sea mist wraps the crag base.
		float fog_k = clamp(smoothstep(24.0, 138.0, dist) * 0.80, 0.0, 0.86);
		float base_mist = 1.0 - smoothstep(-13.2, -4.2, world_pos.y);
		vec3 mist_col = mix(sky_h, mix(glow_colour * 0.72 + belt_colour * 0.35, night_horizon * 1.35, dk), 0.45);
		col = mix(lit, sky_h, fog_k);
		col = mix(col, mist_col, clamp(base_mist * 0.88, 0.0, 0.92));
	}

	// Half-LSB dither prevents 8-bit colour banding across smooth twilight and starlight horizons.
	float dither = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	vec3 s = sqrt(max(col, vec3(0.0))) + dither / 255.0;
	ALBEDO = max(s, vec3(0.0)) * max(s, vec3(0.0));
}
