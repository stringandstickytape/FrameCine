// The toon_outline effect's second pass (scripts/assistant/assistant_room.gd): the part's back faces pushed out a
// little and drawn in one colour, so a line shows around its silhouette. Pushed out from the part's centre rather
// than along its normals, so a box's corners don't split open, and on the screen, in pixels: the line keeps its
// width (2 px by default; 20 px a degree on the headset) near and far.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, specular_disabled;

uniform vec3 outline_color : source_color = vec3(0.02);
// Pixels.
uniform float width = 2.0;

void vertex() {
	vec3 dir = length(VERTEX) > 1e-5 ? normalize(VERTEX) : NORMAL;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec2 on_screen = (PROJECTION_MATRIX * vec4(mat3(MODELVIEW_MATRIX) * dir, 0.0)).xy;
	// 1.4: a corner moves diagonally, so a straight edge moves out by about 0.7 of the push.
	if (length(on_screen) > 1e-6) {
		clip.xy += normalize(on_screen) * width * 1.4 * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color;
}
