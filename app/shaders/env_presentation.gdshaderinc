// The presentation chain's stages (scripts/env/systems/presentation.gd, docs/environments.md "The presentation
// system"): what happens to the film between the source and the glass. Included by env_presentation.gdshader after
// video_common.gdshaderinc. Every uniform here starts with pr_; the script sets them, and copies the rest (the
// screen's own) from the screen's material.
//
//   source        film (gate weave, a slight tilt, flicker, dust, scratches, the lamp's hotspot), tape (tracking
//                 wobble, chroma bleed, head-switch noise at the bottom), broadcast (interlace)
//   transmission  aerial noise (snow), a ghost (the signal's echo off a building), a weak signal
//   display       mechanical (a 1930 mechanical-scan set's few glowing lines), crt (curvature, round corners, a
//                 shadow mask, an aperture grille or a slot mask, scanlines, the glass's reflection), panel (a flat
//                 panel's pixel grid and backlight bleed)
//
// Cost: no loop and no texture read of its own except the ghost and the chroma bleed, which take one more cheap
// sample each (video_pixel(): one bilinear tap per plane; the script turns the deband off then). Every pattern is
// faded out as its period comes near a pixel of the eye buffer (fwidth), so a mask finer than the display does not
// shimmer. Stages that are off cost a uniform branch.

// The picture's width over its height (the screen's flat size).
uniform float pr_aspect = 1.7778;
// 0 none, 1 film, 2 tape, 3 broadcast.
uniform int pr_source = 0;
// Film: the gate's drift (UV), the tilt and the overscan that hides its corners (a 2 x 2 matrix: xy the first
// column, zw the second, in picture-height units), the flicker's gain now, dust and scratches (0..1), the scratches'
// places (UV x) and strengths, the film frame (a new dust pattern each), the lamp's hotspot (0..1).
uniform vec2 pr_weave = vec2(0.0);
uniform vec4 pr_turn = vec4(1.0, 0.0, 0.0, 1.0);
uniform float pr_flicker = 1.0;
uniform float pr_dust = 0.0;
uniform vec4 pr_scratch_x = vec4(-1.0);
uniform vec4 pr_scratch_a = vec4(0.0);
uniform float pr_frame = 0.0;
uniform float pr_hotspot = 0.0;
// Tape: tracking wobble, head-switch noise, chroma bleed, noise (0..1).
uniform float pr_tracking = 0.0;
uniform float pr_head_switch = 0.0;
uniform float pr_bleed = 0.0;
uniform float pr_tape_noise = 0.0;
// Broadcast: interlace (0..1); the field shown now (0, 1); the picture's lines (scanlines, interlace, snow).
uniform float pr_interlace = 0.0;
uniform float pr_field = 0.0;
uniform float pr_lines = 576.0;
// Transmission (0..1 each); the ghost's distance to the right (fraction of the width).
uniform float pr_snow = 0.0;
uniform float pr_ghost = 0.0;
uniform float pr_ghost_shift = 0.03;
uniform float pr_weak = 0.0;
// 0 none, 1 mechanical, 2 crt, 3 panel.
uniform int pr_display = 0;
uniform float pr_curvature = 0.0;
uniform float pr_corner = 0.0;
// 0 none, 1 shadow mask (dot triads), 2 aperture grille (stripes), 3 slot mask.
uniform int pr_mask = 0;
uniform float pr_mask_pitch = 420.0;
uniform float pr_mask_strength = 0.0;
uniform float pr_scanlines = 0.0;
uniform float pr_glass = 0.0;
uniform float pr_mech_lines = 30.0;
uniform float pr_panel_grid = 0.0;
uniform float pr_panel_pixels = 1366.0;
uniform float pr_panel_bleed = 0.0;
// The picture's colour (0: black and white), its tint (gamma-encoded, multiplied) and gain.
uniform float pr_colour = 1.0;
uniform vec3 pr_tint = vec3(1.0);
uniform float pr_gain = 1.0;

const vec3 PR_LUMA = vec3(0.2126, 0.7152, 0.0722);

float pr_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// How much of a pattern with this coordinate to keep: 1 while one period spans several pixels, 0 from about two
// (the pattern would alias into moire).
float pr_keep(float coord) {
	return 1.0 - smoothstep(0.22, 0.45, fwidth(coord));
}

// The position in the eye's picture to sample for the screen point mesh_uv (0..1, y down): the tube's curvature,
// the film's tilt and weave, the tape's wobble and head-switch tear. Uniform control flow only (the caller takes the
// derivatives of the result).
vec2 pr_geometry(vec2 mesh_uv, float time) {
	vec2 c = (mesh_uv - 0.5) * vec2(pr_aspect, 1.0);
	// A tube's face bulges: the picture's edges bow out and its corners fall off the glass.
	float k = pr_display == 2 ? pr_curvature * 0.09 : 0.0;
	c *= 1.0 + k * dot(c, c);
	c = mat2(pr_turn.xy, pr_turn.zw) * c;
	vec2 p = c / vec2(pr_aspect, 1.0) + 0.5 + pr_weave;
	if (pr_source == 2) {
		// Tracking: the lines sway a little, slowly, more some moments than others.
		float sway = 0.0011 * sin(p.y * 9.0 + time * 1.7) + 0.0005 * sin(p.y * 37.0 - time * 4.3);
		p.x += pr_tracking * sway * (0.6 + 0.4 * sin(time * 0.37));
		// Head switching: the last few lines tear to the right, raggedly.
		float band = smoothstep(0.972, 0.992, p.y) * pr_head_switch;
		float line = floor(p.y * pr_lines);
		p.x += band * (0.008 + 0.02 * pr_hash(vec2(line, floor(time * 30.0))));
	}
	return p;
}

// One more cheap sample of the film (the ghost, the chroma bleed).
vec3 pr_sample(vec2 p, int view) {
	return clamp(video_pixel(p, view), 0.0, 1.0);
}

// The tape's colour lags and smears: the chroma of a sample a little to the left mixed in, the luma kept.
vec3 pr_bleed_colour(vec3 rgb, vec2 p, int view) {
	vec3 late = pr_sample(p - vec2(0.006 * pr_bleed, 0.0), view);
	float y = dot(rgb, PR_LUMA);
	vec3 chroma = mix(rgb - y, late - dot(late, PR_LUMA), 0.65 * pr_bleed) * (1.0 - 0.25 * pr_bleed);
	return y + chroma;
}

// A ghost: the signal's echo, fainter, a little to the right.
vec3 pr_ghosted(vec3 rgb, vec2 p, int view) {
	vec3 g = pr_sample(p - vec2(pr_ghost_shift, 0.0), view);
	return mix(rgb, g, 0.32 * pr_ghost) + 0.04 * pr_ghost * (g - 0.5);
}

// The source's own marks on the picture (film, tape, broadcast), in its own coordinates p.
vec3 pr_source_marks(vec3 rgb, vec2 p, float time) {
	if (pr_source == 1) {
		vec2 c = (p - 0.5) * vec2(pr_aspect, 1.0);
		rgb *= 1.0 - pr_hotspot * 0.3 * dot(c, c);
		// Dust: now and then a speck in a cell, a new pattern every film frame; most dark, some light.
		vec2 g = p * vec2(36.0 * pr_aspect, 36.0);
		vec2 cell = floor(g);
		float h = pr_hash(cell + pr_frame * 17.31);
		float present = step(h, pr_dust * 0.012);
		vec2 at = vec2(pr_hash(cell + 3.7 + pr_frame), pr_hash(cell + 9.1 + pr_frame));
		float r = 0.08 + 0.22 * pr_hash(cell + 5.3 + pr_frame);
		float d = length(fract(g) - (0.25 + 0.5 * at));
		float speck = present * (1.0 - smoothstep(r * 0.55, r, d));
		rgb = mix(rgb, vec3(h < pr_dust * 0.003 ? 0.85 : 0.04), speck * 0.85);
		// Scratches: thin lines running down the film, broken here and there.
		float px = max(fwidth(p.x), 1e-5);
		for (int i = 0; i < 4; i++) {
			float w = 1.0 - smoothstep(0.0, max(0.0007, px * 1.2), abs(p.x - pr_scratch_x[i]));
			float run = 0.55 + 0.45 * sin(p.y * 23.0 + pr_frame * 1.3 + float(i) * 2.1);
			rgb = mix(rgb, vec3(0.92), w * run * pr_scratch_a[i]);
		}
	} else if (pr_source == 2) {
		float band = smoothstep(0.972, 0.992, p.y) * pr_head_switch;
		float n = pr_hash(floor(p * vec2(pr_lines * pr_aspect, pr_lines)) + fract(time * 13.7) * 91.0) - 0.5;
		rgb += n * (0.05 * pr_tape_noise + 0.5 * band);
		// The tape's softer colour.
		float y = dot(rgb, PR_LUMA);
		rgb = mix(vec3(y), rgb, 1.0 - 0.15 * pr_tape_noise);
	} else if (pr_source == 3) {
		float line = p.y * pr_lines;
		float other = step(0.5, fract((floor(line) + pr_field) * 0.5));
		rgb *= 1.0 - pr_interlace * 0.1 * other * pr_keep(line);
	}
	return rgb;
}

// The way here: aerial noise, a weak signal (paler, flatter, more snow).
vec3 pr_transmission(vec3 rgb, vec2 p, float time) {
	float snow = pr_snow + 0.35 * pr_weak;
	if (snow > 0.0) {
		vec2 cell = floor(p * vec2(pr_lines * pr_aspect * 0.75, pr_lines));
		float n = pr_hash(cell + fract(time * 7.31) * 113.0) + pr_hash(cell * 1.7 + fract(time * 3.17) * 57.0) - 1.0;
		rgb += n * snow * 0.32;
		rgb += snow * 0.03;
	}
	if (pr_weak > 0.0) {
		float y = dot(rgb, PR_LUMA);
		rgb = mix(vec3(y), rgb, 1.0 - 0.8 * pr_weak);
		rgb = mix(rgb, vec3(0.42), 0.35 * pr_weak);
	}
	return rgb;
}

// The colour of the set: saturation, tint, gain, the lamp's (or the neon's) flicker.
vec3 pr_colour_of(vec3 rgb) {
	float y = dot(rgb, PR_LUMA);
	return mix(vec3(y), rgb, pr_colour) * pr_tint * (pr_gain * pr_flicker);
}

// Rounded rectangle: inside 1, outside 0, with an edge a pixel wide. c: centred, height 1; r: the corner radius.
float pr_rounded(vec2 c, vec2 half_size, float r) {
	vec2 q = abs(c) - half_size + r;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
	float aa = max(fwidth(d), 1e-5);
	return 1.0 - smoothstep(-aa, aa, d);
}

// The phosphors behind a mask, at screen point uv: the three colours' weights (mean about 0.5).
vec3 pr_mask_pattern(vec2 uv) {
	float x = uv.x * pr_mask_pitch;
	float y = uv.y * pr_mask_pitch / pr_aspect;
	float row = floor(y * 1.5);
	float shift = pr_mask == 1 ? 0.5 * mod(row, 2.0) : 0.0;
	vec3 m = 0.5 + 0.5 * cos(6.2831853 * (vec3(x + shift) - vec3(0.0, 1.0 / 3.0, 2.0 / 3.0)));
	if (pr_mask == 1) {
		m *= 0.55 + 0.45 * cos(6.2831853 * y * 1.5);
	} else if (pr_mask == 3) {
		float column = floor(x);
		m *= smoothstep(0.0, 0.12, abs(fract(y * 0.75 + 0.5 * mod(column, 2.0)) - 0.5));
	}
	return m;
}

// The display: mesh_uv is the screen point (on the glass), p the picture's sample position, view_dir and the axes
// in world space (the glass's reflection). Returns the colour and how much of the glass shows the picture.
vec3 pr_display_of(vec3 rgb, vec2 mesh_uv, vec2 p, vec3 to_eye, vec3 ax, vec3 ay, vec3 az) {
	vec2 c0 = (mesh_uv - 0.5) * vec2(pr_aspect, 1.0);
	if (pr_display == 1) {
		// A mechanical-scan set: a few lines across (the scan ran up and down), a neon's orange glow, soft edges.
		float s = p.x * pr_mech_lines;
		float ridge = 0.5 + 0.5 * sin(3.14159265 * fract(s));
		rgb = vec3(pow(clamp(dot(rgb, PR_LUMA), 0.0, 1.0), 1.3)) * vec3(1.0, 0.48, 0.16) * 1.15;
		rgb *= mix(1.0, 0.45 + 0.55 * ridge, pr_keep(s));
		vec2 e = c0 / vec2(pr_aspect, 1.0);
		rgb *= 1.0 - smoothstep(0.18, 0.62, length(e * vec2(1.2, 1.0)));
		return rgb;
	}
	if (pr_display == 2) {
		float line = p.y * pr_lines * (pr_source == 3 ? 0.5 : 1.0);
		float scan = 0.5 + 0.5 * cos(6.2831853 * line);
		float ks = pr_scanlines * pr_keep(line);
		rgb *= mix(1.0, 0.45 + 0.55 * scan, ks) / (1.0 - 0.27 * ks);
		if (pr_mask > 0) {
			float km = pr_mask_strength * pr_keep(mesh_uv.x * pr_mask_pitch);
			rgb *= mix(vec3(1.0), pr_mask_pattern(mesh_uv), km) / (1.0 - 0.5 * km);
		}
		// Darker towards the tube's edges.
		rgb *= 1.0 - 0.35 * pr_curvature * dot(c0, c0);
		// The glass: a soft light behind the viewer seen in the bulge, and a faint sheen at a glance.
		vec3 n = normalize(az + (c0.x * ax - c0.y * ay) * pr_curvature * 0.7);
		vec3 r = reflect(-to_eye, n);
		vec3 light = normalize(az + ay * 0.55 - ax * 0.35);
		float spec = pow(max(dot(r, light), 0.0), 14.0);
		float sheen = 1.0 - max(dot(n, to_eye), 0.0);
		rgb += vec3(0.82, 0.86, 0.92) * pr_glass * (0.2 * spec + 0.05 * sheen + 0.012);
		float corner = pr_rounded(c0, vec2(0.5 * pr_aspect, 0.5), 0.5 * pr_corner);
		return rgb * corner;
	}
	if (pr_display == 3) {
		vec2 px = mesh_uv * vec2(pr_panel_pixels, pr_panel_pixels / pr_aspect);
		vec2 f = abs(fract(px) - 0.5);
		float gap = smoothstep(0.38, 0.5, max(f.x, f.y));
		rgb *= 1.0 - pr_panel_grid * 0.35 * gap * pr_keep(px.x);
		// The backlight comes through where the picture is dark, most at the corners.
		float y = dot(rgb, PR_LUMA);
		float edge = smoothstep(0.25, 0.75, length(c0 / vec2(pr_aspect, 1.0)) * 1.2);
		rgb += pr_panel_bleed * (0.025 + 0.05 * edge) * (1.0 - y) * vec3(0.85, 0.9, 1.0);
		rgb += vec3(0.82, 0.86, 0.92) * pr_glass * 0.01;
		return rgb;
	}
	return rgb;
}
