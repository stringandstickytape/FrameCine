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
//                 panel's pixel grid and backlight bleed), rear_projection (soft focus, convergence fringes, a
//                 hotspot that follows the head, lenticular lines), oled (true blacks, a sheen at a glance)
//   the set       the window (`tube`: the tube's or the panel's shape) and the film in it (letterbox, pan and scan,
//                 14:9, stretched), a mirror's reflection (flipped), the light falling off away from the screen's
//                 axis, and switching on and off (the raster opening from a dot, collapsing to a line and a dot)
//
// Cost: no loop and no texture read of its own except the ghost and the chroma bleed, which take one more cheap
// sample each, and a rear projection's convergence (two) (video_pixel(): one bilinear tap per plane; the script turns the deband off then). Every pattern is
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
// 0 none, 1 mechanical, 2 crt, 3 panel, 4 rear projection, 5 oled.
uniform int pr_display = 0;
uniform float pr_curvature = 0.0;
uniform float pr_corner = 0.0;
// The set's window: the tube's (or the panel's) aspect (0: the picture's own). A wide film letterboxed in a squarer
// tube keeps the tube's round corners and bulge, not the picture's.
uniform float pr_tube = 0.0;
// The film in the window: 0 letterbox (all of it, bars where it is narrower or wider), 1 pan and scan (it fills the
// window, its sides cut off), 2 the 14:9 compromise (a little cut, thin bars), 3 stretched to the window.
uniform int pr_aspect_mode = 0;
// The picture flipped left to right (seen in a mirror the set's electronics do not turn round).
uniform bool pr_mirror = false;
// How much the light falls off (or the colour shifts) away from the screen's axis, 0..1.
uniform float pr_off_axis = 0.0;
// Rear projection: soft focus, the three tubes' convergence, the lenticular screen's lines (0..1 each).
uniform float pr_soft = 0.0;
uniform float pr_convergence = 0.0;
uniform float pr_lenticular = 0.0;
// Switching on and off: while pr_switching, the raster's reach (1, 1: the whole window), the picture's light
// (0..1), the beam's glow where the raster is small (a line, a dot), and the dark face of the set.
uniform bool pr_switching = false;
uniform vec2 pr_raster = vec2(1.0);
uniform float pr_power = 1.0;
uniform float pr_spot = 0.0;
uniform vec3 pr_face = vec3(0.0);
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
// The tube's (the set's window's) half size in the picture's units (the picture's height 1). The app makes the film's
// quad as wide as the room's screen, so the window is as wide as the quad: a squarer tube round a wide film is taller
// than the quad (the film letterboxed in it), a wider panel round a square film shorter (the film pillarboxed).
vec2 pr_tube_half() {
	float t = pr_tube > 0.0 ? pr_tube : pr_aspect;
	return vec2(0.5 * pr_aspect, 0.5 * pr_aspect / t);
}

// The film's half size in the window (the picture's units), by the aspect mode.
vec2 pr_picture_half() {
	vec2 w = pr_tube_half();
	vec2 film = vec2(0.5 * pr_aspect, 0.5);
	if (pr_aspect_mode == 3) {
		return w;
	}
	vec2 r = w / film;
	float fit = min(r.x, r.y);
	float fill = max(r.x, r.y);
	float k = fit;
	if (pr_aspect_mode == 1) {
		k = fill;
	} else if (pr_aspect_mode == 2) {
		// 14:9 of the film across the window's width, never more than filling it nor less than all of it.
		k = clamp(w.x / (0.5 * 14.0 / 9.0), fit, fill);
	}
	return film * k;
}

// How much the quad grows to cover the window (only its height: the window is as wide as the film's quad).
vec2 pr_expand() {
	if (pr_tube <= 0.0) {
		return vec2(1.0);
	}
	return vec2(1.0, max(1.0, 2.0 * pr_tube_half().y));
}

// The tube's bulge on a centred point (the picture's units).
vec2 pr_bulged(vec2 c) {
	float k = pr_display == 2 ? pr_curvature * 0.09 : 0.0;
	float th = 2.0 * pr_tube_half().y;
	return c * (1.0 + k * dot(c, c) / (th * th));
}

vec2 pr_geometry(vec2 mesh_uv, float time) {
	// A tube's face bulges: the picture's edges bow out and its corners fall off the glass (by the tube's height).
	vec2 c = pr_bulged((mesh_uv - 0.5) * vec2(pr_aspect, 1.0));
	// Switching: the deflection reaches only so far, and the whole picture is squeezed into the raster.
	if (pr_switching) {
		c /= max(pr_raster, vec2(0.002));
	}
	c = mat2(pr_turn.xy, pr_turn.zw) * c;
	vec2 p = c / (2.0 * pr_picture_half()) + 0.5 + pr_weave;
	if (pr_mirror) {
		p.x = 1.0 - p.x;
	}
	if (pr_source == 2) {
		// Tracking: the lines sway a little, slowly, more some moments than others.
		float sway = 0.0011 * sin(p.y * 9.0 + time * 1.7) + 0.0005 * sin(p.y * 37.0 - time * 4.3);
		p.x += pr_tracking * sway * (0.6 + 0.4 * sin(time * 0.37));
		// Head switching: the last few lines tear to the right, raggedly. Only the last 1% (about five lines): a set's
		// overscan hid most of it, and a letterboxed film's black bar fizzed with a wider band (the user, 2026-11-08).
		float band = smoothstep(0.988, 0.997, p.y) * pr_head_switch;
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

// A rear projection's three tubes, not quite converged: the red and the blue a little apart, more at the edges.
vec3 pr_converged(vec3 rgb, vec2 p, int view) {
	vec2 c = p - 0.5;
	vec2 off = pr_convergence * (vec2(0.0009, 0.0004) + 0.004 * c * length(c));
	rgb.r = pr_sample(p + off, view).r;
	rgb.b = pr_sample(p - off, view).b;
	return rgb;
}

// The source's own marks on the picture (film, tape, broadcast), in its own coordinates p.
vec3 pr_source_marks(vec3 rgb, vec2 p, float time) {
	if (pr_source == 1) {
		vec2 c = (p - 0.5) * vec2(pr_aspect, 1.0);
		rgb *= 1.0 - pr_hotspot * 0.3 * dot(c, c);
		// Dust: now and then a speck in a cell, a new pattern every film frame; most dark, a few light. Dirt in the gate
		// is in focus, so the edges are sharp (about a pixel), the outlines ragged, most specks small and now and then
		// a clump (round soft dots read as noise, not dirt: the user, 2026-11-08, Screen 3).
		vec2 g = p * vec2(36.0 * pr_aspect, 36.0);
		vec2 cell = floor(g);
		float h = pr_hash(cell + pr_frame * 17.31);
		float present = step(h, pr_dust * 0.016);
		vec2 at = vec2(pr_hash(cell + 3.7 + pr_frame), pr_hash(cell + 9.1 + pr_frame));
		float sz = pr_hash(cell + 5.3 + pr_frame);
		float r = 0.06 + 0.3 * sz * sz * sz;
		vec2 q = fract(g) - (0.3 + 0.4 * at);
		float seed = pr_hash(cell + 7.7 + pr_frame) * 6.2832;
		float ang = atan(q.y, q.x);
		float ragged = 1.0 + 0.32 * sin(ang * 3.0 + seed) + 0.18 * sin(ang * 5.0 - seed * 1.7)
				+ 0.1 * sin(ang * 9.0 + seed * 2.3);
		float d = length(q) / max(ragged, 0.35);
		float edge = max(fwidth(g.y) * 0.7, 0.004);
		float speck = present * (1.0 - smoothstep(r - edge, r + edge, d));
		// Not solid: thin dirt lets some of the picture through (bold specks read as a gimmick: the user, 2026-11-08).
		rgb = mix(rgb, vec3(h < pr_dust * 0.002 ? 0.8 : 0.03), speck * 0.6);
		// Hairs: a fine, faint curled fibre in a bigger cell, one frame each, about one a second at the worn print's dust.
		vec2 g2 = p * vec2(6.0 * pr_aspect, 6.0);
		vec2 c2 = floor(g2);
		float hair_on = step(pr_hash(c2 + pr_frame * 7.13 + 41.0), pr_dust * 0.0025);
		vec2 v = fract(g2) - (0.4 + 0.2 * vec2(pr_hash(c2 + pr_frame + 1.3), pr_hash(c2 + pr_frame + 2.9)));
		float rad = 0.12 + 0.23 * pr_hash(c2 + pr_frame + 4.1);
		float mid = pr_hash(c2 + pr_frame + 6.7) * 6.2832;
		float off = abs(mod(atan(v.y, v.x) - mid + 3.1416, 6.2832) - 3.1416);
		float span = 0.6 + 1.4 * pr_hash(c2 + pr_frame + 8.3);
		float w2 = max(fwidth(g2.y) * 0.45, 0.0008);
		float hair = hair_on * (1.0 - smoothstep(w2 * 0.5, w2 * 1.5, abs(length(v) - rad)))
				* (1.0 - smoothstep(span * 0.85, span, off));
		rgb = mix(rgb, vec3(0.05), hair * 0.45);
		// Scratches: thin lines running down the film, broken here and there.
		float px = max(fwidth(p.x), 1e-5);
		for (int i = 0; i < 4; i++) {
			float w = 1.0 - smoothstep(0.0, max(0.0007, px * 1.2), abs(p.x - pr_scratch_x[i]));
			float run = 0.55 + 0.45 * sin(p.y * 23.0 + pr_frame * 1.3 + float(i) * 2.1);
			rgb = mix(rgb, vec3(0.92), w * run * pr_scratch_a[i]);
		}
	} else if (pr_source == 2) {
		float band = smoothstep(0.988, 0.997, p.y) * pr_head_switch;
		float n = pr_hash(floor(p * vec2(pr_lines * pr_aspect, pr_lines)) + fract(time * 13.7) * 91.0) - 0.5;
		rgb += n * (0.05 * pr_tape_noise + 0.16 * band);
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

// Switching on and off: the raster's reach (outside it the set's dark face), the picture's light, brighter where
// the raster is small (the beam's energy on less of the glass, held under 0.85), and the beam's glow on a line or a
// dot. c: the window's point after the bulge (the picture's units).
vec3 pr_power_of(vec3 rgb, vec2 c) {
	vec2 reach = pr_tube_half() * pr_raster;
	vec2 q = abs(c) - reach;
	float aa = max(fwidth(c.y), 1e-5);
	float inside = 1.0 - smoothstep(-aa, aa, max(q.x, q.y));
	float boost = min(1.0 / max(pr_raster.x * pr_raster.y, 1e-4), 3.0);
	vec3 pic = boost > 1.0 ? min(rgb * boost, vec3(0.85)) : rgb;
	pic *= pr_power * inside;
	vec2 g = max(q, 0.0);
	float glow = pr_spot * exp(-dot(g, g) / (0.006 * 0.006));
	vec3 beam = vec3(0.85) * pr_tint * glow;
	return max(pic, beam) + pr_face * (1.0 - pr_power * inside);
}

// How a view from off the screen's axis changes the light: l, the way to the eye in the screen's frame (x right, y
// up, z out of the screen).
vec3 pr_off_axis_of(vec3 rgb, vec3 l) {
	if (pr_off_axis <= 0.0) {
		return rgb;
	}
	float z = max(l.z, 0.05);
	if (pr_display == 4) {
		// A lenticular screen sends its light in a fan: wide across, narrow up and down.
		float h = atan(l.x / z);
		float v = atan(l.y / z);
		float fan = exp(-(h * h) / (0.78 * 0.78) - (v * v) / (0.44 * 0.44));
		return rgb * mix(1.0, fan, pr_off_axis);
	}
	if (pr_display == 3) {
		// An LCD: the contrast washes out and the colour shifts, most from above and below.
		float k = pr_off_axis * min(1.0, 0.8 * l.x * l.x + 2.2 * l.y * l.y);
		vec3 tint = l.y > 0.0 ? vec3(1.02, 1.0, 0.92) : vec3(0.93, 0.97, 1.05);
		return mix(rgb, (0.07 + 0.84 * pow(max(rgb, 0.0), vec3(0.75))) * tint, k);
	}
	if (pr_display == 5) {
		float k = pr_off_axis * (l.x * l.x + l.y * l.y);
		return rgb * mix(vec3(1.0), vec3(0.95, 0.98, 1.04), k) * (1.0 - 0.1 * k);
	}
	// A tube: a little darker from the side.
	return rgb * (1.0 - pr_off_axis * 0.35 * (1.0 - z));
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
// wp, eye, origin: the point, the eye and the screen's middle in world space (the rear projection's hotspot).
vec3 pr_display_of(vec3 rgb, vec2 mesh_uv, vec2 p, vec3 to_eye, vec3 ax, vec3 ay, vec3 az, vec3 wp, vec3 eye,
		vec3 origin) {
	vec2 c0 = (mesh_uv - 0.5) * vec2(pr_aspect, 1.0);
	vec3 l = vec3(dot(to_eye, ax), dot(to_eye, ay), dot(to_eye, az));
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
		vec2 tube = pr_tube_half();
		vec2 ct = c0 / (2.0 * tube.y);
		rgb *= 1.0 - 0.35 * pr_curvature * dot(ct, ct);
		rgb = pr_off_axis_of(rgb, l);
		// The glass: a soft light behind the viewer seen in the bulge, and a faint sheen at a glance.
		vec3 n = normalize(az + (ct.x * ax - ct.y * ay) * pr_curvature * 0.7);
		vec3 r = reflect(-to_eye, n);
		vec3 light = normalize(az + ay * 0.55 - ax * 0.35);
		float spec = pow(max(dot(r, light), 0.0), 14.0);
		float sheen = 1.0 - max(dot(n, to_eye), 0.0);
		rgb += vec3(0.82, 0.86, 0.92) * pr_glass * (0.2 * spec + 0.05 * sheen + 0.012);
		float corner = pr_rounded(c0, tube, pr_corner * tube.y);
		return rgb * corner;
	}
	if (pr_display == 3) {
		vec2 px = mesh_uv * vec2(pr_panel_pixels, pr_panel_pixels / pr_aspect);
		vec2 f = abs(fract(px) - 0.5);
		float gap = smoothstep(0.38, 0.5, max(f.x, f.y));
		rgb *= 1.0 - pr_panel_grid * 0.35 * gap * pr_keep(px.x);
		// The backlight comes through where the picture is dark, most at the corners (none while it is off).
		float y = dot(rgb, PR_LUMA);
		float edge = smoothstep(0.25, 0.75, length(c0 / vec2(pr_aspect, 1.0)) * 1.2);
		float lit = pr_switching ? pr_power : 1.0;
		rgb += pr_panel_bleed * lit * (0.025 + 0.05 * edge) * (1.0 - y) * vec3(0.85, 0.9, 1.0);
		rgb = pr_off_axis_of(rgb, l);
		rgb += vec3(0.82, 0.86, 0.92) * pr_glass * 0.01;
		return rgb;
	}
	if (pr_display == 4) {
		// A rear projection: the lens's hotspot where the eye looks straight down the projector's light (it
		// follows the head), the lenticular screen's fine lines, a grey-black face, the fan of its light.
		vec3 lens = origin - az * 1.2;
		float t = dot(origin - eye, az) / min(dot(lens - eye, az), -1e-4);
		vec3 hot = eye + (lens - eye) * t;
		vec3 d = wp - hot;
		rgb *= 1.0 + pr_hotspot * 0.2 * exp(-dot(d, d) / (0.35 * 0.35));
		float lx = mesh_uv.x * 1200.0;
		float kl = pr_lenticular * pr_keep(lx);
		rgb *= (1.0 - kl * 0.12 * (0.5 + 0.5 * cos(6.2831853 * lx))) / (1.0 - 0.06 * kl);
		rgb = rgb * 0.97 + 0.02 * (pr_switching ? pr_power : 1.0);
		rgb = pr_off_axis_of(rgb, l);
		float sheen = pow(1.0 - max(l.z, 0.0), 4.0);
		rgb += vec3(0.82, 0.86, 0.92) * pr_glass * (0.04 * sheen + 0.008);
		return rgb;
	}
	if (pr_display == 5) {
		// An OLED panel: true blacks (no backlight, no lift), a little punch in the colour and the middle tones
		// (black stays black and white white: no tricks with the film's levels), a sheen only at a glance.
		float y = dot(rgb, PR_LUMA);
		rgb = max(mix(vec3(y), rgb, 1.06), 0.0);
		rgb = mix(rgb, rgb * rgb * (3.0 - 2.0 * rgb), 0.12);
		rgb = pr_off_axis_of(rgb, l);
		vec3 r = reflect(-to_eye, az);
		vec3 light = normalize(az + ay * 0.55 - ax * 0.35);
		float spec = pow(max(dot(r, light), 0.0), 40.0);
		float sheen = pow(1.0 - max(l.z, 0.0), 5.0);
		rgb += vec3(0.82, 0.86, 0.92) * pr_glass * (0.05 * sheen + 0.04 * spec);
		return rgb;
	}
	return rgb;
}
