shader_type spatial;
render_mode unshaded, cull_back;

// Curved 6-lane British motorway ribbon (M1 Grand Tour):
//   x in [-10.0, +23.8] m (hard shoulder -8.6..-5.4, Lanes 1/2/3 at -3.6/0.0/+3.6,
//   central reservation +5.4..+9.2, oncoming carriageway +9.2..+20.0, far shoulder +20.0..+23.2).
//   z in [-182, +32] m; UV.x = local x (metres), UV.y = local z (metres).

uniform vec4 curve_prof[32]; // (x_off, y_off, lit_level, lamp_style: 1=SOX, 2=SON)
uniform float s_travel = 0.0;
uniform float dir_sign = 1.0;
uniform float wet = 0.0;
uniform float fog_density = 0.0;
uniform float headlight_level = 0.0;
uniform float lightning = 0.0;
uniform float time_sec = 0.0;
uniform vec3 sky_top = vec3(0.08, 0.14, 0.28);
uniform vec3 sky_low = vec3(0.24, 0.28, 0.34);
uniform vec3 sun_dir = vec3(0.3, 0.6, -0.7);
uniform vec3 sun_col = vec3(1.0, 0.92, 0.78);
uniform float day_level = 0.5;
uniform vec3 fog_col = vec3(0.20, 0.24, 0.30);

varying float v_x;
varying float v_z;
varying float v_lit;
varying float v_lamp_style;
varying float v_dist;

vec4 sample_curve(float z_local) {
	float t = clamp((32.0 - z_local) / 214.0, 0.0, 1.0) * 31.0;
	int i0 = int(floor(t));
	int i1 = min(i0 + 1, 31);
	return mix(curve_prof[i0], curve_prof[i1], fract(t));
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	float x_local = VERTEX.x;
	float z_local = VERTEX.z;
	vec4 cp = sample_curve(z_local);
	VERTEX.x += cp.x;
	VERTEX.y += cp.y;
	v_x = x_local;
	v_z = z_local;
	v_lit = cp.z;
	v_lamp_style = cp.w;
	v_dist = length(VERTEX.xz);
}

void fragment() {
	float s_world = s_travel + (-v_z) * dir_sign;
	float s_abs = abs(s_world);

	// Fine motorway tarmac aggregate + twin wheel-track polishing per lane
	vec2 gp = vec2(v_x * 3.8, s_world * 0.45);
	float grain = hash21(floor(gp * 6.0)) * 0.08 + hash21(floor(gp * 2.0)) * 0.05;
	float is_median = step(5.45, v_x) * step(v_x, 9.15);
	float is_verge = step(v_x, -8.55) + step(23.15, v_x);

	vec3 tarmac = vec3(0.032, 0.035, 0.039) + vec3(grain * 0.14);
	// Darker wheel tracks in all 6 running lanes
	float lane_dist = min(
		min(abs(v_x + 3.6), abs(v_x)),
		min(abs(v_x - 3.6), min(abs(v_x - 11.0), min(abs(v_x - 14.6), abs(v_x - 18.2))))
	);
	float tyre_track = smoothstep(1.15, 0.55, abs(lane_dist - 0.72));
	tarmac *= mix(1.0, 0.80, tyre_track * (1.0 - is_median));
	// Slightly redder/coarser UK hard shoulder & central reservation gravel/tarmac
	if (v_x < -5.45 || v_x > 20.05) {
		tarmac = mix(tarmac, vec3(0.048, 0.044, 0.042), 0.45);
	}
	if (is_median > 0.5) {
		tarmac = vec3(0.028, 0.036, 0.022) + vec3(grain * 0.12);
	}
	if (is_verge > 0.5) {
		tarmac = vec3(0.024, 0.048, 0.018);
	}

	// Crisp UK TSRGD motorway road markings (2 m mark / 7 m gap on 9 m pitch!)
	float dash9 = smoothstep(0.0, 0.15, mod(s_abs, 9.0)) * (1.0 - smoothstep(1.85, 2.05, mod(s_abs, 9.0)));
	float solid_l = smoothstep(0.14, 0.06, abs(v_x + 5.4));
	float solid_r = smoothstep(0.14, 0.06, abs(v_x - 5.4));
	float solid_o1 = smoothstep(0.14, 0.06, abs(v_x - 9.2));
	float solid_o2 = smoothstep(0.14, 0.06, abs(v_x - 20.0));
	float lane_d1 = smoothstep(0.11, 0.04, abs(v_x + 1.8)) * dash9;
	float lane_d2 = smoothstep(0.11, 0.04, abs(v_x - 1.8)) * dash9;
	float lane_o1 = smoothstep(0.11, 0.04, abs(v_x - 12.8)) * dash9;
	float lane_o2 = smoothstep(0.11, 0.04, abs(v_x - 16.4)) * dash9;
	float paint_mask = clamp(solid_l + solid_r + solid_o1 + solid_o2 + lane_d1 + lane_d2 + lane_o1 + lane_o2, 0.0, 1.0);
	// Fade fine lines smoothly at long range to prevent aliasing shimmer
	paint_mask *= 1.0 - smoothstep(85.0, 165.0, v_dist);
	vec3 paint_col = vec3(0.86, 0.87, 0.85);

	// Authentic colour-coded British motorway Cat's-Eyes every 18 m!
	float stud_z = abs(mod(s_abs + 4.5, 18.0) - 9.0);
	float stud_len = smoothstep(0.32, 0.06, stud_z) * smoothstep(2.5, 8.0, -v_z) * (1.0 - smoothstep(65.0, 125.0, v_dist));
	vec3 stud_glow = vec3(0.0);
	float stud_strength = 0.25 + headlight_level * 2.1;
	stud_glow += vec3(1.0, 0.14, 0.08) * smoothstep(0.18, 0.04, abs(v_x + 5.4)) * stud_len * stud_strength; // Red left shoulder
	stud_glow += vec3(0.95, 0.97, 1.0) * (smoothstep(0.16, 0.04, abs(v_x + 1.8)) + smoothstep(0.16, 0.04, abs(v_x - 1.8))) * stud_len * stud_strength; // White lane studs
	stud_glow += vec3(1.0, 0.64, 0.08) * smoothstep(0.18, 0.04, abs(v_x - 5.4)) * stud_len * stud_strength; // Amber central reserve

	// Base lighting: sun + sky hemisphere + wet darkening + lightning flash
	float wet_dark = mix(1.0, 0.56, wet * (1.0 - is_median));
	vec3 ambient_col = mix(sky_low, sky_top, 0.35) * (0.28 + 0.72 * day_level) + vec3(0.22, 0.26, 0.36) * lightning * 0.85;
	float ndl = max(sun_dir.y, 0.0);
	vec3 direct_col = sun_col * ndl * (0.55 + 0.55 * day_level);
	vec3 base = mix(tarmac * wet_dark, paint_col, paint_mask * 0.92);
	vec3 lit_road = base * (ambient_col + direct_col);

	// Overhead SOX / SON motorway streetlamp pools every 42 m on lit stretches!
	float lamp_z = abs(mod(s_abs, 42.0) - 21.0);
	float pool = exp(-(lamp_z * lamp_z) / 145.0) * smoothstep(20.0, 4.0, abs(v_x - 6.8));
	vec3 lamp_rgb = mix(vec3(1.0, 0.48, 0.08), vec3(1.0, 0.74, 0.34), step(1.5, v_lamp_style));
	float night_fac = 1.0 - smoothstep(0.18, 0.68, day_level);
	lit_road += base * lamp_rgb * pool * v_lit * night_fac * (1.15 + wet * 0.65);

	// Wet asphalt grazing sky & lamp reflection streaks!
	float fresnel = clamp(pow(1.0 - clamp(abs(VIEW.y), 0.0, 1.0), 3.2), 0.0, 1.0);
	vec3 refl_col = mix(sky_low, sky_top, 0.25) * (0.45 + 0.55 * day_level);
	refl_col += lamp_rgb * exp(-(lamp_z * lamp_z) / 90.0) * v_lit * night_fac * 1.45;
	// Subtle oncoming headlight shimmer on wet right carriageway
	float oncoming_shimmer = smoothstep(9.0, 12.5, v_x) * smoothstep(21.0, 17.5, v_x)
			* (0.5 + 0.5 * sin(s_world * 0.09 + time_sec * 3.8)) * night_fac;
	refl_col += vec3(0.95, 0.92, 0.82) * oncoming_shimmer * 0.35;
	lit_road = mix(lit_road, refl_col, wet * (1.0 - is_median) * (0.18 + 0.52 * fresnel) * (0.75 + 0.25 * tyre_track));

	// Our own GT twin Xenon dipped-beam headlight cones on the asphalt ahead!
	if (headlight_level > 0.01 && v_z < -1.5) {
		float d_fwd = -v_z;
		float spread = 1.15 + d_fwd * 0.145;
		float cone_l = exp(-pow((v_x + 0.72) / spread, 2.0));
		float cone_r = exp(-pow((v_x - 0.72) / spread, 2.0));
		float beam = (cone_l + cone_r) * 0.55 * exp(-d_fwd * 0.024) * smoothstep(1.5, 5.5, d_fwd);
		lit_road += base * vec3(0.92, 0.96, 1.0) * beam * headlight_level * 2.1;
	}

	lit_road += stud_glow;

	// Exponential distance fog + horizon blend into sky_low
	float fog_k = 1.0 - exp(-v_dist * (0.0042 + fog_density * 0.0185));
	float far_fade = smoothstep(125.0, 178.0, v_dist);
	vec3 final_col = mix(lit_road, fog_col, clamp(max(fog_k, far_fade * 0.96), 0.0, 1.0));
	ALBEDO = final_col;
}
