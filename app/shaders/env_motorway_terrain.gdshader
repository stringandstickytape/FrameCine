shader_type spatial;
render_mode unshaded, cull_back;

// Real GEDTM30 elevation + ESA WorldCover RGB streaming countryside ribbon (left & right of M1).
// Samples compact 64x11 streaming DataTextures updated cleanly as the GT cruises along the 310 km M1.

uniform sampler2D height_tex : filter_linear, repeat_disable; // R = relative height / 150.0 + 0.5, G = chalk_cutting, B = valley_mist, A = urban_glow
uniform sampler2D colour_tex : source_color, filter_linear, repeat_disable; // RGB = real ESA WorldCover 2021 terrain colour!
uniform vec4 curve_prof[32]; // (x_off, y_off, lit_level, lamp_style)
uniform float s_travel = 0.0;
uniform float dir_sign = 1.0;
uniform float wet = 0.0;
uniform float fog_density = 0.0;
uniform float lightning = 0.0;
uniform float day_level = 0.5;
uniform vec3 sky_top = vec3(0.08, 0.14, 0.28);
uniform vec3 sky_low = vec3(0.24, 0.28, 0.34);
uniform vec3 sun_dir = vec3(0.3, 0.6, -0.7);
uniform vec3 sun_col = vec3(1.0, 0.92, 0.78);
uniform vec3 fog_col = vec3(0.20, 0.24, 0.30);

varying vec3 v_world_col;
varying float v_chalk;
varying float v_mist;
varying float v_urban;
varying float v_dist;
varying float v_slope;
varying vec2 v_world_xz;
varying float v_rel_y;

vec4 sample_curve(float z_local) {
	float t = clamp((32.0 - z_local) / 214.0, 0.0, 1.0) * 31.0;
	int i0 = int(floor(t));
	int i1 = min(i0 + 1, 31);
	return mix(curve_prof[i0], curve_prof[i1], fract(t));
}

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	// UV.x = lateral index [0..1] across all 11 DEM offsets; UV.y = longitudinal [0..1] from z=+32 to z=-182
	vec4 hdat = texture(height_tex, UV);
	vec4 cdat = texture(colour_tex, UV);
	float dh = (hdat.r - 0.5) * 180.0;
	// Smoothly taper height down to 0 right at the motorway shoulder edge (keep tarmac flush!)
	float edge_t = smoothstep(0.0, 18.0, abs(VERTEX.x - 6.8) - 16.0);
	float rel_y = dh * edge_t;

	// Estimate cross-slope for subtle ridge & chalk-cutting shading
	vec4 h_l = texture(height_tex, vec2(max(UV.x - 0.08, 0.0), UV.y));
	vec4 h_r = texture(height_tex, vec2(min(UV.x + 0.08, 1.0), UV.y));
	v_slope = clamp((h_r.r - h_l.r) * 14.0, -1.0, 1.0);

	vec4 cp = sample_curve(VERTEX.z);
	VERTEX.x += cp.x;
	VERTEX.y = -0.34 + cp.y + rel_y;

	v_world_col = cdat.rgb;
	v_chalk = hdat.g;
	v_mist = hdat.b;
	v_urban = hdat.a;
	v_dist = length(VERTEX.xz);
	v_world_xz = vec2(VERTEX.x, s_travel + (-VERTEX.z) * dir_sign);
	v_rel_y = rel_y;
}

void fragment() {
	// Start from real ESA WorldCover 2021 terrain RGB + authentic British field/pasture patchwork detail!
	vec2 wp = v_world_xz;
	float field_n = vnoise(wp * 0.014);
	float fine_n = vnoise(wp * 0.12) * 0.6 + vnoise(wp * 0.38) * 0.4;
	// Subtle British hedgerow / field-boundary patchwork variation
	vec2 fcell = floor(wp * 0.011);
	float cell_tint = hash21(fcell) * 0.24 - 0.12;
	vec3 col = v_world_col * (0.92 + cell_tint + (fine_n - 0.5) * 0.22);

	// Iconic Chiltern Chalk Cuttings (steep embankments near J9-J11 expose natural weathered chalk strata!)
	float steep = smoothstep(0.24, 0.62, abs(v_slope)) * smoothstep(3.0, 14.0, v_rel_y);
	float chalk_mask = clamp(v_chalk * steep * 0.95, 0.0, 0.68);
	vec3 chalk_col = vec3(0.38, 0.36, 0.30) * (0.85 + 0.28 * fine_n);
	col = mix(col, chalk_col, chalk_mask);

	// Wet ground slightly richer/darker
	col *= mix(1.0, 0.78, wet);

	// Analytical day/golden/dusk/night lighting with hillside slope shading
	vec3 norm = normalize(vec3(-v_slope * 0.8, 1.0, 0.0));
	float ndl = max(dot(norm, normalize(sun_dir)), 0.0);
	vec3 amb = mix(sky_low, sky_top, 0.45) * (0.26 + 0.74 * day_level) + vec3(0.24, 0.28, 0.40) * lightning * 0.9;
	vec3 lit = col * (amb + sun_col * ndl * (0.35 + 0.75 * day_level));

	// Warm orange-sodium distant town/village ground glow at dusk/night on real OSM urban stretches!
	float night_fac = 1.0 - smoothstep(0.15, 0.65, day_level);
	if (v_urban > 0.05 && night_fac > 0.05) {
		float spark = smoothstep(0.68, 0.92, vnoise(wp * 0.095)) * smoothstep(32.0, 75.0, abs(v_world_xz.x));
		lit += vec3(1.0, 0.64, 0.26) * v_urban * night_fac * (0.08 + 0.55 * spark);
	}

	// Automatic low-DEM river-valley mist (Ouse, Trent, Don valleys!) + overall fog
	float valley_fog = v_mist * smoothstep(14.0, -4.0, v_rel_y) * (0.14 + fog_density * 0.65);
	float fog_k = 1.0 - exp(-v_dist * (0.0044 + fog_density * 0.0175 + valley_fog * 0.012));
	float far_fade = smoothstep(118.0, 174.0, v_dist);
	vec3 mist_col = mix(fog_col, sky_low * 1.08, 0.25);
	ALBEDO = mix(lit, mist_col, clamp(max(fog_k, far_fade), 0.0, 1.0));
}
