// Samples the two planes of the decoder's NV12 (or P010) frame directly (no conversion pass) and converts Y'CbCr to RGB.
shader_type spatial;
render_mode unshaded, cull_disabled;

// HWVideoTexture.get_plane_texture(0) (Y) and (1) (interleaved CbCr, half size). Like Texture2DRD, R8 reads as luminance
// (r = g = b = Y) and R8G8 as luminance + alpha, so Cb is in .r and Cr in .a.
uniform sampler2D y_tex : filter_linear, repeat_disable;
uniform sampler2D uv_tex : filter_linear, repeat_disable;
// Visible rectangle in UV of the decoded buffer (xy = offset, zw = size). The decoder pads the height to a multiple of
// 32 lines (3840x1080 comes back as 3840x1088), and those lines must not show.
uniform vec4 visible_rect = vec4(0.0, 0.0, 1.0, 1.0);
// 0: mono, the whole frame to both eyes. 1: full side-by-side 3D, the left half to view 0 (the left eye, and the flat
// camera) and the right half to view 1.
uniform int stereo_mode = 0;
// Video is almost always limited range (Y 16-235, CbCr 16-240). Set for full-range (JPEG-style) sources.
uniform bool full_range = false;
// HWVideoTexture.get_packing(). 0: NV12 planes as above. 1 and 2: Q10C (10-bit, experimental): every texel is a 32-bit word
// holding three 10-bit samples (bits 0-9, 10-19, 20-29), read as RGBA8 bytes (1) or as RGB10A2 (2); the Y plane has W/3
// texels per row, the CbCr plane holds Cb0 Cr0 Cb1 Cr1 ... in the same packing at half height. Sampled nearest.
// 3: P010 (10-bit, linear): Y as R16 (.r) and CbCr as R16G16 (.rg), each sample's 10 bits in the high bits of 16.
uniform int packing = 0;
// Y'CbCr to R'G'B' matrix, from MediaSource.get_video_info(): 0 BT.709, 1 BT.2020 (non-constant luminance), 2 BT.601.
uniform int matrix = 0;
// HDR to SDR, from MediaSource.get_tone_mapping() (main.gd's _set_colour()): 0 SDR, 1 PQ, 2 HLG. The R'G'B' values go
// to light in nits, through the gamut matrix to BT.709, then the BT.2390 EETF on the brightest channel (as a ratio, so
// the hue stays) brings the source peak down to the target peak, which is shown as white.
uniform int hdr_transfer = 0;
uniform mat3 gamut = mat3(1.0);
uniform bool tone_mapping = false;
uniform float source_min_pq = 0.0;
uniform float source_max_pq = 0.75;
uniform float max_luminance = 1.0;
uniform float knee_start = 1.0;
uniform float target_peak_nits = 203.0;
uniform float hlg_system_gamma = 1.2;
// HWVideoTexture.get_decoded_size(): the frame in samples (needed to unpack Q10C).
uniform vec2 frame_size = vec2(1.0);

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// SMPTE ST 2084 (the constants are MediaSource.get_tone_mapping()'s pq_m1 ... pq_c3).
const float PQ_M1 = 0.1593017578125;
const float PQ_M2 = 78.84375;
const float PQ_C1 = 0.8359375;
const float PQ_C2 = 18.8515625;
const float PQ_C3 = 18.6875;

vec3 pq_to_nits(vec3 e) {
	vec3 p = pow(clamp(e, 0.0, 1.0), vec3(1.0 / PQ_M2));
	return 10000.0 * pow(max(p - PQ_C1, 0.0) / (PQ_C2 - PQ_C3 * p), vec3(1.0 / PQ_M1));
}

float nits_to_pq(float nits) {
	float y = pow(clamp(nits / 10000.0, 0.0, 1.0), PQ_M1);
	return pow((PQ_C1 + PQ_C2 * y) / (1.0 + PQ_C3 * y), PQ_M2);
}

// BT.2100 HLG to display light on a 1000 nit display (system gamma on the BT.2020 luminance).
vec3 hlg_to_nits(vec3 e) {
	e = clamp(e, 0.0, 1.0);
	vec3 scene = mix(e * e / 3.0, (exp((e - 0.55991073) / 0.17883277) + 0.28466892) / 12.0, step(vec3(0.5), e));
	float y = dot(scene, vec3(0.2627, 0.6780, 0.0593));
	return scene * 1000.0 * pow(max(y, 1e-6), hlg_system_gamma - 1.0);
}

vec3 hdr_to_linear(vec3 rgb) {
	vec3 nits = hdr_transfer == 1 ? pq_to_nits(rgb) : hlg_to_nits(rgb);
	nits = max(gamut * nits, 0.0);
	float brightest = max(nits.r, max(nits.g, nits.b));
	if (tone_mapping && brightest > 0.0) {
		float e = clamp((nits_to_pq(brightest) - source_min_pq) / (source_max_pq - source_min_pq), 0.0, 1.0);
		if (e > knee_start) {
			float t = (e - knee_start) / (1.0 - knee_start);
			float t2 = t * t;
			float t3 = t2 * t;
			e = (2.0 * t3 - 3.0 * t2 + 1.0) * knee_start + (t3 - 2.0 * t2 + t) * (1.0 - knee_start) + (-2.0 * t3 + 3.0 * t2) * max_luminance;
		}
		nits *= pq_to_nits(vec3(e * (source_max_pq - source_min_pq) + source_min_pq)).r / brightest;
	}
	return min(nits / target_peak_nits, 1.0);
}

// Sample i (0-based, along the row) of row y of a TP10 plane, in 0..1 of the 10-bit range.
float tp10_sample(sampler2D tex, int i, int y) {
	int word = i / 3;
	int k = i - word * 3;
	vec4 c = texelFetch(tex, ivec2(word, y), 0);
	if (packing == 2) {
		return k == 0 ? c.r : (k == 1 ? c.g : c.b);
	}
	uvec4 b = uvec4(round(c * 255.0));
	uint w = b.r | (b.g << 8u) | (b.b << 16u) | (b.a << 24u);
	return float((w >> uint(10 * k)) & 1023u) / 1023.0;
}

void fragment() {
	vec4 rect = visible_rect;
	if (stereo_mode == 1) {
		rect.z *= 0.5;
		if (VIEW_INDEX == VIEW_RIGHT) {
			rect.x += rect.z;
		}
	}
	// Keep the bilinear footprint inside the rectangle: half a chroma texel (one luma texel) from its edges, so neither
	// the padding nor the other eye's half bleeds in.
	vec2 margin = (packing == 0 || packing == 3) ? 0.5 / vec2(textureSize(uv_tex, 0)) : 1.0 / frame_size;
	vec2 uv = clamp(rect.xy + UV * rect.zw, rect.xy + margin, rect.xy + rect.zw - margin);

	float y;
	vec2 cbcr;
	if (packing == 0) {
		y = texture(y_tex, uv).r;
		cbcr = texture(uv_tex, uv).ra;
	} else if (packing == 3) {
		// 16-bit codes to the 8-bit scale used below: (v << 6) / 65535 * 65535 / 65280 = v / 1020 (64-940 becomes 16-235).
		float scale = 65535.0 / 65280.0;
		y = texture(y_tex, uv).r * scale;
		cbcr = texture(uv_tex, uv).rg * scale;
	} else {
		ivec2 p = ivec2(uv * frame_size);
		ivec2 c = p / 2;
		// 10-bit codes to the 8-bit scale used below (64-940 limited range becomes 16-235).
		float scale = 1023.0 / 1020.0;
		y = tp10_sample(y_tex, p.x, p.y) * scale;
		cbcr = vec2(tp10_sample(uv_tex, 2 * c.x, c.y), tp10_sample(uv_tex, 2 * c.x + 1, c.y)) * scale;
	}

	if (full_range) {
		cbcr -= 128.0 / 255.0;
	} else {
		y = (y - 16.0 / 255.0) * (255.0 / 219.0);
		cbcr = (cbcr - 128.0 / 255.0) * (255.0 / 224.0);
	}

	// R = Y + 2 (1 - Kr) Cr, B = Y + 2 (1 - Kb) Cb, G = (Y - Kr R - Kb B) / (1 - Kr - Kb).
	vec2 k = matrix == 1 ? vec2(0.2627, 0.0593) : (matrix == 2 ? vec2(0.299, 0.114) : vec2(0.2126, 0.0722));
	float r = y + 2.0 * (1.0 - k.x) * cbcr.y;
	float b = y + 2.0 * (1.0 - k.y) * cbcr.x;
	vec3 rgb = vec3(r, (y - k.x * r - k.y * b) / (1.0 - k.x - k.y), b);

	if (hdr_transfer != 0) {
		ALBEDO = hdr_to_linear(rgb);
	} else {
		// The result is gamma-encoded; ALBEDO is linear. The sRGB curve stands in for BT.709/BT.1886 here.
		ALBEDO = srgb_to_linear(clamp(rgb, 0.0, 1.0));
	}
}
