shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Soft radial light halos around SOX/SON motorway streetlamps, oncoming headlights, and red HGV lamps in mist/night.
// Billboarded via MODELVIEW_MATRIX in vertex shader; compact radius keeps blend_layers well under budget.

uniform float halo_strength = 0.6;
uniform float fog_density = 0.0;

varying vec3 v_col;
varying float v_fade;

void vertex() {
	v_col = COLOR.rgb;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(wp.xz);
	v_fade = (1.0 - smoothstep(115.0, 178.0, dist)) * smoothstep(3.0, 12.0, dist);
	// Camera-facing spherical billboard keeping instance scale from MODEL_MATRIX column lengths
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec4 view_center = VIEW_MATRIX * vec4(wp, 1.0);
	POSITION = PROJECTION_MATRIX * (view_center + vec4(VERTEX.x * sx, VERTEX.y * sy, 0.0, 0.0));
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r2 = dot(d, d);
	if (r2 >= 1.0) {
		discard;
	}
	float falloff = exp(-r2 * 4.5) * (1.0 - r2);
	float boost = halo_strength * (1.0 + fog_density * 1.15) * v_fade;
	ALBEDO = v_col * falloff * boost;
	ALPHA = clamp(falloff * boost, 0.0, 1.0);
}
