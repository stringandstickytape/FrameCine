// What every visualiser is given (docs/visualisers.md, "Writing one"). Start a visualiser's shader with
//   shader_type canvas_item;
//   #include "res://visualisers/visualiser.gdshaderinc"
// and set COLOR in fragment(). UV runs 0..1 over the visualiser's area, (0, 0) at the top left. The area is
// see-through: alpha 0 shows the music card behind (dark grey). The app sets every uniform below each frame.

// The sound in BINS (128) bands, low (30 Hz, x = 0) to high (16 kHz, x = 1), log-spaced. r: the level now, 0..1;
// g: the same rising at once and falling slowly (steadier; what the bars use).
uniform sampler2D spectrum : filter_linear, repeat_disable;
// The last 512 samples of the sound (mono), -1..1 in r, starting at a rising zero crossing when there is one.
uniform sampler2D waveform : filter_linear, repeat_disable;
// 0..1, smoothed like spectrum's g: the low end (20-250 Hz), the middle (250 Hz-2 kHz), the top (2-12 kHz), all.
uniform float bass = 0.0;
uniform float mid = 0.0;
uniform float treble = 0.0;
uniform float level = 0.0;
// 1 on a beat (a jump in the bass), falling to 0 over 0.3 s; beats counts them (for taking turns).
uniform float beat = 0.0;
uniform float beats = 0.0;
// Seconds of playing: stops while paused. Use it rather than TIME.
uniform float vis_time = 0.0;
// This frame's seconds (0 while paused): for a visualiser with "feedback", so it changes at the same speed at any
// frame rate and stands still while paused.
uniform float vis_dt = 0.0;
// A clock that runs with the music: 0.4 s a second in silence, up to 1.6 with loud bass. Use it for motion that
// speeds up with the sound and never jumps (a scroll, a spin, a drift). Stops while paused.
uniform float drive = 0.0;
// With "feedback": true in visualiser.json: this visualiser's own last frame (same size, before the flash limit).
// 8 bits a channel: a fade must take off at least 1/255 a frame or it never reaches black. fresh is 1 for the first
// frames after a start, while previous still holds the picture from before.
uniform sampler2D previous : filter_linear, repeat_disable;
uniform float fresh = 1.0;
// The area in pixels (for round shapes and lines of a fixed width).
uniform vec2 size = vec2(1280.0, 720.0);
// The track's cover (a plain grey square without one; has_cover is then 0).
uniform sampler2D cover : filter_linear_mipmap, repeat_disable;
uniform float has_cover = 0.0;
// With "picture": true in visualiser.json: the picture of what plays (a film's frame, a captured window), when the
// visualiser shows in its place on the screen. has_screen_pic is 0 without one (a music file; screen_pic is then plain
// grey), and screen_pic_aspect is its width over its height. Sample it wherever and as often as you like: screen_pic_at().
uniform sampler2D screen_pic : filter_linear, repeat_disable;
uniform float has_screen_pic = 0.0;
uniform float screen_pic_aspect = 1.7778;

// The smoothed level at x (0 low .. 1 high).
float band(float x) {
	return texture(spectrum, vec2(clamp(x, 0.0, 1.0), 0.5)).g;
}

// The level now at x.
float band_now(float x) {
	return texture(spectrum, vec2(clamp(x, 0.0, 1.0), 0.5)).r;
}

// The smoothed level averaged from x0 to x1.
float band_between(float x0, float x1) {
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += band(mix(x0, x1, (float(i) + 0.5) / 4.0));
	}
	return s * 0.25;
}

// The waveform at x (0 oldest .. 1 newest), -1..1.
float wave_at(float x) {
	return texture(waveform, vec2(clamp(x, 0.0, 1.0), 0.5)).r;
}

// 1 inside a shape whose signed distance in pixels is d, 0 outside, smooth over one pixel.
float fill_px(float d) {
	return clamp(0.5 - d, 0.0, 1.0);
}

// The picture at uv (0..1 over it, (0, 0) top left); black outside it, and grey when there is none.
vec3 screen_pic_at(vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return vec3(0.0);
	}
	return texture(screen_pic, uv).rgb;
}
