shader_type spatial;
render_mode unshaded, cull_back;

// Instanced opaque hardware, overbridges, traffic vehicles, Ratcliffe cooling towers, pylons & emissive bulbs.
// COLOR = RGB albedo; INSTANCE_CUSTOM.x = emissive strength (0 = lit structural surface, >0 = glowing bulb/window/lamp).

uniform float day_level = 0.5;
uniform float fog_density = 0.0;
uniform float lightning = 0.0;
uniform vec3 sky_top = vec3(0.08, 0.14, 0.28);
uniform vec3 sky_low = vec3(0.24, 0.28, 0.34);
uniform vec3 sun_dir = vec3(0.3, 0.6, -0.7);
uniform vec3 sun_col = vec3(1.0, 0.92, 0.78);
uniform vec3 fog_col = vec3(0.20, 0.24, 0.30);

varying vec3 v_col;
varying float v_emissive;
varying vec3 v_world_norm;
varying float v_dist;

void vertex() {
	v_col = COLOR.rgb;
	v_emissive = INSTANCE_CUSTOM.x;
	v_world_norm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_dist = length(wp.xz);
}

void fragment() {
	vec3 col;
	if (v_emissive > 0.05) {
		col = v_col * v_emissive;
	} else {
		float ndl = max(dot(normalize(v_world_norm), normalize(sun_dir)), 0.0);
		float up_fac = clamp(v_world_norm.y * 0.5 + 0.5, 0.0, 1.0);
		vec3 amb = mix(sky_low * 0.78, sky_top * 1.15, up_fac) * (0.26 + 0.74 * day_level)
				+ vec3(0.22, 0.26, 0.38) * lightning * 0.8;
		vec3 direct = sun_col * ndl * (0.35 + 0.72 * day_level);
		col = v_col * (amb + direct);
	}
	float fog_rate = v_emissive > 0.2 ? (0.0028 + fog_density * 0.011) : (0.0042 + fog_density * 0.0175);
	float fog_k = 1.0 - exp(-v_dist * fog_rate);
	float far_fade = smoothstep(128.0, 180.0, v_dist);
	ALBEDO = mix(col, fog_col, clamp(max(fog_k, far_fade * 0.92), 0.0, 1.0));
}
