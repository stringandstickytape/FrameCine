shader_type spatial;
render_mode unshaded, cull_back;

// Retroreflective UK TSRGD Motorway Signs (m1_signs_atlas.png baked via FableRoadSignLibrary).
// INSTANCE_CUSTOM = (u0, v0, du, dv); COLOR.r = self_lit (1.0 for amber matrix '50' signals, 0.0 for reflective blue signs).

uniform sampler2D sign_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float day_level = 0.5;
uniform float headlight_level = 0.0;
uniform float fog_density = 0.0;
uniform float lightning = 0.0;
uniform vec3 sky_top = vec3(0.08, 0.14, 0.28);
uniform vec3 sky_low = vec3(0.24, 0.28, 0.34);
uniform vec3 sun_col = vec3(1.0, 0.92, 0.78);
uniform vec3 fog_col = vec3(0.20, 0.24, 0.30);

varying vec2 v_uv;
varying float v_dist;
varying float v_self_lit;
varying vec3 v_world_pos;

void vertex() {
	v_uv = INSTANCE_CUSTOM.xy + UV * INSTANCE_CUSTOM.zw;
	v_self_lit = COLOR.r;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_dist = length(v_world_pos.xz);
}

void fragment() {
	vec4 tex = texture(sign_atlas, v_uv);
	if (tex.a < 0.35) {
		discard;
	}
	vec3 col;
	if (v_self_lit > 0.5) {
		// Active amber dot-matrix motorway signal ('50' + corner amber lanterns): cuts boldly through fog & night!
		float lum = dot(tex.rgb, vec3(0.35, 0.55, 0.10));
		float glow = smoothstep(0.18, 0.45, lum);
		vec3 housing = tex.rgb * (0.24 + 0.55 * day_level);
		col = mix(housing, vec3(1.0, 0.68, 0.08) * (2.6 + (1.0 - day_level) * 1.2), glow);
	} else {
		// UK Class 2 microprismatic retroreflective sign sheeting:
		// Crisp natural daylight + dramatic headlight retroreflection at dusk/night!
		vec3 amb = mix(sky_low, sky_top, 0.35) * (0.26 + 0.74 * day_level) + vec3(0.22, 0.26, 0.38) * lightning * 0.7;
		vec3 sun_lit = sun_col * (0.45 + 0.65 * day_level);
		// Retroreflection peaks strongly along our headlight cone toward signs ahead (z < -4.. -120 m)
		float ahead = step(v_world_pos.z, -2.5);
		float lat = abs(v_world_pos.x);
		float retro = ahead * exp(-v_dist * 0.015) * exp(-lat * 0.045) * headlight_level;
		// White Transport Medium lettering has higher retroreflective return than blue sheeting
		float is_white = smoothstep(0.45, 0.85, min(tex.r, min(tex.g, tex.b)));
		float retro_boost = retro * (1.25 + 0.95 * is_white);
		// Motorway gantry signs & major ADS also have faint overhead sign luminaires at night
		float sign_lamp = (1.0 - day_level) * 0.34;
		col = tex.rgb * (amb + sun_lit + vec3(sign_lamp) + vec3(0.95, 0.97, 1.0) * retro_boost);
	}

	float fog_rate = v_self_lit > 0.5 ? (0.0012 + fog_density * 0.0055) : (0.0038 + fog_density * 0.0155);
	float fog_k = 1.0 - exp(-v_dist * fog_rate);
	float far_fade = smoothstep(125.0, 178.0, v_dist);
	ALBEDO = mix(col, fog_col, clamp(max(fog_k, far_fade), 0.0, 1.0));
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
}
