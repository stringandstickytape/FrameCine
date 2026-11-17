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
// The area in pixels (for round shapes and lines of a fixed width).
uniform vec2 size = vec2(1280.0, 720.0);
// The track's cover (a plain grey square without one; has_cover is then 0).
uniform sampler2D cover : filter_linear_mipmap, repeat_disable;
uniform float has_cover = 0.0;

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
