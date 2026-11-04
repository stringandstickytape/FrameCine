// The print on the controllers (scripts/xr/label_surface.gd builds the meshes, scripts/xr/label_font.gd the atlas).
// Each glyph is a distance field, so the edge is worked out per pixel instead of being read from a picture of the text:
// it stays sharp up close, and small or far away it is filtered as true coverage of the pixel. Unlit, and only the
// pixels of the letters run this.
shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled, specular_disabled, skip_vertex_transform;

uniform sampler2D atlas : filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 ink : source_color = vec3(1.0);
// A backing behind the letters for a busy or mid-toned look (scripts/xr/controller_look.gd): an outline of this colour
// round each stroke, backing_width of the field past its edge (0: none; at most 0.4, the glyph quad's margin). The same
// four samples draw it.
uniform vec3 backing : source_color = vec3(0.0);
uniform float backing_width = 0.0;
// Atlas pixels the field spans (label_font.gd FIELD_RANGE).
uniform float field_range = 10.0;
// Moved towards the eye, metres: at a grazing angle the sticker's small height over the surface is almost no depth.
uniform float depth_lift = 0.0004;
// Thin strokes lose against a pixel: thicken them by this share of a pixel per side once they are small.
uniform float stem_gain = 0.2;

float median(vec3 c) {
	return max(min(c.r, c.g), min(max(c.r, c.g), c.b));
}

// One level sharper than a single sample would want: four of them share the pixel. Anisotropic filtering keeps the
// detail along the text at a grazing angle.
float field(vec2 uv) {
	return median(texture(atlas, uv, -1.0).rgb);
}

void vertex() {
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX *= 1.0 - depth_lift / length(VERTEX);
}

void fragment() {
	vec2 dx = dFdx(UV);
	vec2 dy = dFdy(UV);
	vec2 size = vec2(textureSize(atlas, 0));
	float across = length(dx * size);
	float down = length(dy * size);
	// Atlas pixels under one screen pixel, along its shorter side: what the text's size really is. The longer side is
	// only the angle, and thickening for that would turn foreshortened text into a bar.
	float footprint = min(across, down);
	// Field units per screen pixel, from the field's own slope: at a grazing angle it is wide across the strokes that
	// are foreshortened and narrow along the others, so each edge gets the softness it needs and no more.
	float centre = field(UV);
	float slope = length(vec2(dFdx(centre), dFdy(centre)));
	// The slope drops to nothing where the field saturates; the footprint is the bound there.
	float pixel = max(slope, footprint / field_range * 0.5);
	float edge = 0.5 - stem_gain * footprint / field_range * smoothstep(1.0, 3.0, footprint);
	// Rotated grid of four samples in the pixel, each softened over its own share of it.
	vec4 f = vec4(field(UV + dx * -0.125 + dy * -0.375), field(UV + dx * 0.375 + dy * -0.125),
			field(UV + dx * 0.125 + dy * 0.375), field(UV + dx * -0.375 + dy * 0.125));
	float cover = dot(clamp((f - edge) / pixel * 2.0 + 0.5, 0.0, 1.0), vec4(0.25));
	// The backing: the same samples against an edge moved out; the letters over it.
	float behind = dot(clamp((f - edge + clamp(backing_width, 0.0, 0.4)) / pixel * 2.0 + 0.5, 0.0, 1.0), vec4(0.25));
	behind = max(behind, cover);
	ALBEDO = mix(backing, ink, cover / max(behind, 1e-4));
	ALPHA = behind;
}
