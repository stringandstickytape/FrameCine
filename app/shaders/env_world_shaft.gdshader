// Soft volumetric light shaft / atmospheric glow beam for Other Worlds rooms (Cenote cavern moonlight shaft,
// Cloud temple sunset shafts, Venus aerostat cloud glow, Giant's study banker's lamp cone). Additive, zero live
// lights, smooth silhouette edge softening (Fresnel), vertical taper via UV.y (0 top, 1 bottom), slow drifting mist
// shimmer via noise_map scaled by clock (Motion scales clock). Vertex COLOR.rgb tints per shaft, COLOR.a weights it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

uniform sampler2D noise_map : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 shaft_colour : source_color = vec3(0.62, 0.90, 1.0);
uniform float shaft_level = 0.55;
uniform float clock = 0.0;
uniform float edge_softness = 1.8;
uniform float wisp_strength = 0.35;

void fragment() {
	// Smooth radial edge fade so cylinder/cone silhouettes dissolve softly into air.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = pow(clamp(facing, 0.0, 1.0), edge_softness);
	// Soft fade at both top and bottom ends of the shaft (UV.y 0..1).
	float v_fade = smoothstep(0.0, 0.14, UV.y) * (1.0 - smoothstep(0.72, 1.0, UV.y));
	float n1 = texture(noise_map, vec2(UV.x * 2.2 + clock * 0.014, UV.y * 0.8 - clock * 0.022)).g;
	float n2 = texture(noise_map, vec2(UV.x * 4.5 - clock * 0.018, UV.y * 1.6 + clock * 0.016)).b;
	float wisps = mix(1.0, 0.55 + 0.9 * (n1 * 0.6 + n2 * 0.4), wisp_strength);
	float strength = edge * v_fade * wisps * shaft_level * COLOR.a;
	ALBEDO = shaft_colour * COLOR.rgb * strength;
}
