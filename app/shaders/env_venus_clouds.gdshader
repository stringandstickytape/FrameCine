// 360-degree opaque Venusian golden-amber cloud canyon sphere (52 km altitude, scripts/env/systems/kit/venus_aerostat.gd).
// Drawn on an inward-facing sphere at r = 160 m: 1 draw, zero alpha-blend cost, zero live lights.
// Layers: luminous hazy golden-ivory upper zenith with diffused Venusian solar bloom, high drifting cirrus streaks,
// towering sunlit saffron & ochre cloud-canyon cathedral walls around the horizon, swirling burnt-sienna lower cloud
// strata beneath the gondola, and very slow soft distant lower-deck sheet lightning (< 0.25 Hz cosine bloom, 0 when
// lightning is off or Flickering lights is off).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, specular_disabled, fog_disabled;

// Seamless 4-channel tileable noise texture (sky.gd noise_texture()).
uniform sampler2D noise_map : filter_linear_mipmap, repeat_enable;
// Slow cloud-canyon drift clock (seconds * motion_scale; Motion = 0 freezes cleanly).
uniform float clock = 0.0;
// Live mood palette (Amber noon / Copper sunset / Stormy gold), linear RGB set via source_color.
uniform vec3 zenith_col : source_color = vec3(0.95, 0.87, 0.67);
uniform vec3 horizon_col : source_color = vec3(0.92, 0.67, 0.34);
uniform vec3 cloud_crest_col : source_color = vec3(1.0, 0.84, 0.52);
uniform vec3 canyon_mid_col : source_color = vec3(0.76, 0.43, 0.16);
uniform vec3 canyon_deep_col : source_color = vec3(0.34, 0.14, 0.06);
uniform vec3 sun_glow_col : source_color = vec3(1.0, 0.93, 0.74);
uniform vec3 sun_dir = vec3(0.64, 0.42, -0.64);
// Overall exterior radiance (1.0 pre-show, softly mellowed during film playback).
uniform float exterior_level = 1.0;
// Slow distant sheet lightning glow strength (0 when off or Flickering lights off; strictly < 0.25 Hz).
uniform float lightning_level = 0.0;
// Separate lightning phase clock (held frozen when Flickering lights is off).
uniform float lightning_clock = 0.0;
uniform vec3 lightning_col : source_color = vec3(1.0, 0.88, 0.68);

const float PI_V = 3.14159265;
const float TAU_V = 6.28318530;

varying vec3 local_dir;

void vertex() {
	local_dir = normalize(VERTEX);
}

// Smooth seamless cylindrical FBM over azimuth u (0..1) and elevation v.
float cloud_fbm(vec2 uv) {
	vec4 a = texture(noise_map, uv);
	vec4 b = texture(noise_map, uv * 2.13 + vec2(0.37, 0.19));
	return a.r * 0.48 + a.g * 0.27 + b.r * 0.16 + b.b * 0.09;
}

void fragment() {
	vec3 d = normalize(local_dir);
	vec3 sdir = normalize(sun_dir);
	float y = d.y;
	float az = atan(d.x, -d.z);
	float u = az / TAU_V + 0.5;
	float sun_dot = max(dot(d, sdir), 0.0);
	float sun_az = max(dot(normalize(vec3(d.x, 0.0, d.z) + vec3(1e-5)), normalize(vec3(sdir.x, 0.0, sdir.z))), 0.0);

	// 1. Upper Venusian atmospheric dome: glowing hazy golden-ivory zenith warming to rich sunlit amber at the horizon.
	float up_t = pow(clamp(y, 0.0, 1.0), 0.50);
	vec3 sky = mix(horizon_col, zenith_col, up_t);
	// Broad diffused Venusian solar radiance filtered through upper cloud haze.
	float solar_core = pow(sun_dot, 5.5) * 0.42 + pow(sun_dot, 1.8) * 0.20;
	sky += sun_glow_col * solar_core * smoothstep(-0.18, 0.35, y);

	// High-altitude sunlit wispy cirrus bands curving overhead around the buoyant gas envelope.
	if (y > -0.05) {
		vec2 sky_uv = d.xz / (max(y, 0.0) + 0.24) * 0.22;
		float w1 = texture(noise_map, sky_uv + vec2(clock * 0.0045, clock * 0.0018)).r;
		float w2 = texture(noise_map, sky_uv * 2.4 - vec2(clock * 0.0032, -clock * 0.0024)).g;
		float wisp = smoothstep(0.30, 0.82, w1 * 0.65 + w2 * 0.35) * smoothstep(-0.04, 0.20, y) * (1.0 - smoothstep(0.62, 1.0, y) * 0.42);
		vec3 wisp_col = mix(cloud_crest_col, sun_glow_col, 0.45 + 0.35 * sun_dot);
		sky = mix(sky, wisp_col, wisp * 0.42);
	}

	// 2. Sculpted towering cloud-canyon cathedral walls wrapping 360 degrees around the horizon.
	// Layer A: towering sunlit anvil & cumulus cathedral cliffs rising up to +0.34 elevation in sculpted banks!
	float drift_far = clock * 0.0032;
	float h_far = cloud_fbm(vec2(u * 3.0 + drift_far, 0.28));
	float h_far_peak = pow(cloud_fbm(vec2(u * 2.0 + drift_far * 0.7, 0.52)), 1.35);
	float h_far_fine = texture(noise_map, vec2(u * 9.0 + drift_far * 1.4, y * 1.8 + 0.41)).g;
	float ridge_far = -0.04 + h_far * 0.26 + h_far_peak * 0.16 + (h_far_fine - 0.5) * 0.075;
	float mask_far = 1.0 - smoothstep(ridge_far - 0.036, ridge_far + 0.026, y);
	// Sunlit cream-gold crest rim fading smoothly down into rich ochre & copper cloud body.
	float crest_far = smoothstep(ridge_far - 0.15, ridge_far + 0.01, y);
	float puff_far = cloud_fbm(vec2(u * 5.0 + drift_far * 1.1, y * 2.6 + 0.15));
	vec3 col_far = mix(canyon_mid_col * 0.96, cloud_crest_col, clamp(crest_far * 0.80 + puff_far * 0.32, 0.0, 1.0));
	col_far += sun_glow_col * (0.30 * pow(sun_az, 2.2) * crest_far);
	col_far = mix(col_far, horizon_col * 1.02, 0.18);

	vec3 c = mix(sky, col_far, mask_far);

	// Layer B: mid-distance dramatic golden-amber & burnt-sienna cloud canyon walls (-0.28 .. +0.18).
	float drift_mid = clock * 0.0058;
	float h_mid = cloud_fbm(vec2(u * 4.0 - drift_mid, 0.64));
	float h_mid_billow = texture(noise_map, vec2(u * 12.0 - drift_mid * 1.5, y * 2.8 + 0.73)).r;
	float ridge_mid = -0.14 + h_mid * 0.28 + (h_mid_billow - 0.5) * 0.085;
	float mask_mid = 1.0 - smoothstep(ridge_mid - 0.030, ridge_mid + 0.022, y);
	float crest_mid = smoothstep(ridge_mid - 0.13, ridge_mid + 0.006, y);
	// Horizontal wind-carved sulfuric cloud striations & dramatic canyon shadow folds.
	float strata_mid = texture(noise_map, vec2(u * 6.0 - drift_mid * 1.3, y * 7.2 + h_mid * 0.38)).b;
	float fold_shadow = smoothstep(0.20, 0.80, h_mid_billow * 0.55 + strata_mid * 0.45);
	float shade_mid = clamp(0.28 + 0.45 * sun_az + 0.34 * fold_shadow, 0.0, 1.0);
	vec3 col_mid = mix(canyon_deep_col * 1.15, canyon_mid_col * 1.16, shade_mid);
	col_mid = mix(col_mid, cloud_crest_col * 0.98, crest_mid * (0.48 + 0.44 * sun_az));
	// Glowing sunlit golden rim catching the canyon wall summits.
	float rim_mid = smoothstep(ridge_mid - 0.048, ridge_mid - 0.005, y) * mask_mid;
	col_mid += sun_glow_col * rim_mid * (0.24 + 0.30 * sun_az);

	c = mix(c, col_mid, mask_mid * 0.95);

	// 3. Deep churning lower-deck cloud canyon floor & warm atmospheric mist troughs (y < -0.06).
	float lower_mask = smoothstep(-0.04, -0.24, y);
	if (lower_mask > 0.001) {
		vec2 low_uv = d.xz / (max(-y, 0.08) + 0.32) * 0.28;
		float swirl_a = cloud_fbm(low_uv + vec2(clock * 0.0052, -clock * 0.0026));
		float swirl_b = texture(noise_map, low_uv * 2.3 + vec2(swirl_a * 0.25 - clock * 0.004, clock * 0.003)).g;
		float canyon_chasm = smoothstep(0.22, 0.80, swirl_a * 0.62 + swirl_b * 0.38);
		float depth_fade = smoothstep(-0.14, -0.82, y);
		vec3 floor_col = mix(canyon_deep_col * 0.68, canyon_mid_col * 0.98, canyon_chasm);
		floor_col = mix(floor_col, cloud_crest_col * 0.86, smoothstep(0.68, 0.92, canyon_chasm) * (1.0 - depth_fade * 0.55));
		floor_col = mix(floor_col, canyon_deep_col * 0.50, depth_fade * 0.64);
		c = mix(c, floor_col, lower_mask);
	}

	// 4. Soft luminous golden horizon mist band tying upper sky and canyon walls together.
	float mist_band = exp(-pow((y + 0.02) / 0.10, 2.0));
	c = mix(c, mix(horizon_col, sun_glow_col, 0.32 * sun_az), mist_band * 0.22);

	// 5. Very slow, soft distant lower-deck sheet lightning bloom (strictly < 0.25 Hz cosine swells!).
	if (lightning_level > 0.001 && y < 0.06 && y > -0.62) {
		float cell_band = smoothstep(-0.56, -0.22, y) * (1.0 - smoothstep(-0.08, 0.05, y));
		float p1 = exp(-pow(sin((az - 1.05) * 0.5), 2.0) * 9.0);
		float p2 = exp(-pow(sin((az + 1.85) * 0.5), 2.0) * 10.0);
		float wave1 = pow(0.5 + 0.5 * cos(TAU_V * 0.11 * lightning_clock + 0.4), 5.0);
		float wave2 = pow(0.5 + 0.5 * cos(TAU_V * 0.16 * lightning_clock + 2.7), 6.0);
		float cloud_mod = texture(noise_map, vec2(u * 4.0 + clock * 0.002, y * 3.0 + 0.5)).b;
		float bloom = (p1 * wave1 + p2 * wave2) * cell_band * (0.45 + 0.55 * cloud_mod);
		c += lightning_col * bloom * lightning_level * 0.62;
	}

	c *= exterior_level;

	// Subtle 8-bit dither to prevent banding across the smooth golden-ivory Venusian sky dome.
	float h = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	vec3 s = sqrt(max(c, vec3(0.0))) + h / 255.0;
	ALBEDO = max(s, vec3(0.0)) * max(s, vec3(0.0));
}
