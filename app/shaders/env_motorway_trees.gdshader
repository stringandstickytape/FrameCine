shader_type spatial;
render_mode unshaded, cull_disabled;

// Alpha-cutout British tree & hedgerow impostors (uk_trees_impostors.png, 4x4 grid).
// Uses ALPHA_SCISSOR_THRESHOLD so blend_layers overdraw stays strictly 0.00!
// INSTANCE_CUSTOM: (cell_col, cell_row, shade_tint, 0)

uniform sampler2D tree_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float fog_density = 0.0;
uniform float day_level = 0.5;
uniform float lightning = 0.0;
uniform vec3 sky_top = vec3(0.08, 0.14, 0.28);
uniform vec3 sky_low = vec3(0.24, 0.28, 0.34);
uniform vec3 sun_col = vec3(1.0, 0.92, 0.78);
uniform vec3 fog_col = vec3(0.20, 0.24, 0.30);

varying vec2 v_uv;
varying float v_dist;
varying float v_tint;
varying float v_hfrac;

void vertex() {
	vec2 cell = INSTANCE_CUSTOM.xy;
	v_uv = (cell + UV) * 0.25;
	v_tint = INSTANCE_CUSTOM.z;
	v_hfrac = 1.0 - UV.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_dist = length(wp.xz);
}

void fragment() {
	vec4 tex = texture(tree_atlas, v_uv);
	if (tex.a < 0.42) {
		discard;
	}
	// Subtle crown top-to-bottom lighting gradient + golden hour / night tint
	float crown = 0.68 + 0.38 * v_hfrac;
	vec3 amb = mix(sky_low, sky_top, 0.4) * (0.24 + 0.76 * day_level) + vec3(0.22, 0.26, 0.38) * lightning * 0.85;
	vec3 direct = sun_col * (0.28 + 0.62 * day_level) * (0.55 + 0.45 * v_hfrac);
	vec3 col = tex.rgb * v_tint * crown * (amb + direct);

	float fog_k = 1.0 - exp(-v_dist * (0.0046 + fog_density * 0.0185));
	float far_fade = smoothstep(115.0, 172.0, v_dist);
	ALBEDO = mix(col, fog_col, clamp(max(fog_k, far_fade), 0.0, 1.0));
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.42;
}
