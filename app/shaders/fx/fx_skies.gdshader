// The effect library's skies (scripts/effects/catalogue/skies.gd, docs/effects.md): whole skies drawn on the room's
// sky sphere, from the direction alone (room_sky.gdshader's conventions: the sphere centred on the viewer, opaque,
// writing depth like any far wall, unlit, a fixed sub-level dither against banding). Compiled once per sky with
// FX_<NAME> defined. Each draws its own sky: a sky's colour or picture is not under it.
//
// Noise: fx_noise3 on the direction (3D, so no seam anywhere on the sphere) for skies all round; fx_fbm2 on a plane
// overhead for cloud layers (mipmapped, so the far, squashed part near the horizon fades to its average instead of
// shimmering). Stars as room_sky.gdshader's: one candidate per cell of a 3D grid on the direction, at least a pixel
// wide (fwidth), their energy spread when smaller.
//
// Photosensitivity: stars twinkle each at its own rate under 1.2 Hz by at most the twinkle (<= FX_MAX_SWING);
// everything else drifts or changes shape slowly enough that no pixel changes faster than a 3 Hz wave of the full
// swing (docs/effects.md). Nothing rotates the whole sky: a star moving across pixels would blink in each.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

#include "res://shaders/fx/fx_common.gdshaderinc"

// The sky's top and its horizon (every sky), and the sun's place for a sunset (degrees: above the horizon, and
// round from straight ahead to the right).
uniform vec3 sky_zenith : source_color = vec3(0.01, 0.015, 0.04);
uniform vec3 sky_horizon : source_color = vec3(0.03, 0.05, 0.09);
uniform float sun_height = 3.0;
uniform float sun_azimuth = 0.0;
// Stars (0 none .. 1 a clear night far from towns) and how far each one's brightness wanders (<= FX_MAX_SWING).
uniform float star_density = 0.5;
uniform float twinkle = 0.2;

varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

// The sky's own gradient: the horizon colour low down, the zenith's overhead, a darker band below the horizon.
vec3 sky_gradient(vec3 d) {
	vec3 up = mix(sky_horizon, sky_zenith, pow(smoothstep(-0.02, 0.85, d.y), 0.7));
	return mix(up, sky_horizon * 0.35, smoothstep(0.0, -0.35, d.y));
}

// A star field: one candidate star per cell of a grid `cells` across, kept by density, placed off the cell's
// corners, few of them bright, each a little warm or cool. px: the grid's size of a pixel (from fwidth outside any
// branch). Twinkle: each star its own rate, 0.15..1.2 Hz.
vec3 sky_stars(vec3 d, float cells, float density, float px, float t) {
	vec3 g = d * cells;
	vec3 cell = floor(g);
	if (fx_hash(cell + 11.0) >= density * 0.35) {
		return vec3(0.0);
	}
	vec3 at = cell + 0.2 + 0.6 * vec3(fx_hash(cell + 1.7), fx_hash(cell + 3.1), fx_hash(cell + 5.3));
	at = normalize(at) * cells;
	float dist = length(g - at);
	float core = 0.07;
	float r = max(core, px * 0.9);
	float bright = (pow(fx_hash(cell + 7.9), 3.0) * 1.6 + 0.12) * (core * core) / (r * r);
	float rate = 0.15 + 1.05 * fx_hash(cell + 9.4);
	float tw = fx_swing(sin(FX_TAU * (rate * t + fx_hash(cell + 13.2))), twinkle);
	vec3 tint = mix(vec3(0.8, 0.88, 1.0), vec3(1.0, 0.9, 0.75), fx_hash(cell + 15.8));
	return tint * bright * tw * exp(-dist * dist / (r * r)) * smoothstep(-0.02, 0.1, d.y);
}

// A cloud layer on a plane overhead: its density (0..1) at the plane point p, cover 0..1.
float sky_cloud(vec2 p, float cover) {
	vec4 a = fx_fbm2(p);
	vec4 b = fx_fbm2(p * 2.3 + a.rg * 0.18);
	float n = a.r * 0.68 + b.g * 0.32;
	float c = clamp(cover, 0.0, 1.0);
	return smoothstep(1.0 - c - 0.1, 1.0 - c + 0.3, n);
}

void fragment() {
	vec3 d = normalize(dir);
	float t = FX_TIME;
	vec3 col = sky_gradient(d);
	float px128 = max(length(fwidth(d * 128.0)), 1e-4);
#if defined(FX_SKY_AURORA)
	// Curtains of light round the sky: a lower edge that waves along the azimuth, rays rising from it and fading
	// upwards, green low and violet high, two layers sliding past each other slowly.
	float az = atan(d.x, -d.z) / FX_TAU;
	float el = asin(clamp(d.y, -1.0, 1.0));
	float v = 0.002 * fx_speed01();
	vec3 light = vec3(0.0);
	for (int i = 0; i < 2; i++) {
		float k = float(i);
		// Without mipmaps: the azimuth jumps where it wraps, and its derivative with it.
		vec4 fold = textureLod(fx_fbm, vec2(az * (2.0 + k) + t * v * (1.0 - 1.8 * k) + fx_seed, 0.37 * k), 0.0);
		float edge = 0.14 + 0.2 * fold.r + 0.06 * k;
		float above = el - edge;
		// A soft lower edge (it moves as the curtain waves), a long fade upwards, some stretches dark.
		float body = smoothstep(-0.04, 0.05, above) * exp(-max(above, 0.0) * mix(7.0, 4.0, fold.g))
				* (1.0 + 0.6 * exp(-abs(above - 0.03) * 25.0));
		body *= 0.15 + 0.85 * smoothstep(0.3, 0.7, fold.g);
		vec2 ray_at = vec2(az * (11.0 + 4.0 * k) + fold.g * 0.4 + t * v * 2.0, el * 0.25 + k);
		float rays = mix(0.45, 1.0, smoothstep(0.25, 0.85, textureLod(fx_fbm, ray_at, 0.0).g));
		vec3 hue = mix(fx_color, fx_color2, smoothstep(0.0, 0.35, above));
		light += hue * body * rays * (0.75 - 0.25 * k);
	}
	col += light * fx_strength * smoothstep(0.02, 0.15, d.y) * (1.0 - smoothstep(0.75, 1.1, el));
	col += sky_stars(d, 128.0, star_density, px128, t) * (1.0 - clamp(dot(light, vec3(0.6)), 0.0, 1.0));
#elif defined(FX_SKY_STARFIELD)
	// A clear night: a faint band of the galaxy across the sky with dark dust in it, more stars along it.
	// The band: the great circle round this axis, rising from the horizon ahead-left across to the right.
	vec3 axis = normalize(vec3(0.8, 0.5, 0.27));
	float off = dot(d, axis);
	vec2 dust = fx_noise3x2(d * 7.0 * fx_scale + fx_seed * 7.0);
	float clump = fx_noise3(d * 19.0 * fx_scale + vec3(dust, 0.0));
	// Its width wanders; a dark rift of dust runs along its middle, broken up.
	off += (dust.x - 0.5) * 0.06;
	float band = exp(-off * off / (0.02 + 0.02 * dust.y));
	float rift = exp(-pow(off - 0.02, 2.0) / 0.0015) * smoothstep(0.35, 0.65, clump);
	float glow = band * (0.4 + 0.6 * dust.x + 0.5 * clump) * (1.0 - 0.7 * rift);
	col += fx_color * glow * 0.08 * fx_strength * smoothstep(-0.02, 0.15, d.y);
	col += sky_stars(d, 128.0, clamp(star_density * (0.7 + 0.8 * band), 0.0, 1.0), px128, t);
	col += sky_stars(d, 64.0, star_density * 0.35, max(length(fwidth(d * 64.0)), 1e-4), t + 17.0) * 1.3;
#elif defined(FX_SKY_NEBULA)
	// Deep space all round: clouds of glowing gas in two colours with darker dust, changing shape very slowly, and
	// stars. No horizon: it is space.
	// Four taps of 3D noise: a warp, the clouds' body, their fine structure, and thin bright filaments where the
	// fine noise crosses its middle (ridges), only inside the clouds.
	col = sky_zenith;
	vec3 q = d * 1.6 / max(fx_scale, 0.2) + vec3(fx_seed * 9.0, 0.0, t * 0.006 * fx_speed01());
	vec2 w = fx_noise3x2(q);
	vec2 n = fx_noise3x2(q * 2.1 + vec3(w * 1.6, 0.0));
	vec2 fine = fx_noise3x2(q * 4.7 + vec3(n * 0.9, 1.3));
	float density = n.x * 0.62 + fine.x * 0.28 + w.x * 0.1;
	float gas = smoothstep(0.42, 0.9, density) * smoothstep(0.2, 0.6, w.x);
	float ridge = pow(1.0 - abs(fine.y * 2.0 - 1.0), 3.0) * smoothstep(0.5, 0.75, density) * 0.4;
	vec3 hue = mix(fx_color, fx_color2, smoothstep(0.3, 0.7, n.y + (fine.x - 0.5) * 0.4));
	float dark = smoothstep(0.5, 0.75, w.y) * smoothstep(0.3, 0.6, fine.x) * 0.85;
	vec3 gas_col = hue * (gas * gas * 0.8 + ridge * 0.35) + mix(hue, vec3(1.0), 0.5) * pow(gas, 4.0) * 0.25;
	col += gas_col * fx_strength * (1.0 - dark);
	col += hue * 0.01 * fx_strength * w.x;
	col += sky_stars(d, 128.0, star_density, px128, t) * (1.0 - 0.7 * dark);
#elif defined(FX_SKY_SUNSET)
	// The sun on the horizon: a warm glow round it, the sky deepening overhead, thin streaks of cloud lit from
	// below, drifting slowly.
	float h = radians(clamp(sun_height, -6.0, 20.0));
	float a = radians(sun_azimuth);
	vec3 sun = vec3(sin(a) * cos(h), sin(h), -cos(a) * cos(h));
	float c = dot(d, sun);
	float low = 1.0 - smoothstep(-0.05, 0.55, d.y);
	col += fx_color * (exp(-(1.0 - c) * 6.0) * 0.55 + exp(-(1.0 - c) * 60.0) * 0.4) * low;
	float aa = max(fwidth(c), 1e-5);
	float disc = smoothstep(cos(radians(0.7)) - aa, cos(radians(0.7)) + aa, c) * smoothstep(-0.01, 0.01, d.y);
	col = mix(col, vec3(1.0, 0.92, 0.75), disc * 0.95);
	vec2 p = d.xz / max(d.y + 0.08, 0.02) * vec2(0.35, 1.4) + vec2(t * 0.004 * fx_speed01(), 0.0) + fx_seed;
	float streak = smoothstep(0.55, 0.85, fx_fbm2(p * 0.6).r) * smoothstep(0.0, 0.12, d.y)
			* clamp(fx_param, 0.0, 1.0) * 1.5;
	vec3 under = mix(fx_color2, fx_color * 1.2, exp(-(1.0 - c) * 3.0));
	col = mix(col, under, clamp(streak, 0.0, 0.85));
#elif defined(FX_SKY_CLOUDS)
	// Two layers of cloud overhead, the high one thin and slow, the low one fuller, each drifting with the wind
	// and lit a little brighter on its sunward side; thinning softly to the horizon.
	float up = d.y;
	vec2 plane = d.xz / max(up + 0.12, 0.02);
	float v = 0.006 * fx_speed01();
	vec2 hi = plane * 0.35 / max(fx_scale, 0.2) + vec2(t * v * 0.6, t * v * 0.2) + fx_seed;
	float high = sky_cloud(hi, fx_param * 0.7) * 0.55;
	vec2 lo = plane * 0.6 / max(fx_scale, 0.2) + vec2(t * v, t * v * 0.35) + 0.5;
	float low = sky_cloud(lo, fx_param);
	float lit = sky_cloud(lo + vec2(-0.02, 0.012), fx_param);
	float fade = smoothstep(0.0, 0.25, up);
	vec3 shade = mix(fx_color * 0.62, fx_color, clamp(0.6 + (low - lit) * 2.5, 0.0, 1.0));
	col = mix(col, fx_color * 0.95, high * fade);
	col = mix(col, shade, low * fade * 0.95);
#endif
	ALBEDO = max(col + fx_dither(FRAGCOORD.xy), vec3(0.0));
}
