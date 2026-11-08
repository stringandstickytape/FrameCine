// Small lights far out on the Moon round the Crater's dome (scripts/env/systems/kit/lunar_surface.gd): the base's
// windows, the mast's beacon, the marker lights along the track, the lamps over the airlocks' hatches. Each is a quad
// whose corners all sit at the light; here they are spread to face the eye, `COLOR.a` metres across but never under
// a tenth of a degree, so a far light stays a few pixels wide and never shimmers as the head moves. A bright core and a
// soft glow, added over what is behind. UV2.x: 1 for the beacon, which swells and fades once in 4 s (well under the
// photosensitivity ceiling) and never goes out. No depth write, never baked.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled,
		skip_vertex_transform;

uniform float energy = 1.0;
uniform float min_angle = 0.0018;
uniform float clock = 0.0;

varying vec3 col;
varying float pulse;

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(c.xyz);
	float size = max(COLOR.a, d * min_angle);
	c.xy += (UV * 2.0 - 1.0) * size;
	VERTEX = c.xyz;
	col = COLOR.rgb;
	pulse = UV2.x;
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float k = pow(max(1.0 - r, 0.0), 3.0) + smoothstep(0.3, 0.0, r) * 1.5;
	float swell = mix(1.0, 0.45 + 0.55 * (0.5 + 0.5 * sin(clock * 6.2831853 / 4.0)), pulse);
	ALBEDO = col * k * energy * swell;
}
