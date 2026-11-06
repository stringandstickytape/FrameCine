// The video's picture, shared by video.gdshader (the screen) and video_reflection.gdshader (its reflection on the
// floor, ideas #62): every uniform the app sets on the screen's material, and video_pixel(), which returns the
// gamma-encoded RGB of the picture at a position inside one eye's picture for a view. Included, not a shader itself.

// Plane 0 (Y) and plane 1 (interleaved CbCr, half size). Like Texture2DRD, R8 reads as luminance (r = g = b = Y) and
// R8G8 as luminance + alpha, so Cb is in .r and Cr in .a. The desktop test source writes the same layout.
uniform sampler2D y_tex : filter_linear, repeat_disable;
uniform sampler2D uv_tex : filter_linear, repeat_disable;
// 10-bit frames (HWVideoTexture.PACKING_P010: a driver's P010, or Q10C written out as P010-like planes): Y as R16
// (.r) and CbCr as R16G16 (.rg, not .ra), each sample's 10 bits in the high 6+10 of 16, so the codes are scaled to the
// 8-bit range the maths below uses (64-940 becomes 16-235). Reading .ra here put Cr at 1.0: a red picture (seen on the headset, 2026-10-31).
uniform bool p010 = false;
// Visible rectangle in UV of the decoded buffer (xy = offset, zw = size): the decoder pads the height to 32 lines.
uniform vec4 visible_rect = vec4(0.0, 0.0, 1.0, 1.0);
// 0: mono (the whole frame to both eyes). 1: side by side, left half = left eye. 2: top/bottom, top = left eye.
// Half-width / half-height (anamorphic) layouts sample the same rectangles; only the screen's aspect differs.
uniform int stereo_layout = 0;
// Right eye first (e.g. cross-view or some dual-fisheye cameras).
uniform bool swap_eyes = false;
// -1: the eye of the view being rendered (VIEW_INDEX). 0 / 1: force the left / right eye (desktop screenshots;
// a flat camera is always view 0).
uniform int force_eye = -1;
// Fisheye: black outside the image circle (the polar mesh ends at the circle; this trims the last ring).
uniform bool circle_mask = false;
// Video is almost always limited range (Y 16-235, CbCr 16-240).
uniform bool full_range = false;
// Dims the picture (e.g. while the menu is open).
uniform float brightness = 1.0;
// A captured window (WindowVideoSource): one RGB texture with sRGB-encoded values in a UNORM format. The colour comes
// from rgb_tex and the YUV matrix is skipped; the projection, stereo layout, visible rectangle and sRGB decode apply.
uniform bool rgb_source = false;
uniform sampler2D rgb_tex : filter_linear, repeat_disable;
// The stick pointer's cursor on a captured window (scripts/window_pointer.gd, scripts/video/stick_cursor.gd): the
// capture has no cursor in it, so this draws one into the picture itself, where the film layer can't hide it (a quad
// in front of the screen would be covered by the layer). cursor_px is its centre in window pixels (the texture's);
// cursor_alpha 0 hides it (the default, and always for video). A white ring with a dark edge either side and a dot in
// the middle, so it shows on light and dark pages; cursor_radius is the ring's radius in window pixels.
uniform vec2 cursor_px = vec2(-1000.0);
uniform float cursor_alpha = 0.0;
uniform float cursor_radius = 11.0;
// 3D depth (scripts/play/stereo_depth.gd): each view's picture moves sideways by half of this, in opposite directions,
// as a fraction of one eye's width. > 0 moves the left view left and the right view right, so the picture sits
// further away; < 0 brings it nearer. Stereo layouts only. Outside the picture is black, except in 360 (wrap_x).
uniform float stereo_shift = 0.0;
// 360 degree pictures wrap around horizontally.
uniform bool wrap_x = false;
// Manual zoom and pan (scripts/play/zoom_pan.gd), flat only: the picture is magnified by `zoom` about its centre
// and moved by `pan` (fractions of the eye's picture); what falls outside the screen is cut, uncovered parts are black.
uniform float zoom = 1.0;
uniform vec2 pan = vec2(0.0);
// 2D from 3D (scripts/play/two_d.gd): -1 off; 0 / 1: both views show the left / right eye's picture (before the
// swap, so "left" means the left eye as the file intends). The depth shift is off then.
uniform int mono_eye = -1;
// Edge fade (scripts/play/edge_fade.gd): the picture fades to black over this fraction of the screen's width at the
// left and right edges (and half of it at the top and bottom), against window violations in 3D. 0 = off.
uniform float edge_fade = 0.0;
// Picture controls (scripts/play/picture_controls.gd), on the gamma-encoded RGB, in this order: dark-scene lift,
// gamma, contrast around mid grey, brightness, saturation. pc_enabled skips them all at the defaults.
uniform bool pc_enabled = false;
// Raises the shadows, most at a third of full scale, by up to this much; black and white stay put.
uniform float pc_lift = 0.0;
uniform float pc_gamma = 1.0;
uniform float pc_contrast = 1.0;
uniform float pc_brightness = 0.0;
uniform float pc_saturation = 1.0;
// Light sharpen (ideas #90, picture controls' "sharpen"): an unsharp mask on the picture's own pixels (luma for video,
// the colour for a window or picture), 0..1; 0 skips it (four more samples when on).
uniform float pc_sharpen = 0.0;
// Deinterlace (ideas #95, scripts/play/deinterlace.gd): 0 off; 1 bob: the shown field's lines, the other field's lines
// interpolated between their neighbours; 2 edge: those interpolated along the best of three directions (diagonals
// stay smooth). `field` is the field shown now (0: the even lines, 1: the odd ones), alternated at twice the frame
// rate by the script.
uniform int deinterlace = 0;
uniform int field = 0;
// Projector mode (ideas #92, scripts/env/projector.gd), for old releases: film grain (0..1, monochrome, strongest in
// the mid-tones, a new pattern every frame from grain_seed) and gate weave (the picture's small unsteady drift in the
// projector's gate, as a fraction of the picture, set per frame by the script). 0 and (0, 0) skip them.
uniform float film_grain = 0.0;
uniform float grain_seed = 0.0;
uniform vec2 film_weave = vec2(0.0);
// Colour description of the file (scripts/play/hdr_tone_map.gd sets these from the source's video info).
// Y'CbCr matrix: 0 BT.709, 1 BT.601, 2 BT.2020 (non-constant luminance).
uniform int yuv_matrix = 0;
// 0: SDR (the sRGB curve stands in for BT.709 / BT.1886). 1: PQ (SMPTE ST 2084, HDR10). 2: HLG (ARIB STD-B67).
uniform int transfer = 0;
// BT.2020 primaries: converted to BT.709 in linear light (out-of-gamut colours clip).
uniform bool primaries_bt2020 = false;
// 1: Dolby Vision profile 5 (no HDR10 base): the planes hold I, P and T of Dolby's IPT-PQ-c2 signal, not Y'CbCr. The
// app sets transfer 1 and primaries_bt2020 with it; yuv_matrix is not used then.
uniform int dovi = 0;
// HDR to the display (ideas #85): linear light with 1.0 = reference white (203 nits, BT.2408), times tm_exposure;
// colours whose brightest channel is above tm_knee are compressed so that the content's peak (tm_peak, in reference
// whites) lands on display white. Hue is kept (the three channels scale together). Off: highlights clip.
uniform bool tm_enabled = true;
uniform float tm_peak = 4.93;
uniform float tm_exposure = 1.0;
uniform float tm_knee = 0.75;
// tm_curve 1: the BT.2390 EETF with MediaSource.get_tone_mapping()'s parameters (engine builds that have it). On the
// brightest channel, in PQ: the source's range [tm_src_min_pq, tm_src_max_pq] normalised to 0..1, a Hermite spline
// above tm_knee_start bringing the source's peak down to tm_max_lum (the target peak in the same scale), then back
// to nits, shown with tm_target_nits as display white. tm_curve 0: tone_map() below.
uniform int tm_curve = 0;
uniform float tm_src_min_pq = 0.0;
uniform float tm_src_max_pq = 0.75;
uniform float tm_max_lum = 1.0;
uniform float tm_knee_start = 1.0;
uniform float tm_target_nits = 203.0;

const float REF_WHITE_NITS = 203.0;
// Linear BT.2020 RGB -> linear BT.709 RGB (columns).
const mat3 BT2020_TO_BT709 = mat3(
		vec3(1.6605, -0.1246, -0.0182),
		vec3(-0.5876, 1.1329, -0.1006),
		vec3(-0.0728, -0.0083, 1.1187));

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 linear_to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

// Dolby Vision profile 5 (IPT-PQ-c2): I'P'T' (P and T centred on 0) to PQ-encoded LMS, the RPU's ycc_to_rgb_matrix
// (the same in every profile 5 file seen), and linear LMS to linear BT.2020 RGB. The second was fitted against the
// HDR10 base of the same master (a profile 8 encode of the same film: five frames, 5445 block means, median error
// 0.8 %, 90th percentile 2.8 %); the published IPT and BT.2100 LMS matrices, with or without the RPU's 2 %
// crosstalk, were 5 % out. Column-major.
const mat3 DOVI_IPT_TO_LMS = mat3(
		vec3(1.0, 1.0, 1.0),
		vec3(0.09753418, -0.11389160, 0.03259277),
		vec3(0.20520020, 0.13317871, -0.67687988));
const mat3 DOVI_LMS_TO_RGB = mat3(
		vec3(3.14443, -0.79663, -0.06416),
		vec3(-2.23166, 1.90617, -0.02069),
		vec3(0.09499, -0.10497, 1.10503));

// PQ signal -> absolute luminance in nits.
vec3 pq_to_nits(vec3 e) {
	vec3 p = pow(clamp(e, 0.0, 1.0), vec3(1.0 / 78.84375));
	return 10000.0 * pow(max(p - 0.8359375, 0.0) / (18.8515625 - 18.6875 * p), vec3(1.0 / 0.1593017578125));
}

// HLG signal -> display luminance in nits on a 1000 nit reference display (inverse OETF, then the OOTF, gamma 1.2).
vec3 hlg_to_nits(vec3 e) {
	e = clamp(e, 0.0, 1.0);
	vec3 s = mix(e * e / 3.0, (exp((e - 0.55991073) / 0.17883277) + 0.28466892) / 12.0, step(vec3(0.5), e));
	float ys = dot(s, vec3(0.2627, 0.6780, 0.0593));
	return 1000.0 * pow(max(ys, 1e-6), 0.2) * s;
}

// Absolute luminance in nits -> PQ signal.
float nits_to_pq(float nits) {
	float y = pow(clamp(nits / 10000.0, 0.0, 1.0), 0.1593017578125);
	return pow((0.8359375 + 18.8515625 * y) / (1.0 + 18.6875 * y), 78.84375);
}

// BT.2390 EETF (tm_curve 1): linear light in reference whites in, display linear (1.0 = tm_target_nits) out. The three
// channels scale together, so the hue is kept. Off: no compression, highlights clip at the target.
vec3 eetf(vec3 lin) {
	vec3 nits = lin * REF_WHITE_NITS;
	float b = max(max(nits.r, nits.g), nits.b);
	if (!tm_enabled || b <= 0.0) {
		return nits / tm_target_nits;
	}
	float range = max(tm_src_max_pq - tm_src_min_pq, 1e-6);
	float e = clamp((nits_to_pq(b) - tm_src_min_pq) / range, 0.0, 1.0);
	if (e > tm_knee_start) {
		float t = (e - tm_knee_start) / (1.0 - tm_knee_start);
		float t2 = t * t;
		float t3 = t2 * t;
		e = (2.0 * t3 - 3.0 * t2 + 1.0) * tm_knee_start + (t3 - 2.0 * t2 + t) * (1.0 - tm_knee_start)
				+ (-2.0 * t3 + 3.0 * t2) * tm_max_lum;
	}
	float mapped = pq_to_nits(vec3(e * range + tm_src_min_pq)).r;
	return nits * (mapped / b) / tm_target_nits;
}

// Extended Reinhard on the part above the knee: slope 1 at the knee, tm_peak -> 1.0, monotonic.
vec3 tone_map(vec3 c) {
	c *= tm_exposure;
	float peak = tm_peak * tm_exposure;
	float m = max(max(c.r, c.g), c.b);
	if (!tm_enabled || m <= tm_knee || peak <= 1.0) {
		return c;
	}
	float d = 1.0 - tm_knee;
	float u = (m - tm_knee) / d;
	float uw = (peak - tm_knee) / d;
	float mapped = tm_knee + d * u * (1.0 + u / (uw * uw)) / (1.0 + u);
	return c * (mapped / m);
}

// Filtering by footprint (the picture shrunk on the display: an 8K 360 frame has about twice the texels a degree the
// eye image has, a 4K flat film on a 60° screen six times): one bilinear sample skips texels then, and fine detail
// shimmers and drops out (stars in a still 4K frame). video_pixel_filtered() is given the screen pixel's footprint in
// the eye's picture (its UV's derivatives) and averages a grid of bilinear samples across it, up to footprint_taps
// along each axis, separately for luma and the half-size chroma; no more than one sample where the picture is near
// 1:1 or stretched. No mipmaps: the decoder's frames are imported as they are, and building a chain per frame would
// cost the bandwidth this saves. The samples lie close together, so most come from the texture cache. Where the eye
// image is coarser (the foveated edge), each pixel covers more texels and is filtered more, as it should be.
// 1 turns it off (one sample, as video_pixel()).
uniform int footprint_taps = 3;

// Deband (picture controls' "Smooth banding", pc_deband 0..1; 8-bit sources only): 8-bit video shows steps in dark
// gradients, worst in a dark room on an LCD. Each pixel is compared with four samples up to DEBAND_RADIUS texels away
// (for 1080 lines; the bands of a taller frame are as much wider, so the radius grows with it, up to 3 times) at a
// random turn (two pairs at right angles); where all four lie within the threshold (up to DEBAND_THRESHOLD code
// values at full strength) it takes their mean, fading back to itself as they part, so a real edge is left alone.
// Luma and chroma apart. The step that remains is broken up by a dither at the output (dither(), video.gdshader and
// video_layer.gdshader), which is what hides the bands; the mean only spreads them.
uniform float pc_deband = 0.5;
const float DEBAND_RADIUS = 16.0;
const float DEBAND_THRESHOLD = 3.0 / 255.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// The deband's offsets for the texel under uv (size: the plane's), fixed per texel.
vec2 deband_offset(vec2 uv, vec2 size) {
	vec2 cell = floor(uv * size);
	float a = hash12(cell) * 6.2831853;
	float r = (0.5 + 0.5 * hash12(cell + 17.31)) * DEBAND_RADIUS * clamp(size.y / 1080.0, 1.0, 3.0);
	return vec2(cos(a), sin(a)) * r / size;
}

// How much of the four samples' mean to take, from how far the furthest is from the pixel.
float deband_weight(float spread) {
	float t = DEBAND_THRESHOLD * pc_deband;
	return 1.0 - smoothstep(0.5 * t, t, spread);
}

// Triangular noise of one output code value, new each frame: the dither after a deband.
float dither(vec2 frag, float time) {
	vec2 seed = floor(frag) + fract(time * 7.123) * 113.0;
	return (hash12(seed) + hash12(seed + 71.7) - 1.0) / 255.0;
}

// Taps along one axis for a footprint `texels` long: one up to a quarter past 1:1 (a bilinear sample covers that).
int footprint_taps_for(float texels) {
	return clamp(int(ceil(texels - 0.25)), 1, max(footprint_taps, 1));
}

// The cursor over rgb at uv (the texture's UV); aa: a screen pixel's size in texels (0 or 1 when drawn 1:1).
vec3 draw_cursor(vec3 rgb, vec2 uv, float aa) {
	vec2 d = uv * vec2(textureSize(rgb_tex, 0)) - cursor_px;
	float r = length(d);
	float e = max(aa, 1.0);
	float ring = abs(r - cursor_radius);
	float white = max(1.0 - smoothstep(1.5, 1.5 + e, ring), 1.0 - smoothstep(1.5, 1.5 + e, r));
	float dark = max(1.0 - smoothstep(3.2, 3.2 + e, ring), 1.0 - smoothstep(3.2, 3.2 + e, r));
	rgb = mix(rgb, vec3(0.04), dark * 0.85 * cursor_alpha);
	return mix(rgb, vec3(1.0), white * cursor_alpha);
}

// The planes' samples on the 8-bit scale, whatever the packing (see p010).
const float P010_SCALE = 65535.0 / 65280.0;
float read_y(vec2 uv) {
	float v = textureLod(y_tex, uv, 0.0).r;
	return p010 ? v * P010_SCALE : v;
}
vec2 read_cbcr(vec2 uv) {
	vec4 c = textureLod(uv_tex, uv, 0.0);
	return p010 ? c.rg * P010_SCALE : c.ra;
}

// Luma at uv for a deinterlaced picture: the shown field's line, or the other field's line rebuilt from the shown
// field's lines above and below it.
float field_luma(vec2 uv) {
	vec2 size = vec2(textureSize(y_tex, 0));
	float row = floor(uv.y * size.y);
	if (int(mod(row, 2.0)) == field) {
		return read_y(vec2(uv.x, (row + 0.5) / size.y));
	}
	float up = (row - 0.5) / size.y;
	float down = (row + 1.5) / size.y;
	if (deinterlace == 1) {
		return 0.5 * (read_y(vec2(uv.x, up)) + read_y(vec2(uv.x, down)));
	}
	// Edge-directed: of left-down, straight down and right-down, the direction whose two ends agree best.
	float dx = 1.0 / size.x;
	float best = 0.0;
	float best_diff = 10.0;
	for (int d = -1; d <= 1; d++) {
		float a = read_y(vec2(uv.x + float(d) * dx, up));
		float b = read_y(vec2(uv.x - float(d) * dx, down));
		float diff = abs(a - b) + (d == 0 ? 0.0 : 0.02);
		if (diff < best_diff) {
			best_diff = diff;
			best = 0.5 * (a + b);
		}
	}
	return best;
}

// Chroma for a deinterlaced picture: the shown field's chroma line, or the mean of its neighbours.
vec2 field_chroma(vec2 uv) {
	vec2 size = vec2(textureSize(uv_tex, 0));
	float row = floor(uv.y * size.y);
	if (int(mod(row, 2.0)) == field) {
		return read_cbcr(vec2(uv.x, (row + 0.5) / size.y));
	}
	return 0.5 * (read_cbcr(vec2(uv.x, (row - 0.5) / size.y))
			+ read_cbcr(vec2(uv.x, (row + 1.5) / size.y)));
}

// A plane's mean over a screen pixel's footprint (duv_dx, duv_dy: the frame UV's derivatives), each sample kept
// inside [lo, hi]. which: 0 luma, 1 chroma, 2 the RGB source's.
vec4 footprint_mean(int which, vec2 uv, vec2 duv_dx, vec2 duv_dy, vec2 lo, vec2 hi) {
	vec2 size = vec2(which == 0 ? textureSize(y_tex, 0) : (which == 1 ? textureSize(uv_tex, 0) : textureSize(rgb_tex, 0)));
	int kx = footprint_taps_for(length(duv_dx * size));
	int ky = footprint_taps_for(length(duv_dy * size));
	vec4 sum = vec4(0.0);
	for (int i = 0; i < kx; i++) {
		for (int j = 0; j < ky; j++) {
			vec2 o = ((float(i) + 0.5) / float(kx) - 0.5) * duv_dx + ((float(j) + 0.5) / float(ky) - 0.5) * duv_dy;
			vec2 q = clamp(uv + o, lo, hi);
			if (which == 0) {
				sum.r += read_y(q);
			} else if (which == 1) {
				sum.rg += read_cbcr(q);
			} else {
				sum.rgb += textureLod(rgb_tex, q, 0.0).rgb;
			}
		}
	}
	return sum / float(kx * ky);
}

// The picture at mesh_uv (the position inside ONE EYE's picture, 0..1) for view_index (VIEW_INDEX), gamma-encoded,
// with zoom / pan, depth shift, stereo layout, masks, picture controls and the edge fade applied, filtered over the
// screen pixel's footprint: mesh_dx, mesh_dy are mesh_uv's derivatives (dFdx, dFdy), taken by the caller in uniform
// control flow (the dual fisheye seam picks its UV in a branch). Zero derivatives: one sample.
vec3 video_pixel_filtered(vec2 mesh_uv, vec2 mesh_dx, vec2 mesh_dy, int view_index) {
	int view = force_eye >= 0 ? force_eye : view_index;
	int src_view = mono_eye >= 0 ? mono_eye : view;
	int eye = swap_eyes ? 1 - src_view : src_view;
	// Position inside one eye's picture, after the per-view shift.
	vec2 p = mesh_uv;
	if (stereo_layout != 0 && mono_eye < 0) {
		p.x += (view == 0 ? 0.5 : -0.5) * stereo_shift;
	}
	p = (p - 0.5) / zoom + 0.5 + pan + film_weave;
	bool outside = false;
	if (wrap_x) {
		p.x = fract(p.x);
	} else {
		outside = p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0;
	}
	vec4 rect = visible_rect;
	if (stereo_layout == 1) {
		rect.z *= 0.5;
		rect.x += rect.z * float(eye);
	} else if (stereo_layout == 2) {
		rect.w *= 0.5;
		rect.y += rect.w * float(eye);
	}
	// Keep the bilinear footprint inside the eye's rectangle: half a chroma texel (one luma texel) from its edges, so
	// neither the padding nor the other eye's half bleeds in.
	vec2 margin = 0.5 / vec2(rgb_source ? textureSize(rgb_tex, 0) : textureSize(uv_tex, 0));
	vec2 lo = rect.xy + margin;
	vec2 hi = rect.xy + rect.zw - margin;
	vec2 uv = clamp(rect.xy + p * rect.zw, lo, hi);
	// The footprint in the frame: the mesh UV's derivatives through the zoom and the eye's rectangle (the wrap of a
	// 360 frame is taken after, so its seam doesn't look like a huge footprint).
	vec2 duv_dx = mesh_dx / zoom * rect.zw;
	vec2 duv_dy = mesh_dy / zoom * rect.zw;
	bool filtered = footprint_taps > 1 && deinterlace == 0 && (mesh_dx != vec2(0.0) || mesh_dy != vec2(0.0));

	vec3 rgb;
	if (rgb_source) {
		rgb = filtered ? footprint_mean(2, uv, duv_dx, duv_dy, lo, hi).rgb : textureLod(rgb_tex, uv, 0.0).rgb;
		if (pc_sharpen > 0.0) {
			vec2 t = 1.0 / vec2(textureSize(rgb_tex, 0));
			vec3 n = textureLod(rgb_tex, uv + vec2(t.x, 0.0), 0.0).rgb + textureLod(rgb_tex, uv - vec2(t.x, 0.0), 0.0).rgb
					+ textureLod(rgb_tex, uv + vec2(0.0, t.y), 0.0).rgb + textureLod(rgb_tex, uv - vec2(0.0, t.y), 0.0).rgb;
			rgb += pc_sharpen * (rgb - 0.25 * n);
		}
	} else {
		float y;
		vec2 cbcr;
		if (deinterlace > 0) {
			y = field_luma(uv);
			cbcr = field_chroma(uv);
		} else if (filtered) {
			y = footprint_mean(0, uv, duv_dx, duv_dy, lo, hi).r;
			cbcr = footprint_mean(1, uv, duv_dx, duv_dy, lo, hi).rg;
		} else {
			y = read_y(uv);
			cbcr = read_cbcr(uv);
		}
		if (pc_deband > 0.0 && !p010 && deinterlace == 0) {
			vec2 o = deband_offset(uv, vec2(textureSize(y_tex, 0)));
			vec2 o2 = vec2(-o.y, o.x);
			vec4 s = vec4(read_y(clamp(uv + o, lo, hi)), read_y(clamp(uv - o, lo, hi)),
					read_y(clamp(uv + o2, lo, hi)), read_y(clamp(uv - o2, lo, hi)));
			vec4 d = abs(s - y);
			y = mix(y, dot(s, vec4(0.25)), deband_weight(max(max(d.x, d.y), max(d.z, d.w))));
			// Chroma: the same offsets in the frame (the same UV), on its own half-size plane.
			vec2 oc = o;
			vec2 oc2 = vec2(-oc.y, oc.x);
			vec2 c0 = read_cbcr(clamp(uv + oc, lo, hi));
			vec2 c1 = read_cbcr(clamp(uv - oc, lo, hi));
			vec2 c2 = read_cbcr(clamp(uv + oc2, lo, hi));
			vec2 c3 = read_cbcr(clamp(uv - oc2, lo, hi));
			vec2 dc = max(max(abs(c0 - cbcr), abs(c1 - cbcr)), max(abs(c2 - cbcr), abs(c3 - cbcr)));
			cbcr = mix(cbcr, 0.25 * (c0 + c1 + c2 + c3), deband_weight(max(dc.x, dc.y)));
		}
		if (pc_sharpen > 0.0) {
			vec2 t = 1.0 / vec2(textureSize(y_tex, 0));
			float n = read_y(uv + vec2(t.x, 0.0)) + read_y(uv - vec2(t.x, 0.0))
					+ read_y(uv + vec2(0.0, t.y)) + read_y(uv - vec2(0.0, t.y));
			y += pc_sharpen * (y - 0.25 * n);
		}
		if (full_range) {
			cbcr -= 128.0 / 255.0;
		} else {
			y = (y - 16.0 / 255.0) * (255.0 / 219.0);
			cbcr = (cbcr - 128.0 / 255.0) * (255.0 / 224.0);
		}
		if (yuv_matrix == 2) {
			// BT.2020 (Kr = 0.2627, Kb = 0.0593).
			rgb = vec3(
					y + 1.4746 * cbcr.y,
					y - 0.164553 * cbcr.x - 0.571353 * cbcr.y,
					y + 1.8814 * cbcr.x);
		} else if (yuv_matrix == 1) {
			// BT.601 (Kr = 0.299, Kb = 0.114).
			rgb = vec3(
					y + 1.402 * cbcr.y,
					y - 0.344136 * cbcr.x - 0.714136 * cbcr.y,
					y + 1.772 * cbcr.x);
		} else {
			// BT.709 (Kr = 0.2126, Kb = 0.0722).
			rgb = vec3(
					y + 1.5748 * cbcr.y,
					y - 0.1873 * cbcr.x - 0.4681 * cbcr.y,
					y + 1.8556 * cbcr.x);
		}
		if (transfer != 0 || primaries_bt2020) {
			// To linear light (1.0 = reference white), BT.709 primaries, tone mapped, and back to the gamma-encoded
			// values the rest of the shader works on.
			vec3 lin;
			if (dovi == 1) {
				// The RPU's reshaping curves are not read: the files seen carry the limited-to-full range expansion
				// only, which the range step above has done.
				vec3 lms = pq_to_nits(DOVI_IPT_TO_LMS * vec3(y, cbcr));
				lin = DOVI_LMS_TO_RGB * lms / REF_WHITE_NITS;
			} else if (transfer == 1) {
				lin = pq_to_nits(rgb) / REF_WHITE_NITS;
			} else if (transfer == 2) {
				lin = hlg_to_nits(rgb) / REF_WHITE_NITS;
			} else {
				lin = srgb_to_linear(clamp(rgb, 0.0, 1.0));
			}
			if (primaries_bt2020) {
				lin = max(BT2020_TO_BT709 * lin, vec3(0.0));
			}
			if (transfer != 0) {
				lin = tm_curve == 1 ? eetf(lin) : tone_map(lin);
			}
			rgb = linear_to_srgb(clamp(lin, 0.0, 1.0));
		}
	}
	if (pc_enabled) {
		rgb = clamp(rgb, 0.0, 1.0);
		rgb += pc_lift * 6.75 * rgb * (1.0 - rgb) * (1.0 - rgb);
		rgb = pow(rgb, vec3(1.0 / pc_gamma));
		rgb = (rgb - 0.5) * pc_contrast + 0.5 + pc_brightness;
		float luma = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
		rgb = mix(vec3(luma), rgb, pc_saturation);
	}
	if (film_grain > 0.0) {
		// About two picture pixels per grain, so it reads as film rather than per-pixel noise.
		vec2 cell = floor(p * vec2(rgb_source ? textureSize(rgb_tex, 0) : textureSize(y_tex, 0)) * 0.5);
		float n = fract(sin(dot(cell + grain_seed, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
		float l = clamp(dot(rgb, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
		rgb += n * film_grain * 0.16 * (0.25 + 3.0 * l * (1.0 - l));
	}
	if (rgb_source && cursor_alpha > 0.0) {
		rgb = draw_cursor(rgb, uv, length(duv_dx * vec2(textureSize(rgb_tex, 0))));
	}
	if (outside || (circle_mask && length(p - 0.5) > 0.5)) {
		rgb = vec3(0.0);
	}
	if (edge_fade > 0.0) {
		vec2 e = min(mesh_uv, 1.0 - mesh_uv);
		rgb *= smoothstep(0.0, edge_fade, e.x) * smoothstep(0.0, edge_fade * 0.5, e.y);
	}
	return rgb;
}

// As video_pixel_filtered() with one bilinear sample: the reflection, the magnifier and the film layer's copy (blurred,
// or drawn 1:1). The screen and the crossfade use video_pixel_filtered().
vec3 video_pixel(vec2 mesh_uv, int view_index) {
	return video_pixel_filtered(mesh_uv, vec2(0.0), vec2(0.0), view_index);
}
