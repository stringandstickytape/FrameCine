// A window to the real room (scripts/play/real_windows.gd): where this draws, the headset's cameras show through.
// The app runs in the ALPHA_BLEND environment blend mode while a window is on, so the eye buffer's alpha says how much
// of the cameras' view the runtime shows behind the app's picture. Multiply blending scales what is already there,
// colour and alpha apart: colour by 1 - reveal (the room goes), alpha by 1 - reveal * light (the cameras come, dimmed
// with the room light as the passthrough room's are). No depth test, back faces: the window shows through whatever
// the room has in front of or inside it, from outside the box or in it; drawn first in the transparent pass, so the
// panel, subtitles and other see-through things still draw over it.
shader_type spatial;
render_mode unshaded, blend_mul, cull_front, depth_test_disabled, depth_draw_never, shadows_disabled,
		specular_disabled, fog_disabled;

// How much of the cameras' view shows, 0..1.
uniform float reveal = 1.0;
// The room light on the cameras' view, 0..1.
uniform float light = 1.0;

void fragment() {
	ALBEDO = vec3(1.0 - reveal);
	ALPHA = 1.0 - reveal * light;
}
