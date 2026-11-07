// Ambient life's own lights (scripts/env/systems/life.gd): fireflies and a plane's lights as soft points that face
// the viewer (mode 0), and the deep-sea creatures' glowing bells (mode 1: a rim that glows where the bell is seen
// edge-on, pulsing as it swims). Additive, so they only ever add light; nothing here darkens (blend_mul is wrong on
// the Mobile renderer, see room_contact.gdshader).
// Per instance (MultiMesh): the colour (rgb a tint, alpha a fade) and custom data: x the pulse's phase (cycles),
// z the light's strength now (a firefly's flash, a strobe). glow scales every one (the system's live parameter).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

uniform int mode = 0;
uniform vec3 colour : source_color = vec3(1.0);
uniform float glow = 1.0;
// Mode 1: how much the bell narrows at the top of its pulse.
uniform float pulse = 0.18;

varying vec4 tint;
varying vec4 data;

void vertex() {
	tint = COLOR;
	data = INSTANCE_CUSTOM;
	if (mode == 0) {
		// Facing the main camera (both eyes alike), keeping the instance's scale.
		float s = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(MAIN_CAM_INV_VIEW_MATRIX[0] * s, MAIN_CAM_INV_VIEW_MATRIX[1] * s,
				MAIN_CAM_INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	} else {
		// The bell (UV.y 0 at its crown, 1 at its rim) draws in and stretches with the pulse.
		float p = 0.5 + 0.5 * sin(data.x * TAU);
		VERTEX.xz *= 1.0 - pulse * p * UV.y;
		VERTEX.y *= 1.0 + pulse * 0.6 * p;
	}
}

void fragment() {
	float a;
	if (mode == 0) {
		vec2 d = UV * 2.0 - 1.0;
		float r2 = dot(d, d);
		a = (exp(-r2 * 6.0) + 0.8 * exp(-r2 * 40.0)) * (1.0 - smoothstep(0.8, 1.0, r2));
	} else {
		float f = 1.0 - abs(dot(NORMAL, VIEW));
		a = 0.1 + 0.9 * f * f;
	}
	ALBEDO = colour * tint.rgb * (glow * tint.a * data.z * a);
}
