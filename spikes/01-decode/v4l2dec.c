/*
 * v4l2dec.c - spike 01: minimal V4L2 stateful M2M decoder client for the Steam Frame.
 *
 * Target: Valve's fork of Qualcomm's iris driver, /dev/video-dec0 (-> /dev/video22), MPLANE API.
 * Feeds a raw Annex-B H.264/HEVC elementary stream (or IVF VP9, only with --allow-vp9), one access
 * unit per OUTPUT buffer, and measures what the decoder does: fps, per-frame latency, formats,
 * SOURCE_CHANGE handling, VIDIOC_EXPBUF on CAPTURE, imported DMABUF CAPTURE, concurrent sessions.
 *
 * Quirks of the fork that this client works around (docs/research-device.md, section 2):
 *   - OUTPUT formats do not set V4L2_FMT_FLAG_DYN_RESOLUTION; we never rely on that flag.
 *   - G_FMT(CAPTURE) reports a 384x256 placeholder until SOURCE_CHANGE; we print it, then ignore it.
 *   - The driver can DMA a full frame into too-small CAPTURE buffers (SMMU fault, SIGSEGV), so
 *     CAPTURE buffers are allocated only after SOURCE_CHANGE, sized from the format reported then,
 *     and are freed and reallocated on every later SOURCE_CHANGE.
 *   - Firmware can crash (0x5000003) on parallel sessions or fast open/close: one open per
 *     session, sessions start staggered, and every poll has a timeout. On a hang we print a
 *     message, STREAMOFF and close; we never kill anything. Do not SIGKILL this process while it
 *     is stuck in an ioctl (it can oops the kernel); Ctrl-C once drains, twice aborts.
 *   - VP9 crashes the firmware on the second session after boot: refused unless --allow-vp9.
 *
 * Access-unit split heuristic (Annex-B): a new AU starts at the first of these NAL units that
 * follows a VCL NAL unit of the current AU:
 *   HEVC: AUD(35) any layer; on nuh_layer_id 0 only: VPS/SPS/PPS(32-34), prefix SEI(39),
 *         41-44, 48-55, or a VCL NAL (0-31) with first_slice_segment_in_pic_flag = 1.
 *         Restricting to layer 0 keeps MV-HEVC layer-1 slices in the same AU as layer 0.
 *   H.264: AUD(9), SEI(6), SPS(7), PPS(8), 15-18, or a slice (1, 2, 5) with first_mb_in_slice = 0
 *         (first bit of the ue(v) is 1). Prefix NAL 14 and MVC slices (20) are not split points,
 *         so SVC/MVC streams are not split correctly. PAFF field pairs become two AUs.
 *   The AU spans from the zero_byte of its first start code to the start of the next AU.
 *   The first SPS is parsed for the coded size and bit depth, which seed S_FMT(OUTPUT).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <inttypes.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <drm/drm.h>
#include <drm/drm_mode.h>
#include <linux/dma-buf.h>
#include <linux/dma-heap.h>
#include <linux/videodev2.h>

#ifndef V4L2_PIX_FMT_QC08C
#define V4L2_PIX_FMT_QC08C v4l2_fourcc('Q', '0', '8', 'C')
#endif
#ifndef V4L2_PIX_FMT_QC10C
#define V4L2_PIX_FMT_QC10C v4l2_fourcc('Q', '1', '0', 'C')
#endif
#ifndef V4L2_PIX_FMT_P010
#define V4L2_PIX_FMT_P010 v4l2_fourcc('P', '0', '1', '0')
#endif
#ifndef V4L2_FMT_FLAG_DYN_RESOLUTION
#define V4L2_FMT_FLAG_DYN_RESOLUTION 0x0008
#endif

#define OUT_TYPE V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE
#define CAP_TYPE V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE
#define MAX_OUT_BUFS 32
#define MAX_CAP_BUFS 64
#define LAT_RING 1024
#define MAX_ERRS 32
#define POLL_SLICE_MS 100

/* ------------------------------------------------------------------------------------------ */
/* options */

enum mem_kind { MEM_MMAP, MEM_DMABUF };
enum dmabuf_src { SRC_HEAP, SRC_DUMB };

static struct opts {
	const char *dev;
	const char *input;
	const char *codec_name;
	uint32_t codec;
	uint32_t cap_fourcc;        /* 0: keep the driver's choice after SOURCE_CHANGE */
	enum mem_kind cap_mem;
	enum dmabuf_src dmabuf_src;
	const char *dmabuf_dev;
	unsigned out_bufs;
	unsigned cap_extra;
	unsigned cap_count;         /* 0: MIN_BUFFERS_FOR_CAPTURE + cap_extra */
	unsigned coded_w, coded_h;  /* 0: from SPS */
	long write_frame;           /* -1: off */
	const char *write_prefix;
	uint64_t max_frames;
	double duration;
	bool loop, realtime, allow_vp9, parse_only;
	double fps;
	double reconfig_rate;       /* queued-rate target before a CAPTURE re-setup; 0: off */
	bool no_restart;            /* no session-restart fallback when a re-setup fails */
	int dump_twice_ms;          /* > 0: dump the -w frame again after this delay */
	double stats_interval;
	int sessions;
	int stagger_ms;
	int timeout_ms;
} o = {
	.dev = "/dev/video-dec0",
	.codec_name = "hevc",
	.codec = V4L2_PIX_FMT_HEVC,
	.cap_mem = MEM_MMAP,
	.dmabuf_src = SRC_HEAP,
	.out_bufs = 8,
	.cap_extra = 4,
	.write_frame = -1,
	.write_prefix = "frame",
	.fps = 60.0,
	.reconfig_rate = 25.0,
	.sessions = 1,
	.stagger_ms = 500,
	.timeout_ms = 5000,
};

static volatile sig_atomic_t g_stop; /* 1: drain and finish, 2+: abort */
static double g_t0;

/* ------------------------------------------------------------------------------------------ */
/* small helpers */

static double mono(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
}

struct fcc_str { char s[8]; };

static struct fcc_str fcc(uint32_t f)
{
	struct fcc_str r;
	for (int i = 0; i < 4; i++) {
		char c = (char)((f >> (8 * i)) & 0xff);
		r.s[i] = (c >= 32 && c < 127) ? c : '.';
	}
	r.s[4] = (f & (1u << 31)) ? '-' : '\0'; /* big-endian flag */
	r.s[5] = (f & (1u << 31)) ? 'B' : '\0';
	r.s[6] = (f & (1u << 31)) ? 'E' : '\0';
	r.s[7] = '\0';
	return r;
}

struct md5 { uint32_t h[4]; uint64_t len; uint8_t buf[64]; size_t n; };

static const uint32_t md5_k[64] = {
	0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
	0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
	0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
	0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
	0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
	0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
	0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
	0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
};
static const uint8_t md5_r[16] = { 7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21 };

static void md5_block(uint32_t h[4], const uint8_t *p)
{
	uint32_t w[16], a = h[0], b = h[1], c = h[2], d = h[3];
	for (int i = 0; i < 16; i++)
		w[i] = (uint32_t)p[4 * i] | (uint32_t)p[4 * i + 1] << 8 | (uint32_t)p[4 * i + 2] << 16 |
		       (uint32_t)p[4 * i + 3] << 24;
	for (int i = 0; i < 64; i++) {
		uint32_t f;
		int g;
		if (i < 16) {
			f = (b & c) | (~b & d);
			g = i;
		} else if (i < 32) {
			f = (d & b) | (~d & c);
			g = (5 * i + 1) % 16;
		} else if (i < 48) {
			f = b ^ c ^ d;
			g = (3 * i + 5) % 16;
		} else {
			f = c ^ (b | ~d);
			g = (7 * i) % 16;
		}
		uint32_t x = a + f + md5_k[i] + w[g], r = md5_r[(i / 16) * 4 + i % 4];
		a = d;
		d = c;
		c = b;
		b += (x << r) | (x >> (32 - r));
	}
	h[0] += a;
	h[1] += b;
	h[2] += c;
	h[3] += d;
}

static void md5_init(struct md5 *m)
{
	*m = (struct md5){ .h = { 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476 } };
}

static void md5_update(struct md5 *m, const uint8_t *p, size_t n)
{
	m->len += n;
	while (n) {
		if (m->n == 0 && n >= 64) {
			md5_block(m->h, p);
			p += 64;
			n -= 64;
			continue;
		}
		size_t k = 64 - m->n < n ? 64 - m->n : n;
		memcpy(m->buf + m->n, p, k);
		m->n += k;
		p += k;
		n -= k;
		if (m->n == 64) {
			md5_block(m->h, m->buf);
			m->n = 0;
		}
	}
}

static void md5_hex(struct md5 *m, char out[33])
{
	uint64_t bits = m->len * 8;
	uint8_t pad[72] = { 0x80 };
	size_t padlen = (m->n < 56 ? 56 : 120) - m->n;
	for (int i = 0; i < 8; i++)
		pad[padlen + (size_t)i] = (uint8_t)(bits >> (8 * i));
	md5_update(m, pad, padlen + 8);
	for (int i = 0; i < 16; i++)
		snprintf(out + 2 * i, 3, "%02x", (m->h[i / 4] >> (8 * (i % 4))) & 0xff);
}

struct acc { double min, max, sum; uint64_t n; };

static void acc_add(struct acc *a, double v)
{
	if (!a->n || v < a->min)
		a->min = v;
	if (!a->n || v > a->max)
		a->max = v;
	a->sum += v;
	a->n++;
}

static double acc_avg(const struct acc *a) { return a->n ? a->sum / (double)a->n : 0.0; }

static pthread_mutex_t g_log_mu = PTHREAD_MUTEX_INITIALIZER;

struct session;
static void logmsg(const struct session *s, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

/* ------------------------------------------------------------------------------------------ */
/* stream: whole file mmapped, split into access units once, shared read-only by all sessions */

/* sps_w/sps_h: coded size of an SPS inside this AU (0: none). Marks where a session restart
 * can resume after a resolution change. */
struct au { uint64_t off; uint32_t len; uint16_t sps_w, sps_h; };

struct sps_info { unsigned width, height, disp_w, disp_h, bit_depth, chroma_format; bool ok; };

struct stream {
	const uint8_t *data;
	size_t size;
	struct au *aus;
	size_t n_aus, cap_aus;
	uint32_t max_au;
	bool sps_parsed;
	unsigned width, height;          /* coded size from SPS (or IVF header) */
	unsigned disp_w, disp_h;         /* after conformance window / frame cropping */
	unsigned bit_depth, chroma_format;
} g_st;

static int push_au(struct stream *st, uint64_t off, uint64_t len, unsigned sps_w, unsigned sps_h)
{
	if (len == 0)
		return 0;
	if (len > UINT32_MAX) {
		fprintf(stderr, "access unit at %" PRIu64 " is %" PRIu64 " bytes; too large\n", off, len);
		return -1;
	}
	if (st->n_aus == st->cap_aus) {
		size_t nc = st->cap_aus ? st->cap_aus * 2 : 4096;
		struct au *n = realloc(st->aus, nc * sizeof(*n));
		if (!n)
			return -1;
		st->aus = n;
		st->cap_aus = nc;
	}
	st->aus[st->n_aus++] = (struct au){ off, (uint32_t)len, (uint16_t)sps_w, (uint16_t)sps_h };
	if (len > st->max_au)
		st->max_au = (uint32_t)len;
	return 0;
}

/* Exp-Golomb bit reader over an RBSP (emulation prevention bytes already removed). */
struct br { const uint8_t *p; size_t n; size_t bit; bool err; };

static uint32_t br_u(struct br *b, int n)
{
	uint32_t v = 0;
	while (n-- > 0) {
		if (b->bit >= b->n * 8) {
			b->err = true;
			return 0;
		}
		v = (v << 1) | ((b->p[b->bit >> 3] >> (7 - (b->bit & 7))) & 1u);
		b->bit++;
	}
	return v;
}

static void br_skip(struct br *b, size_t n)
{
	b->bit += n;
	if (b->bit > b->n * 8)
		b->err = true;
}

static uint32_t br_ue(struct br *b)
{
	int lz = 0;
	while (!br_u(b, 1)) {
		if (b->err || ++lz > 31) {
			b->err = true;
			return 0;
		}
	}
	return lz ? ((1u << lz) - 1u + br_u(b, lz)) : 0;
}

static int32_t br_se(struct br *b)
{
	uint32_t k = br_ue(b);
	return (k & 1) ? (int32_t)((k + 1) / 2) : -(int32_t)(k / 2);
}

static size_t unescape(const uint8_t *src, size_t n, uint8_t *dst, size_t cap)
{
	size_t out = 0;
	int zeros = 0;
	for (size_t i = 0; i < n && out < cap; i++) {
		if (zeros >= 2 && src[i] == 3) {
			zeros = 0;
			continue;
		}
		dst[out++] = src[i];
		zeros = src[i] == 0 ? zeros + 1 : 0;
	}
	return out;
}

static void parse_hevc_sps(struct sps_info *si, const uint8_t *nal, size_t len)
{
	uint8_t buf[512];
	if (len < 3)
		return;
	struct br b = { buf, unescape(nal + 2, len - 2, buf, sizeof(buf)), 0, false };
	br_skip(&b, 4);                         /* sps_video_parameter_set_id */
	unsigned max_sub = br_u(&b, 3);
	br_skip(&b, 1);                         /* sps_temporal_id_nesting_flag */
	br_skip(&b, 88 + 8);                    /* general profile/tier/flags + general_level_idc */
	bool sp[8] = { 0 }, sl[8] = { 0 };
	for (unsigned i = 0; i < max_sub; i++) {
		sp[i] = br_u(&b, 1);
		sl[i] = br_u(&b, 1);
	}
	if (max_sub > 0)
		for (unsigned i = max_sub; i < 8; i++)
			br_skip(&b, 2);
	for (unsigned i = 0; i < max_sub; i++) {
		if (sp[i])
			br_skip(&b, 88);
		if (sl[i])
			br_skip(&b, 8);
	}
	br_ue(&b);                              /* sps_seq_parameter_set_id */
	unsigned chroma = br_ue(&b);
	if (chroma == 3)
		br_skip(&b, 1);                 /* separate_colour_plane_flag */
	unsigned w = br_ue(&b), h = br_ue(&b);
	unsigned cl = 0, cr = 0, ct = 0, cb = 0;
	if (br_u(&b, 1)) {
		cl = br_ue(&b);
		cr = br_ue(&b);
		ct = br_ue(&b);
		cb = br_ue(&b);
	}
	unsigned bd = br_ue(&b) + 8;
	if (b.err || w == 0 || h == 0 || w > 16384 || h > 16384)
		return;
	unsigned sub_w = (chroma == 1 || chroma == 2) ? 2 : 1, sub_h = chroma == 1 ? 2 : 1;
	*si = (struct sps_info){ w, h, w - sub_w * (cl + cr), h - sub_h * (ct + cb), bd, chroma, true };
}

static void h264_skip_scaling_list(struct br *b, int size)
{
	int last = 8, next = 8;
	for (int j = 0; j < size; j++) {
		if (next)
			next = (last + br_se(b) + 256) % 256;
		last = next ? next : last;
	}
}

static void parse_h264_sps(struct sps_info *si, const uint8_t *nal, size_t len)
{
	uint8_t buf[512];
	if (len < 4)
		return;
	struct br b = { buf, unescape(nal + 1, len - 1, buf, sizeof(buf)), 0, false };
	unsigned profile = br_u(&b, 8);
	br_skip(&b, 16);                        /* constraint flags, level_idc */
	br_ue(&b);                              /* seq_parameter_set_id */
	unsigned chroma = 1, bd = 8;
	if (profile == 100 || profile == 110 || profile == 122 || profile == 244 || profile == 44 ||
	    profile == 83 || profile == 86 || profile == 118 || profile == 128 || profile == 138 ||
	    profile == 139 || profile == 134 || profile == 135) {
		chroma = br_ue(&b);
		if (chroma == 3)
			br_skip(&b, 1);
		bd = br_ue(&b) + 8;
		br_ue(&b);                      /* bit_depth_chroma_minus8 */
		br_skip(&b, 1);                 /* qpprime_y_zero_transform_bypass_flag */
		if (br_u(&b, 1)) {              /* seq_scaling_matrix_present_flag */
			for (int i = 0; i < (chroma == 3 ? 12 : 8) && !b.err; i++)
				if (br_u(&b, 1))
					h264_skip_scaling_list(&b, i < 6 ? 16 : 64);
		}
	}
	br_ue(&b);                              /* log2_max_frame_num_minus4 */
	unsigned poc_type = br_ue(&b);
	if (poc_type == 0) {
		br_ue(&b);
	} else if (poc_type == 1) {
		br_skip(&b, 1);
		br_se(&b);
		br_se(&b);
		unsigned n = br_ue(&b);
		for (unsigned i = 0; i < n && i < 256 && !b.err; i++)
			br_se(&b);
	}
	br_ue(&b);                              /* max_num_ref_frames */
	br_skip(&b, 1);                         /* gaps_in_frame_num_value_allowed_flag */
	unsigned wmb = br_ue(&b) + 1, hmu = br_ue(&b) + 1;
	unsigned frame_mbs_only = br_u(&b, 1);
	if (!frame_mbs_only)
		br_skip(&b, 1);
	br_skip(&b, 1);                         /* direct_8x8_inference_flag */
	unsigned cl = 0, cr = 0, ct = 0, cb = 0;
	if (br_u(&b, 1)) {
		cl = br_ue(&b);
		cr = br_ue(&b);
		ct = br_ue(&b);
		cb = br_ue(&b);
	}
	if (b.err || wmb > 1024 || hmu > 1024)
		return;
	unsigned w = wmb * 16, h = (2 - frame_mbs_only) * hmu * 16;
	unsigned cux = (chroma == 1 || chroma == 2) ? 2 : 1;
	unsigned cuy = (chroma == 1 ? 2 : 1) * (2 - frame_mbs_only);
	*si = (struct sps_info){ w, h, w - cux * (cl + cr), h - cuy * (ct + cb), bd, chroma, true };
}

/* Offset of the next 00 00 01 at or after i, or n. */
static size_t next_sc(const uint8_t *p, size_t n, size_t i)
{
	while (i + 3 <= n) {
		if (p[i + 2] > 1)
			i += 3;
		else if (p[i + 2] == 1 && p[i + 1] == 0 && p[i] == 0)
			return i;
		else
			i++;
	}
	return n;
}

static void classify_nal(const uint8_t *q, size_t len, bool *new_au, bool *vcl,
			 struct sps_info *si)
{
	*new_au = *vcl = false;
	si->ok = false;
	if (o.codec == V4L2_PIX_FMT_HEVC) {
		if (len < 2)
			return;
		unsigned type = (q[0] >> 1) & 0x3f;
		unsigned layer = ((q[0] & 1u) << 5) | (q[1] >> 3);
		*vcl = type <= 31;
		if (type == 35)
			*new_au = true;
		else if (layer == 0 && ((type >= 32 && type <= 34) || type == 39 ||
					(type >= 41 && type <= 44) || (type >= 48 && type <= 55)))
			*new_au = true;
		else if (layer == 0 && type <= 31 && len >= 3 && (q[2] & 0x80))
			*new_au = true;
		if (type == 33 && layer == 0)
			parse_hevc_sps(si, q, len);
	} else {
		if (len < 1)
			return;
		unsigned type = q[0] & 0x1f;
		*vcl = type >= 1 && type <= 5;
		if (type == 9 || type == 6 || type == 7 || type == 8 || (type >= 15 && type <= 18))
			*new_au = true;
		else if ((type == 1 || type == 2 || type == 5) && len >= 2 && (q[1] & 0x80))
			*new_au = true;
		if (type == 7)
			parse_h264_sps(si, q, len);
	}
}

static int split_annexb(struct stream *st)
{
	const uint8_t *p = st->data;
	size_t n = st->size;
	size_t sc = next_sc(p, n, 0);
	size_t au_start = SIZE_MAX;
	bool seen_vcl = false;
	unsigned sps_w = 0, sps_h = 0;
	while (sc < n) {
		size_t nal = sc + 3;
		size_t start = (sc > 0 && p[sc - 1] == 0) ? sc - 1 : sc; /* zero_byte of 4-byte code */
		size_t next = next_sc(p, n, nal);
		bool new_au, vcl;
		struct sps_info si;
		classify_nal(p + nal, next - nal, &new_au, &vcl, &si);
		if (au_start == SIZE_MAX) {
			au_start = start;
		} else if (seen_vcl && new_au) {
			if (push_au(st, au_start, start - au_start, sps_w, sps_h))
				return -1;
			au_start = start;
			seen_vcl = false;
			sps_w = sps_h = 0;
		}
		if (si.ok) {
			sps_w = si.width;
			sps_h = si.height;
			if (!st->sps_parsed) {
				st->width = si.width;
				st->height = si.height;
				st->disp_w = si.disp_w;
				st->disp_h = si.disp_h;
				st->bit_depth = si.bit_depth;
				st->chroma_format = si.chroma_format;
				st->sps_parsed = true;
			}
		}
		if (vcl)
			seen_vcl = true;
		sc = next;
	}
	if (au_start != SIZE_MAX && seen_vcl &&
	    push_au(st, au_start, n - au_start, sps_w, sps_h))
		return -1;
	return 0;
}

static uint32_t rd_le(const uint8_t *p, int n)
{
	uint32_t v = 0;
	for (int i = n - 1; i >= 0; i--)
		v = (v << 8) | p[i];
	return v;
}

static int split_ivf(struct stream *st)
{
	const uint8_t *p = st->data;
	size_t n = st->size;
	if (n < 32 || memcmp(p, "DKIF", 4) != 0) {
		fprintf(stderr, "VP9 input must be IVF (ffmpeg -i in.webm -c:v copy out.ivf)\n");
		return -1;
	}
	st->width = st->disp_w = rd_le(p + 12, 2);
	st->height = st->disp_h = rd_le(p + 14, 2);
	st->bit_depth = 0; /* not in the IVF header */
	size_t off = rd_le(p + 6, 2);
	while (off + 12 <= n) {
		uint32_t sz = rd_le(p + off, 4);
		if (off + 12 + sz > n)
			break;
		if (push_au(st, off + 12, sz, 0, 0))
			return -1;
		off += 12 + (size_t)sz;
	}
	return 0;
}

static int load_stream(struct stream *st, const char *path)
{
	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0) {
		fprintf(stderr, "open %s: %s\n", path, strerror(errno));
		return -1;
	}
	struct stat sb;
	if (fstat(fd, &sb) || sb.st_size <= 0) {
		fprintf(stderr, "%s: empty or unreadable\n", path);
		close(fd);
		return -1;
	}
	void *m = mmap(NULL, (size_t)sb.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
	close(fd);
	if (m == MAP_FAILED) {
		fprintf(stderr, "mmap %s: %s\n", path, strerror(errno));
		return -1;
	}
	st->data = m;
	st->size = (size_t)sb.st_size;
	int r = o.codec == V4L2_PIX_FMT_VP9 ? split_ivf(st) : split_annexb(st);
	if (r)
		return -1;
	if (st->n_aus == 0) {
		fprintf(stderr, "%s: no access units found. Is it raw Annex-B? For MP4/MKV input use "
			"ffmpeg -i in.mp4 -c:v copy -bsf:v hevc_mp4toannexb out.h265\n", path);
		return -1;
	}
	return 0;
}

/* ------------------------------------------------------------------------------------------ */
/* session */

struct out_buf { void *map; size_t len; bool queued; };

struct cap_buf {
	unsigned n_planes;
	void *map[VIDEO_MAX_PLANES];
	size_t map_len[VIDEO_MAX_PLANES];
	int exp_fd[VIDEO_MAX_PLANES];     /* VIDIOC_EXPBUF result (MMAP mode) */
	int dma_fd[VIDEO_MAX_PLANES];     /* imported buffer (DMABUF mode) */
	size_t dma_len[VIDEO_MAX_PLANES];
	uint32_t dumb_handle[VIDEO_MAX_PLANES];
	bool queued;
};

struct errent { const char *name; int err; unsigned count; };

enum result { RES_OK, RES_ERROR, RES_HUNG, RES_ABORTED };

struct session {
	int id;
	int fd;
	pthread_t thread;
	const struct stream *st;
	char driver[32], card[32];

	struct out_buf out[MAX_OUT_BUFS];
	unsigned n_out, out_in_driver;
	uint32_t out_sizeimage;
	unsigned out_w, out_h;

	struct cap_buf cap[MAX_CAP_BUFS];
	unsigned n_cap, cap_min, cap_count_last;
	struct v4l2_format cap_fmt;
	struct v4l2_rect visible;
	bool visible_ok;
	int drm_fd, heap_fd;
	unsigned expbuf_ok, expbuf_fail, cap_setups;

	bool out_streaming, cap_streaming, cap_configured;
	bool need_setup, pending_reconfig, got_last;
	double t_last_seen;
	bool input_done, stop_sent, stop_failed, done;
	enum result result;
	uint64_t seq_at_open;            /* QBUF count when the device was (re)opened */
	unsigned reconfig_inplace, reconfig_restart, restarts;

	uint64_t next_au, seq, loops, skipped_aus;
	uint64_t frames, error_frames, out_errors, src_changes, eos_events;
	double t_open, t_first_queue, t_first_frame, t_last_frame, t_end;
	bool fed, have_frame;
	double t_reconfig_start, t_eos, last_progress, next_due;
	double max_input_late;

	struct acc lat, ivl, rep_lat;
	uint64_t rep_frames;
	double t_rep;
	struct { uint64_t seq; double t; } ring[LAT_RING];

	struct errent errs[MAX_ERRS];
	unsigned n_errs;
};

static void logmsg(const struct session *s, const char *fmt, ...)
{
	char buf[1024];
	int n = s ? snprintf(buf, sizeof(buf), "[%8.3f s%d] ", mono() - g_t0, s->id)
		  : snprintf(buf, sizeof(buf), "[%8.3f   ] ", mono() - g_t0);
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(buf + n, sizeof(buf) - (size_t)n, fmt, ap);
	va_end(ap);
	pthread_mutex_lock(&g_log_mu);
	fputs(buf, stdout);
	fputc('\n', stdout);
	pthread_mutex_unlock(&g_log_mu);
}

static const char *errname(int err)
{
	const char *n = strerrorname_np(err);
	return n ? n : "?";
}

static void record_err(struct session *s, const char *name, int err)
{
	for (unsigned i = 0; i < s->n_errs; i++) {
		if (!strcmp(s->errs[i].name, name) && s->errs[i].err == err) {
			if (++s->errs[i].count == 5)
				logmsg(s, "(further %s %s errors not printed)", name, errname(err));
			if (s->errs[i].count < 5)
				logmsg(s, "%s failed: %s (%s)", name, strerror(err), errname(err));
			return;
		}
	}
	if (s->n_errs < MAX_ERRS)
		s->errs[s->n_errs++] = (struct errent){ name, err, 1 };
	logmsg(s, "%s failed: %s (%s)", name, strerror(err), errname(err));
}

/*
 * Every ioctl goes through here: retries on EINTR (unless an abort was requested), records and
 * prints failures. q1/q2 are errnos that are part of normal flow (EAGAIN, EPIPE, ...) and are
 * returned silently.
 */
static int xioctl(struct session *s, int fd, unsigned long req, void *arg, const char *name, int q1,
		  int q2)
{
	int r;
	do
		r = ioctl(fd, req, arg);
	while (r < 0 && errno == EINTR && g_stop < 2);
	if (r < 0) {
		int e = errno;
		if (e != q1 && e != q2)
			record_err(s, name, e);
		errno = e;
	}
	return r;
}

#define IOC(s, req, arg)          xioctl((s), (s)->fd, (req), (arg), #req, 0, 0)
#define IOCQ(s, req, arg, q1, q2) xioctl((s), (s)->fd, (req), (arg), #req, (q1), (q2))
#define IOCFD(s, fd, req, arg)    xioctl((s), (fd), (req), (arg), #req, 0, 0)

static uint64_t ts_for_seq(uint64_t seq) { return (uint64_t)((double)seq * 1e6 / o.fps + 0.5); }
static uint64_t seq_for_ts(uint64_t us) { return (uint64_t)((double)us * o.fps / 1e6 + 0.5); }

static const char *mem_name(enum mem_kind m) { return m == MEM_MMAP ? "MMAP" : "DMABUF"; }
static enum v4l2_memory cap_memory(void)
{
	return o.cap_mem == MEM_MMAP ? V4L2_MEMORY_MMAP : V4L2_MEMORY_DMABUF;
}

static void enum_formats(struct session *s, uint32_t type, const char *label)
{
	for (uint32_t i = 0;; i++) {
		struct v4l2_fmtdesc d = { .index = i, .type = type };
		if (IOCQ(s, VIDIOC_ENUM_FMT, &d, EINVAL, 0))
			break;
		logmsg(s, "  %s[%u] %-4s flags 0x%04x%s%s  '%s'", label, i, fcc(d.pixelformat).s, d.flags,
		       (d.flags & V4L2_FMT_FLAG_COMPRESSED) ? " COMPRESSED" : "",
		       (d.flags & V4L2_FMT_FLAG_DYN_RESOLUTION) ? " DYN_RESOLUTION" : "",
		       (const char *)d.description);
	}
}

static void enum_framesizes(struct session *s, uint32_t fourcc)
{
	struct v4l2_frmsizeenum fs = { .index = 0, .pixel_format = fourcc };
	if (IOCQ(s, VIDIOC_ENUM_FRAMESIZES, &fs, EINVAL, ENOTTY)) {
		logmsg(s, "  ENUM_FRAMESIZES %s: not reported", fcc(fourcc).s);
		return;
	}
	if (fs.type == V4L2_FRMSIZE_TYPE_DISCRETE)
		logmsg(s, "  framesizes %s: discrete, first %ux%u", fcc(fourcc).s, fs.discrete.width,
		       fs.discrete.height);
	else
		logmsg(s, "  framesizes %s: %ux%u .. %ux%u step %u/%u", fcc(fourcc).s,
		       fs.stepwise.min_width, fs.stepwise.min_height, fs.stepwise.max_width,
		       fs.stepwise.max_height, fs.stepwise.step_width, fs.stepwise.step_height);
}

static void log_cap_fmt(struct session *s, const char *what, const struct v4l2_format *f)
{
	const struct v4l2_pix_format_mplane *pf = &f->fmt.pix_mp;
	logmsg(s, "%s: %s %ux%u planes=%u field=%u colorspace=%u", what, fcc(pf->pixelformat).s,
	       pf->width, pf->height, pf->num_planes, pf->field, pf->colorspace);
	for (unsigned p = 0; p < pf->num_planes && p < VIDEO_MAX_PLANES; p++)
		logmsg(s, "    plane %u: bytesperline %u sizeimage %u", p, pf->plane_fmt[p].bytesperline,
		       pf->plane_fmt[p].sizeimage);
}

static int session_open(struct session *s)
{
	s->fd = open(o.dev, O_RDWR | O_NONBLOCK | O_CLOEXEC);
	if (s->fd < 0) {
		logmsg(s, "open %s: %s", o.dev, strerror(errno));
		return -1;
	}
	struct v4l2_capability cap = { 0 };
	if (IOC(s, VIDIOC_QUERYCAP, &cap))
		return -1;
	uint32_t caps = (cap.capabilities & V4L2_CAP_DEVICE_CAPS) ? cap.device_caps : cap.capabilities;
	snprintf(s->driver, sizeof(s->driver), "%s", (const char *)cap.driver);
	snprintf(s->card, sizeof(s->card), "%s", (const char *)cap.card);
	logmsg(s, "opened %s: driver '%s' card '%s' bus '%s' version %u.%u.%u device_caps 0x%08x",
	       o.dev, s->driver, s->card, (const char *)cap.bus_info, (cap.version >> 16) & 0xff,
	       (cap.version >> 8) & 0xff, cap.version & 0xff, caps);
	if (!(caps & V4L2_CAP_VIDEO_M2M_MPLANE) || !(caps & V4L2_CAP_STREAMING)) {
		logmsg(s, "device is not a streaming M2M MPLANE device; giving up");
		return -1;
	}
	if (s->id == 0 && s->restarts == 0) {
		enum_formats(s, OUT_TYPE, "OUTPUT");
		enum_framesizes(s, o.codec);
		logmsg(s, "  (the fork is known not to set DYN_RESOLUTION; this client does not need it)");
	}
	return 0;
}

static int setup_output(struct session *s)
{
	const struct stream *st = s->st;
	struct v4l2_format f = { .type = OUT_TYPE };
	uint32_t want = st->max_au + st->max_au / 8;
	if (want < (1u << 20))
		want = 1u << 20;
	want = (want + 4095u) & ~4095u;
	f.fmt.pix_mp.pixelformat = o.codec;
	f.fmt.pix_mp.width = s->out_w;
	f.fmt.pix_mp.height = s->out_h;
	f.fmt.pix_mp.num_planes = 1;
	f.fmt.pix_mp.plane_fmt[0].sizeimage = want;
	if (IOC(s, VIDIOC_S_FMT, &f))
		return -1;
	if (f.fmt.pix_mp.pixelformat != o.codec) {
		logmsg(s, "driver replaced coded format %s with %s; codec not supported",
		       fcc(o.codec).s, fcc(f.fmt.pix_mp.pixelformat).s);
		return -1;
	}
	s->out_sizeimage = f.fmt.pix_mp.plane_fmt[0].sizeimage;
	logmsg(s, "S_FMT OUTPUT %s %ux%u: got %ux%u planes=%u sizeimage %u (asked %u, max AU %u)",
	       fcc(o.codec).s, s->out_w, s->out_h, f.fmt.pix_mp.width, f.fmt.pix_mp.height,
	       f.fmt.pix_mp.num_planes, s->out_sizeimage, want, st->max_au);

	struct v4l2_requestbuffers rb = { .count = o.out_bufs, .type = OUT_TYPE,
					  .memory = V4L2_MEMORY_MMAP };
	if (IOC(s, VIDIOC_REQBUFS, &rb))
		return -1;
	if (rb.count == 0) {
		logmsg(s, "REQBUFS OUTPUT returned 0 buffers");
		return -1;
	}
	s->n_out = rb.count < MAX_OUT_BUFS ? rb.count : MAX_OUT_BUFS;
	for (unsigned i = 0; i < s->n_out; i++) {
		struct v4l2_plane pl[VIDEO_MAX_PLANES] = { 0 };
		struct v4l2_buffer b = { .index = i, .type = OUT_TYPE, .memory = V4L2_MEMORY_MMAP,
					 .m.planes = pl, .length = VIDEO_MAX_PLANES };
		if (IOC(s, VIDIOC_QUERYBUF, &b))
			return -1;
		void *m = mmap(NULL, pl[0].length, PROT_READ | PROT_WRITE, MAP_SHARED, s->fd,
			       pl[0].m.mem_offset);
		if (m == MAP_FAILED) {
			logmsg(s, "mmap OUTPUT %u: %s", i, strerror(errno));
			return -1;
		}
		s->out[i].map = m;
		s->out[i].len = pl[0].length;
	}
	logmsg(s, "OUTPUT: %u MMAP buffers of %zu bytes", s->n_out, s->out[0].len);
	if (s->out[0].len < st->max_au)
		logmsg(s, "WARNING: largest AU (%u) exceeds OUTPUT buffer (%zu); such AUs are skipped. "
		       "Try --coded-size with the real size.", st->max_au, s->out[0].len);
	return 0;
}

static int subscribe_events(struct session *s)
{
	struct v4l2_event_subscription sub = { .type = V4L2_EVENT_SOURCE_CHANGE };
	if (IOC(s, VIDIOC_SUBSCRIBE_EVENT, &sub))
		return -1;
	sub = (struct v4l2_event_subscription){ .type = V4L2_EVENT_EOS };
	if (IOC(s, VIDIOC_SUBSCRIBE_EVENT, &sub))
		logmsg(s, "EOS event not available; relying on V4L2_BUF_FLAG_LAST");
	return 0;
}

static void set_input_done(struct session *s, const char *why)
{
	if (!s->input_done)
		logmsg(s, "input done (%s) after %" PRIu64 " access units", why, s->seq);
	s->input_done = true;
}

/* Our copy of the fork's QUEUED_RATE: the driver averages the last 30 OUTPUT QBUF intervals. */
#define RATE_WINDOW 30

static double queued_rate(const struct session *s)
{
	if (s->seq - s->seq_at_open <= RATE_WINDOW)
		return 0;
	double span = s->ring[(s->seq - 1) % LAT_RING].t -
		      s->ring[(s->seq - 1 - RATE_WINDOW) % LAT_RING].t;
	return span > 0 ? RATE_WINDOW / span : 0;
}

static int free_out_buf(const struct session *s)
{
	for (unsigned i = 0; i < s->n_out; i++)
		if (!s->out[i].queued)
			return (int)i;
	return -1;
}

/* Copies the next AU into OUTPUT buffer idx and queues it. 1: queued, 0: skipped (too large). */
static int qbuf_au(struct session *s, unsigned idx)
{
	const struct au *a = &s->st->aus[s->next_au];
	if (a->len > s->out[idx].len) {
		logmsg(s, "AU %" PRIu64 " (%u bytes) does not fit OUTPUT buffer (%zu); skipped",
		       s->next_au, a->len, s->out[idx].len);
		s->skipped_aus++;
		s->next_au++;
		return 0;
	}
	memcpy(s->out[idx].map, s->st->data + a->off, a->len);
	struct v4l2_plane pl[1] = { { .bytesused = a->len, .length = (uint32_t)s->out[idx].len } };
	struct v4l2_buffer b = { .index = idx, .type = OUT_TYPE, .memory = V4L2_MEMORY_MMAP,
				 .m.planes = pl, .length = 1 };
	uint64_t us = ts_for_seq(s->seq);
	b.timestamp.tv_sec = (time_t)(us / 1000000);
	b.timestamp.tv_usec = (suseconds_t)(us % 1000000);
	if (IOC(s, VIDIOC_QBUF, &b))
		return -1;
	double now = mono();
	if (!s->fed) {
		s->fed = true;
		s->t_first_queue = now;
	}
	s->ring[s->seq % LAT_RING].seq = s->seq;
	s->ring[s->seq % LAT_RING].t = now;
	s->out[idx].queued = true;
	s->out_in_driver++;
	s->seq++;
	s->next_au++;
	return 1;
}

/*
 * One OUTPUT buffer is kept free in normal flow, and no input is queued while a resolution
 * change is pending. During that drain the decoder holds every buffer it has, and
 * rate_reset() needs one free buffer to queue after its pause.
 */
static int queue_input(struct session *s)
{
	const struct stream *st = s->st;
	int queued = 0;
	while (!s->input_done && !s->pending_reconfig) {
		double now = mono();
		if (o.max_frames && s->seq >= o.max_frames) {
			set_input_done(s, "--max-frames");
			break;
		}
		if (o.duration > 0 && s->fed && now - s->t_first_queue >= o.duration) {
			set_input_done(s, "--duration");
			break;
		}
		if (s->next_au >= st->n_aus) {
			if (!o.loop) {
				set_input_done(s, "end of file");
				break;
			}
			s->next_au = 0;
			s->loops++;
		}
		if (o.realtime && s->fed) {
			double due = s->t_first_queue + (double)s->seq / o.fps;
			if (now < due) {
				s->next_due = due;
				break;
			}
			if (now - due > s->max_input_late)
				s->max_input_late = now - due;
		}
		if (s->n_out > 1 && s->out_in_driver + 1 >= s->n_out)
			break;
		int idx = free_out_buf(s);
		if (idx < 0)
			break;
		int r = qbuf_au(s, (unsigned)idx);
		if (r < 0)
			return -1;
		queued += r;
	}
	return queued;
}

/*
 * The fork's admission check (check_core_mbps_mbpf() in iris_helpers.c) runs on every REQBUFS
 * and on both STREAMONs. It fails with ENOMEM when mbpf x fps > MAX_MBPS (7833600 =
 * 7680x4320@60). fps is the largest of the default (30) and QUEUED_RATE. QUEUED_RATE is a
 * wall-clock rate over the last 30 OUTPUT QBUFs, and it changes only on an OUTPUT QBUF. The
 * check also counts the calling session's load once per open session. An unpaced feed
 * (~1500 fps at 1080p) therefore fails the check at any later CAPTURE re-setup. Fix: pause
 * until the last 30 intervals span 30/--reconfig-rate seconds, then queue one AU. That one
 * long interval brings the average down.
 */
static void rate_reset(struct session *s)
{
	if (o.reconfig_rate <= 0 || s->seq - s->seq_at_open < RATE_WINDOW)
		return;
	double before = queued_rate(s);
	double target = s->ring[(s->seq - RATE_WINDOW) % LAT_RING].t + RATE_WINDOW / o.reconfig_rate;
	double now = mono();
	if (now >= target) {
		logmsg(s, "rate reset: queued-rate estimate %.1f fps, no pause needed", before);
		return;
	}
	int idx = free_out_buf(s);
	if (idx < 0) {
		logmsg(s, "rate reset: no free OUTPUT buffer (estimate %.1f fps); REQBUFS may fail "
		       "with ENOMEM", before);
		return;
	}
	if (s->next_au >= s->st->n_aus) {
		if (!o.loop) {
			logmsg(s, "rate reset: no AU left to queue (estimate %.1f fps)", before);
			return;
		}
		s->next_au = 0;
		s->loops++;
	}
	logmsg(s, "rate reset: queued-rate estimate %.1f fps; pausing %.0f ms, then queueing one "
	       "AU so the driver's estimate drops to <= %.1f fps", before, (target - now) * 1e3,
	       o.reconfig_rate);
	while (g_stop < 2 && (now = mono()) < target) {
		double left = target - now;
		usleep((useconds_t)((left > 0.05 ? 0.05 : left) * 1e6) + 1);
	}
	if (qbuf_au(s, (unsigned)idx) == 1)
		logmsg(s, "rate reset: queued AU %" PRIu64 ", estimate now %.1f fps", s->seq - 1,
		       queued_rate(s));
}

static int dq_output(struct session *s)
{
	int got = 0;
	for (;;) {
		struct v4l2_plane pl[VIDEO_MAX_PLANES] = { 0 };
		struct v4l2_buffer b = { .type = OUT_TYPE, .memory = V4L2_MEMORY_MMAP, .m.planes = pl,
					 .length = VIDEO_MAX_PLANES };
		if (IOCQ(s, VIDIOC_DQBUF, &b, EAGAIN, 0))
			break;
		if (b.index < s->n_out && s->out[b.index].queued) {
			s->out[b.index].queued = false;
			s->out_in_driver--;
		}
		if (b.flags & V4L2_BUF_FLAG_ERROR)
			s->out_errors++;
		got++;
	}
	return got;
}

/* ---- CAPTURE buffer memory ---- */

static int alloc_dmabuf(struct session *s, size_t len, int *fd, uint32_t *handle)
{
	*handle = 0;
	if (o.dmabuf_src == SRC_HEAP) {
		struct dma_heap_allocation_data a = { .len = len, .fd_flags = O_RDWR | O_CLOEXEC };
		if (IOCFD(s, s->heap_fd, DMA_HEAP_IOCTL_ALLOC, &a))
			return -1;
		*fd = (int)a.fd;
		return 0;
	}
	struct drm_mode_create_dumb c = { .width = 4096, .height = (uint32_t)((len + 4095) / 4096),
					  .bpp = 8 };
	if (IOCFD(s, s->drm_fd, DRM_IOCTL_MODE_CREATE_DUMB, &c))
		return -1;
	struct drm_prime_handle ph = { .handle = c.handle, .flags = DRM_CLOEXEC | DRM_RDWR };
	if (IOCFD(s, s->drm_fd, DRM_IOCTL_PRIME_HANDLE_TO_FD, &ph)) {
		struct drm_mode_destroy_dumb d = { .handle = c.handle };
		IOCFD(s, s->drm_fd, DRM_IOCTL_MODE_DESTROY_DUMB, &d);
		return -1;
	}
	*fd = ph.fd;
	*handle = c.handle;
	return 0;
}

/* Releases every user-space reference to the CAPTURE buffers: vb2 frees a buffer only when
 * no mapping and no exported dmabuf fd refers to it any more. */
static void free_cap_buffers(struct session *s)
{
	unsigned n_unmap = 0, n_unmap_fail = 0, n_exp = 0, n_dma = 0, n_dumb = 0;
	for (unsigned i = 0; i < s->n_cap; i++) {
		struct cap_buf *c = &s->cap[i];
		for (unsigned p = 0; p < c->n_planes; p++) {
			if (c->map[p]) {
				if (munmap(c->map[p], c->map_len[p]) == 0)
					n_unmap++;
				else
					n_unmap_fail++;
			}
			if (c->exp_fd[p] >= 0 && close(c->exp_fd[p]) == 0)
				n_exp++;
			if (c->dma_fd[p] >= 0 && close(c->dma_fd[p]) == 0)
				n_dma++;
			if (c->dumb_handle[p]) {
				struct drm_mode_destroy_dumb d = { .handle = c->dumb_handle[p] };
				if (IOCFD(s, s->drm_fd, DRM_IOCTL_MODE_DESTROY_DUMB, &d) == 0)
					n_dumb++;
			}
		}
		memset(c, 0, sizeof(*c));
	}
	logmsg(s, "  munmap %u plane(s) (%u failed), closed %u EXPBUF fd(s), %u imported fd(s), "
	       "destroyed %u dumb buffer(s)", n_unmap, n_unmap_fail, n_exp, n_dma, n_dumb);
	s->n_cap = 0;
}

static int queue_capture(struct session *s, unsigned i)
{
	struct cap_buf *c = &s->cap[i];
	struct v4l2_plane pl[VIDEO_MAX_PLANES] = { 0 };
	struct v4l2_buffer b = { .index = i, .type = CAP_TYPE, .memory = cap_memory(), .m.planes = pl,
				 .length = c->n_planes };
	if (o.cap_mem == MEM_DMABUF)
		for (unsigned p = 0; p < c->n_planes; p++) {
			pl[p].m.fd = c->dma_fd[p];
			pl[p].length = (uint32_t)c->dma_len[p];
		}
	if (IOC(s, VIDIOC_QBUF, &b))
		return -1;
	c->queued = true;
	return 0;
}

/* Order matters: STREAMOFF, then drop the mappings and fds, then REQBUFS(0). */
static void teardown_capture(struct session *s, const char *why)
{
	if (!s->cap_streaming && !s->n_cap) {
		s->cap_configured = false;
		return;
	}
	logmsg(s, "CAPTURE teardown (%s)", why);
	if (s->cap_streaming) {
		int type = CAP_TYPE;
		int r = IOC(s, VIDIOC_STREAMOFF, &type);
		logmsg(s, "  STREAMOFF CAPTURE: %s", r ? strerror(errno) : "ok");
		s->cap_streaming = false;
	}
	if (s->n_cap) {
		unsigned n = s->n_cap;
		free_cap_buffers(s);
		struct v4l2_requestbuffers rb = { .count = 0, .type = CAP_TYPE, .memory = cap_memory() };
		int r = IOC(s, VIDIOC_REQBUFS, &rb);
		logmsg(s, "  REQBUFS(CAPTURE, 0) for %u buffer(s): %s", n, r ? strerror(errno) : "ok");
	}
	s->cap_configured = false;
}

static void explain_enomem(struct session *s, const char *what)
{
	if (errno != ENOMEM)
		return;
	const struct v4l2_pix_format_mplane *pf = &s->cap_fmt.fmt.pix_mp;
	double rate = queued_rate(s);
	double mbpf = (double)((pf->width + 15) / 16) * (double)((pf->height + 15) / 16);
	logmsg(s, "%s ENOMEM: most likely the fork's admission check, not memory: mbpf %.0f x "
	       "max(30, queued rate ~%.0f fps) x %d session(s) = %.0f vs MAX_MBPS 7833600. Look for "
	       "'current session not supported(-12)' in dmesg. Pace the input (--realtime) or keep "
	       "--reconfig-rate on.", what, mbpf, rate, o.sessions,
	       mbpf * (rate > 30 ? rate : 30) * o.sessions);
}

/* Called after SOURCE_CHANGE only: the CAPTURE format is valid only from then on. */
static int setup_capture(struct session *s)
{
	double t_start = mono();
	struct v4l2_format f = { .type = CAP_TYPE };
	if (IOC(s, VIDIOC_G_FMT, &f))
		return -1;
	log_cap_fmt(s, "G_FMT CAPTURE after SOURCE_CHANGE", &f);
	if (s->id == 0 && s->cap_setups == 0)
		enum_formats(s, CAP_TYPE, "CAPTURE");

	if (o.cap_fourcc && f.fmt.pix_mp.pixelformat != o.cap_fourcc) {
		struct v4l2_format want = f;
		want.fmt.pix_mp.pixelformat = o.cap_fourcc;
		if (IOC(s, VIDIOC_S_FMT, &want) == 0) {
			if (want.fmt.pix_mp.pixelformat != o.cap_fourcc)
				logmsg(s, "WARNING: asked CAPTURE %s, driver chose %s",
				       fcc(o.cap_fourcc).s, fcc(want.fmt.pix_mp.pixelformat).s);
		}
		f = (struct v4l2_format){ .type = CAP_TYPE };
		if (IOC(s, VIDIOC_G_FMT, &f))
			return -1;
		log_cap_fmt(s, "CAPTURE after S_FMT", &f);
	}
	s->cap_fmt = f;
	const struct v4l2_pix_format_mplane *pf = &s->cap_fmt.fmt.pix_mp;
	unsigned n_planes = pf->num_planes;
	if (n_planes == 0 || n_planes > VIDEO_MAX_PLANES) {
		logmsg(s, "bad CAPTURE plane count %u", n_planes);
		return -1;
	}
	/* Guard against the fork's too-small-buffer SMMU fault: on the first setup the reported
	 * size must cover the size in the SPS, or we would hand the decoder buffers it overruns. */
	if (s->cap_setups == 0 && s->st->disp_w &&
	    (pf->width < s->st->disp_w || pf->height < s->st->disp_h ||
	     pf->plane_fmt[0].sizeimage < s->st->disp_w * s->st->disp_h)) {
		logmsg(s, "CAPTURE format %ux%u (plane 0 sizeimage %u) is smaller than the stream's "
		       "%ux%u; refusing to allocate (risk of SMMU fault). Still the placeholder?",
		       pf->width, pf->height, pf->plane_fmt[0].sizeimage, s->st->disp_w, s->st->disp_h);
		return -1;
	}
	if (s->st->bit_depth > 8 && pf->pixelformat != V4L2_PIX_FMT_QC10C &&
	    pf->pixelformat != V4L2_PIX_FMT_P010)
		logmsg(s, "NOTE: %u-bit stream decoded to %s; the fork is known to write only the low "
		       "8 bits into NV12 (garbage). Q10C (and P010 with build/iris-module) are the "
		       "correct 10-bit outputs.", s->st->bit_depth, fcc(pf->pixelformat).s);

	struct v4l2_selection sel = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
				      .target = V4L2_SEL_TGT_COMPOSE };
	s->visible_ok = IOCQ(s, VIDIOC_G_SELECTION, &sel, EINVAL, ENOTTY) == 0;
	if (!s->visible_ok) {
		sel.target = V4L2_SEL_TGT_CROP;
		s->visible_ok = IOCQ(s, VIDIOC_G_SELECTION, &sel, EINVAL, ENOTTY) == 0;
	}
	if (s->visible_ok) {
		s->visible = sel.r;
		logmsg(s, "visible rect (G_SELECTION %s): %ux%u+%d+%d",
		       sel.target == V4L2_SEL_TGT_COMPOSE ? "COMPOSE" : "CROP", sel.r.width,
		       sel.r.height, sel.r.left, sel.r.top);
	} else {
		logmsg(s, "visible rect: G_SELECTION not supported");
	}

	struct v4l2_control ctl = { .id = V4L2_CID_MIN_BUFFERS_FOR_CAPTURE };
	s->cap_min = IOCQ(s, VIDIOC_G_CTRL, &ctl, EINVAL, 0) == 0 ? (unsigned)ctl.value : 0;
	unsigned count = o.cap_count ? o.cap_count : s->cap_min + o.cap_extra;
	if (count < 2)
		count = 2;
	if (count > MAX_CAP_BUFS)
		count = MAX_CAP_BUFS;

	struct v4l2_requestbuffers rb = { .count = count, .type = CAP_TYPE, .memory = cap_memory() };
	if (IOC(s, VIDIOC_REQBUFS, &rb)) {
		explain_enomem(s, "REQBUFS CAPTURE");
		return -1;
	}
	if (rb.count == 0) {
		logmsg(s, "REQBUFS CAPTURE returned 0 buffers");
		return -1;
	}
	s->n_cap = rb.count < MAX_CAP_BUFS ? rb.count : MAX_CAP_BUFS;
	s->cap_count_last = s->n_cap;
	logmsg(s, "REQBUFS CAPTURE %s: asked %u (MIN_BUFFERS_FOR_CAPTURE %u), got %u",
	       mem_name(o.cap_mem), count, s->cap_min, rb.count);

	unsigned exp_ok = 0, exp_fail = 0;
	for (unsigned i = 0; i < s->n_cap; i++) {
		struct cap_buf *c = &s->cap[i];
		memset(c, 0, sizeof(*c));
		c->n_planes = n_planes;
		for (unsigned p = 0; p < VIDEO_MAX_PLANES; p++)
			c->exp_fd[p] = c->dma_fd[p] = -1;
		struct v4l2_plane pl[VIDEO_MAX_PLANES] = { 0 };
		struct v4l2_buffer b = { .index = i, .type = CAP_TYPE, .memory = cap_memory(),
					 .m.planes = pl, .length = n_planes };
		if (IOC(s, VIDIOC_QUERYBUF, &b))
			return -1;
		char fds[128] = "";
		size_t fl = 0;
		for (unsigned p = 0; p < n_planes; p++) {
			if (o.cap_mem == MEM_MMAP) {
				void *m = mmap(NULL, pl[p].length, PROT_READ, MAP_SHARED, s->fd,
					       pl[p].m.mem_offset);
				if (m == MAP_FAILED) {
					logmsg(s, "mmap CAPTURE %u.%u: %s", i, p, strerror(errno));
				} else {
					c->map[p] = m;
					c->map_len[p] = pl[p].length;
				}
				struct v4l2_exportbuffer eb = { .type = CAP_TYPE, .index = i, .plane = p,
								.flags = O_RDWR | O_CLOEXEC };
				if (IOC(s, VIDIOC_EXPBUF, &eb) == 0) {
					c->exp_fd[p] = eb.fd;
					off_t sz = lseek(eb.fd, 0, SEEK_END);
					exp_ok++;
					fl += (size_t)snprintf(fds + fl, sizeof(fds) - fl,
							       " p%u: fd %d (dmabuf %lld bytes)", p,
							       eb.fd, (long long)sz);
				} else {
					exp_fail++;
					fl += (size_t)snprintf(fds + fl, sizeof(fds) - fl,
							       " p%u: EXPBUF failed", p);
				}
				if (fl >= sizeof(fds))
					fl = sizeof(fds) - 1;
			} else {
				size_t len = pf->plane_fmt[p].sizeimage;
				if (len < pl[p].length)
					len = pl[p].length;
				len = (len + 4095) & ~(size_t)4095;
				if (alloc_dmabuf(s, len, &c->dma_fd[p], &c->dumb_handle[p])) {
					logmsg(s, "DMABUF allocation of %zu bytes failed", len);
					return -1;
				}
				c->dma_len[p] = len;
				fl += (size_t)snprintf(fds + fl, sizeof(fds) - fl,
						       " p%u: imported fd %d (%zu bytes)", p, c->dma_fd[p],
						       len);
				if (fl >= sizeof(fds))
					fl = sizeof(fds) - 1;
			}
		}
		logmsg(s, "  CAPTURE[%2u] length %u%s", i, pl[0].length, fds);
	}
	if (o.cap_mem == MEM_MMAP) {
		s->expbuf_ok += exp_ok;
		s->expbuf_fail += exp_fail;
		logmsg(s, "VIDIOC_EXPBUF: %u ok, %u failed", exp_ok, exp_fail);
	}
	for (unsigned i = 0; i < s->n_cap; i++)
		if (queue_capture(s, i))
			return -1;
	int type = CAP_TYPE;
	if (IOC(s, VIDIOC_STREAMON, &type)) {
		explain_enomem(s, "STREAMON CAPTURE");
		return -1;
	}
	s->cap_streaming = true;
	s->cap_configured = true;
	s->cap_setups++;
	logmsg(s, "CAPTURE streaming (setup took %.1f ms)", (mono() - t_start) * 1e3);
	return 0;
}

static void handle_events(struct session *s)
{
	for (;;) {
		struct v4l2_event ev;
		memset(&ev, 0, sizeof(ev));
		if (IOCQ(s, VIDIOC_DQEVENT, &ev, ENOENT, 0))
			return;
		s->last_progress = mono();
		if (ev.type == V4L2_EVENT_SOURCE_CHANGE) {
			s->src_changes++;
			logmsg(s, "SOURCE_CHANGE #%" PRIu64 " changes 0x%x%s", s->src_changes,
			       ev.u.src_change.changes,
			       (ev.u.src_change.changes & V4L2_EVENT_SRC_CH_RESOLUTION) ? " (RESOLUTION)"
										  : "");
			if (!s->cap_configured) {
				s->need_setup = true;
			} else {
				s->pending_reconfig = true;
				s->t_reconfig_start = s->last_progress;
				logmsg(s, "draining CAPTURE until LAST before reallocating (input paused)");
			}
		} else if (ev.type == V4L2_EVENT_EOS) {
			s->eos_events++;
			s->t_eos = s->last_progress;
			logmsg(s, "EOS event");
		} else {
			logmsg(s, "event type %u", ev.type);
		}
		if (ev.pending == 0)
			return;
	}
}

/*
 * Copies each plane out of the buffer once, then writes and hashes that snapshot. The read is
 * bracketed by DMA_BUF_IOCTL_SYNC on the dmabuf fd (the EXPBUF fd for MMAP buffers) in case
 * the mapping is cached. Returns 0 and the MD5 of the file (same as md5sum) in md5out.
 */
static int write_frame(struct session *s, unsigned idx, const struct v4l2_buffer *b,
		       const char *suffix, char md5out[33])
{
	const struct v4l2_pix_format_mplane *pf = &s->cap_fmt.fmt.pix_mp;
	struct cap_buf *c = &s->cap[idx];
	char path[512], meta[560];
	snprintf(path, sizeof(path), "%s_s%d_f%ld_%ux%u_%s%s.raw", o.write_prefix, s->id,
		 o.write_frame, pf->width, pf->height, fcc(pf->pixelformat).s, suffix);
	FILE *f = fopen(path, "wb");
	if (!f) {
		logmsg(s, "write %s: %s", path, strerror(errno));
		return -1;
	}
	struct md5 md;
	md5_init(&md);
	size_t total = 0;
	double t0 = mono();
	for (unsigned p = 0; p < c->n_planes; p++) {
		const struct v4l2_plane *pl = &b->m.planes[p];
		size_t used = pl->bytesused, off = pl->data_offset;
		void *base = c->map[p];
		size_t maplen = c->map_len[p];
		int sync_fd = c->exp_fd[p] >= 0 ? c->exp_fd[p] : c->dma_fd[p];
		bool tmp = false;
		if (!base && c->dma_fd[p] >= 0) {
			maplen = c->dma_len[p];
			base = mmap(NULL, maplen, PROT_READ, MAP_SHARED, c->dma_fd[p], 0);
			if (base == MAP_FAILED) {
				logmsg(s, "mmap imported dmabuf: %s", strerror(errno));
				base = NULL;
			} else {
				tmp = true;
			}
		}
		if (base && used > off && used <= maplen) {
			uint8_t *copy = malloc(used - off);
			if (!copy) {
				logmsg(s, "plane %u: out of memory for a %zu-byte copy", p, used - off);
			} else {
				if (sync_fd >= 0) {
					struct dma_buf_sync sy = { DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ };
					IOCFD(s, sync_fd, DMA_BUF_IOCTL_SYNC, &sy);
				}
				memcpy(copy, (const uint8_t *)base + off, used - off);
				if (sync_fd >= 0) {
					struct dma_buf_sync sy = { DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ };
					IOCFD(s, sync_fd, DMA_BUF_IOCTL_SYNC, &sy);
				}
				md5_update(&md, copy, used - off);
				total += fwrite(copy, 1, used - off, f);
				free(copy);
			}
		} else {
			logmsg(s, "plane %u not written (mapped %d, data_offset %zu, bytesused %zu, len %zu)",
			       p, base != NULL, off, used, maplen);
		}
		if (tmp)
			munmap(base, maplen);
	}
	fclose(f);
	md5_hex(&md, md5out);

	unsigned bpl = pf->plane_fmt[0].bytesperline;
	unsigned vw = s->visible_ok ? s->visible.width : s->st->disp_w;
	unsigned vh = s->visible_ok ? s->visible.height : s->st->disp_h;
	int vx = s->visible_ok ? s->visible.left : 0, vy = s->visible_ok ? s->visible.top : 0;
	logmsg(s, "wrote frame %ld (buffer %u) to %s: %zu bytes in %.0f ms, md5 %s, %s %ux%u "
	       "bytesperline %u, visible %ux%u+%d+%d", o.write_frame, idx, path, total,
	       (mono() - t0) * 1e3, md5out, fcc(pf->pixelformat).s, pf->width, pf->height, bpl, vw,
	       vh, vx, vy);
	if (*suffix)
		return 0;
	snprintf(meta, sizeof(meta), "%s.txt", path);
	FILE *m = fopen(meta, "w");
	if (!m)
		return 0;
	fprintf(m, "format %s\nwidth %u\nheight %u\nnum_planes %u\n", fcc(pf->pixelformat).s,
		pf->width, pf->height, pf->num_planes);
	for (unsigned p = 0; p < pf->num_planes && p < VIDEO_MAX_PLANES; p++)
		fprintf(m, "plane%u_bytesperline %u\nplane%u_sizeimage %u\nplane%u_bytesused %u\n", p,
			pf->plane_fmt[p].bytesperline, p, pf->plane_fmt[p].sizeimage, p,
			b->m.planes[p].bytesused);
	fprintf(m, "visible %ux%u+%d+%d\nbytes_written %zu\nmd5 %s\n", vw, vh, vx, vy, total, md5out);
	if (pf->pixelformat == V4L2_PIX_FMT_NV12 || pf->pixelformat == V4L2_PIX_FMT_NV21) {
		const char *pix = pf->pixelformat == V4L2_PIX_FMT_NV12 ? "nv12" : "nv21";
		unsigned h32 = (pf->height + 31) & ~31u;
		fprintf(m, "# convert (stride as width, luma height as G_FMT height):\n"
			"ffmpeg -f rawvideo -pix_fmt %s -video_size %ux%u -i %s "
			"-vf crop=%u:%u:%d:%d -frames:v 1 %s.png\n",
			pix, bpl, pf->height, path, vw, vh, vx, vy, path);
		fprintf(m, "# if chroma is shifted, the luma plane is padded to 32 lines; try:\n"
			"ffmpeg -f rawvideo -pix_fmt %s -video_size %ux%u -i %s "
			"-vf crop=%u:%u:%d:%d -frames:v 1 %s.png\n",
			pix, bpl, h32, path, vw, vh, vx, vy, path);
	} else if (pf->pixelformat == V4L2_PIX_FMT_P010) {
		/* 16-bit samples: the row is bytesperline/2 pixels; UV follows pf->height luma rows. */
		fprintf(m, "# convert (stride/2 as width, luma height as G_FMT height):\n"
			"ffmpeg -f rawvideo -pix_fmt p010le -video_size %ux%u -i %s "
			"-vf crop=%u:%u:%d:%d -frames:v 1 %s.png\n",
			bpl / 2, pf->height, path, vw, vh, vx, vy, path);
	} else {
		fprintf(m, "# %s is not a linear format ffmpeg can read directly\n",
			fcc(pf->pixelformat).s);
	}
	fclose(m);
	logmsg(s, "format details and ffmpeg command in %s", meta);
	return 0;
}

/* --dump-twice: keep the buffer dequeued, wait, dump it again and compare the hashes. */
static void dump_frame(struct session *s, unsigned idx, const struct v4l2_buffer *b)
{
	char h1[33], h2[33];
	if (write_frame(s, idx, b, "", h1) || o.dump_twice_ms <= 0)
		return;
	usleep((useconds_t)o.dump_twice_ms * 1000);
	if (write_frame(s, idx, b, "_again", h2))
		return;
	logmsg(s, "dump-twice: buffer %u held %d ms before the second copy: %s (%s vs %s)", idx,
	       o.dump_twice_ms, strcmp(h1, h2) ? "DIFFERENT - buffer changed after DQBUF" : "identical",
	       h1, h2);
}

static int dq_capture(struct session *s)
{
	int got = 0;
	while (!s->got_last) {
		struct v4l2_plane pl[VIDEO_MAX_PLANES] = { 0 };
		struct v4l2_buffer b = { .type = CAP_TYPE, .memory = cap_memory(), .m.planes = pl,
					 .length = VIDEO_MAX_PLANES };
		if (IOCQ(s, VIDIOC_DQBUF, &b, EAGAIN, EPIPE)) {
			if (errno == EPIPE) {
				logmsg(s, "DQBUF CAPTURE: EPIPE (last buffer already dequeued)");
				s->got_last = true;
				s->t_last_seen = mono();
			}
			break;
		}
		double now = mono();
		got++;
		if (b.index >= s->n_cap)
			continue;
		s->cap[b.index].queued = false;
		bool last = b.flags & V4L2_BUF_FLAG_LAST;
		if (b.flags & V4L2_BUF_FLAG_ERROR) {
			s->error_frames++;
		} else if (pl[0].bytesused > 0) {
			if (o.write_frame >= 0 && s->frames == (uint64_t)o.write_frame)
				dump_frame(s, b.index, &b);
			s->frames++;
			if (s->have_frame)
				acc_add(&s->ivl, (now - s->t_last_frame) * 1e3);
			else
				s->t_first_frame = now;
			s->have_frame = true;
			s->t_last_frame = now;
			uint64_t us = (uint64_t)b.timestamp.tv_sec * 1000000u + (uint64_t)b.timestamp.tv_usec;
			uint64_t seq = seq_for_ts(us);
			if (s->ring[seq % LAT_RING].seq == seq && seq < s->seq) {
				double ms = (now - s->ring[seq % LAT_RING].t) * 1e3;
				acc_add(&s->lat, ms);
				acc_add(&s->rep_lat, ms);
			}
		}
		if (last) {
			logmsg(s, "CAPTURE buffer with V4L2_BUF_FLAG_LAST (bytesused %u)", pl[0].bytesused);
			s->got_last = true;
			s->t_last_seen = now;
			break;
		}
		if (queue_capture(s, b.index))
			return -1;
	}
	return got;
}

static void send_stop(struct session *s)
{
	struct v4l2_decoder_cmd dc = { .cmd = V4L2_DEC_CMD_STOP };
	if (IOC(s, VIDIOC_DECODER_CMD, &dc) == 0) {
		s->stop_sent = true;
		logmsg(s, "V4L2_DEC_CMD_STOP sent; draining");
	} else {
		s->stop_failed = true;
		logmsg(s, "V4L2_DEC_CMD_STOP failed; will finish when the decoder goes idle");
	}
}

static void print_report(struct session *s, double now)
{
	uint64_t df = s->frames - s->rep_frames;
	double dt = now - s->t_rep;
	logmsg(s, "stats: %" PRIu64 " frames (+%" PRIu64 ", %.1f fps), latency avg %.1f max %.1f ms, "
	       "loops %" PRIu64, s->frames, df, dt > 0 ? (double)df / dt : 0.0,
	       acc_avg(&s->rep_lat), s->rep_lat.max, s->loops);
	s->rep_frames = s->frames;
	s->t_rep = now;
	memset(&s->rep_lat, 0, sizeof(s->rep_lat));
}

static int session_restart(struct session *s);

static void run_loop(struct session *s)
{
	double timeout = o.timeout_ms / 1000.0;
	s->last_progress = s->t_rep = mono();
	while (!s->done) {
		double now = mono();
		if (g_stop >= 2) {
			logmsg(s, "abort requested");
			s->result = RES_ABORTED;
			break;
		}
		if (g_stop == 1 && !s->input_done)
			set_input_done(s, "interrupted");
		if (s->input_done && !s->cap_configured && !s->need_setup && g_stop) {
			s->result = RES_ABORTED;
			break;
		}
		if (s->need_setup) {
			s->need_setup = false;
			rate_reset(s); /* no-op unless >= 30 AUs were queued before SOURCE_CHANGE */
			if (setup_capture(s)) {
				s->result = RES_ERROR;
				break;
			}
			s->last_progress = mono();
		}
		if (s->got_last && !s->stop_sent && !s->pending_reconfig &&
		    now - s->t_last_seen > timeout / 4) {
			logmsg(s, "LAST buffer without SOURCE_CHANGE or STOP; treating it as a resolution "
			       "change");
			s->pending_reconfig = true;
			s->t_reconfig_start = now;
		}
		if (s->pending_reconfig) {
			bool timed_out = now - s->t_reconfig_start > timeout / 2;
			if (s->got_last || timed_out) {
				if (!s->got_last)
					logmsg(s, "no LAST buffer %.1f s after SOURCE_CHANGE; reallocating anyway",
					       timeout / 2);
				double t = mono();
				rate_reset(s);
				teardown_capture(s, "resolution change");
				s->pending_reconfig = false;
				s->got_last = false;
				if (setup_capture(s) == 0) {
					s->reconfig_inplace++;
					logmsg(s, "reconfig path: IN-PLACE. Resolution change handled in %.1f ms "
					       "(drain %.1f ms)", (mono() - s->t_reconfig_start) * 1e3,
					       (t - s->t_reconfig_start) * 1e3);
				} else if (o.no_restart) {
					logmsg(s, "reconfig path: in-place re-setup failed, --no-restart given");
					s->result = RES_ERROR;
					break;
				} else if (session_restart(s)) {
					s->result = RES_ERROR;
					break;
				}
				s->last_progress = mono();
			}
		}
		int progress = 0;
		int q = queue_input(s);
		if (q < 0) {
			s->result = RES_ERROR;
			break;
		}
		progress += q;
		if (s->input_done && s->cap_streaming && !s->pending_reconfig && !s->stop_sent &&
		    !s->stop_failed)
			send_stop(s);
		if (s->stop_sent && s->got_last) {
			s->done = true;
			break;
		}
		if (s->stop_sent && s->eos_events && now - s->t_eos > 1.0) {
			logmsg(s, "EOS event but no LAST buffer after 1 s; finishing");
			s->done = true;
			break;
		}
		if (s->stop_failed && s->out_in_driver == 0 && now - s->last_progress > 1.0) {
			s->done = true;
			break;
		}

		int wait_ms = POLL_SLICE_MS;
		if (o.realtime && !s->input_done && s->next_due > now) {
			int ms = (int)((s->next_due - now) * 1e3) + 1;
			if (ms < wait_ms)
				wait_ms = ms;
		}
		/* POLLOUT only while the driver holds OUTPUT buffers: some poll implementations
		 * report POLLOUT whenever a free OUTPUT slot exists, which would spin in --realtime. */
		struct pollfd pfd = { .fd = s->fd, .events = POLLPRI };
		if (s->out_in_driver)
			pfd.events |= POLLOUT;
		if (s->cap_streaming && !s->got_last)
			pfd.events |= POLLIN;
		int pr = poll(&pfd, 1, wait_ms);
		if (pr < 0 && errno != EINTR) {
			logmsg(s, "poll: %s", strerror(errno));
			s->result = RES_ERROR;
			break;
		}
		/* Events are also polled for directly until CAPTURE exists, in case the fork's poll
		 * does not raise POLLPRI before CAPTURE streams. */
		if ((pr > 0 && (pfd.revents & POLLPRI)) || !s->cap_configured || pr == 0) {
			uint64_t before = s->src_changes + s->eos_events;
			handle_events(s);
			progress += (int)(s->src_changes + s->eos_events - before);
		}
		progress += dq_output(s);
		if (s->cap_streaming) {
			int c = dq_capture(s);
			if (c < 0) {
				s->result = RES_ERROR;
				break;
			}
			progress += c;
		}
		now = mono();
		if (progress)
			s->last_progress = now;
		else if (pr > 0)
			usleep(1000); /* poll reported something (e.g. POLLERR) we could not consume */

		if (o.stats_interval > 0 && now - s->t_rep >= o.stats_interval)
			print_report(s, now);

		bool waiting = s->out_in_driver > 0 || s->stop_sent || s->pending_reconfig ||
			       (s->out_streaming && !s->cap_configured);
		if (waiting && now - s->last_progress > timeout) {
			logmsg(s, "HANG: decoder made no progress for %.1f s (%u OUTPUT buffers held, "
			       "capture %s, stop_sent %d, reconfig %d). Firmware hang? Check "
			       "'sudo dmesg | grep -iE \"iris|0x5000003\"'. Abandoning this session "
			       "(STREAMOFF + close). Do not SIGKILL processes stuck in decoder ioctls.",
			       now - s->last_progress, s->out_in_driver,
			       s->cap_configured ? "configured" : "waiting for SOURCE_CHANGE",
			       s->stop_sent, s->pending_reconfig);
			s->result = RES_HUNG;
			break;
		}
	}
}

/* STREAMOFF both queues, free every buffer, close the decoder fd. */
static void session_close_device(struct session *s, const char *why)
{
	if (s->fd < 0)
		return;
	teardown_capture(s, why);
	if (s->out_streaming) {
		int type = OUT_TYPE;
		int r = IOC(s, VIDIOC_STREAMOFF, &type);
		logmsg(s, "  STREAMOFF OUTPUT: %s", r ? strerror(errno) : "ok");
		s->out_streaming = false;
	}
	if (s->n_out) {
		unsigned n = 0;
		for (unsigned i = 0; i < s->n_out; i++)
			if (s->out[i].map && munmap(s->out[i].map, s->out[i].len) == 0)
				n++;
		struct v4l2_requestbuffers rb = { .count = 0, .type = OUT_TYPE,
						  .memory = V4L2_MEMORY_MMAP };
		int r = IOC(s, VIDIOC_REQBUFS, &rb);
		logmsg(s, "  munmap %u OUTPUT buffer(s), REQBUFS(OUTPUT, 0): %s", n,
		       r ? strerror(errno) : "ok");
		s->n_out = 0;
	}
	s->out_in_driver = 0;
	close(s->fd);
	s->fd = -1;
	logmsg(s, "  decoder fd closed");
}

static void session_cleanup(struct session *s)
{
	if (s->result == RES_HUNG)
		logmsg(s, "cleanup after hang: STREAMOFF CAPTURE/OUTPUT (may block in the driver)");
	session_close_device(s, "session end");
	if (s->drm_fd >= 0)
		close(s->drm_fd);
	if (s->heap_fd >= 0)
		close(s->heap_fd);
	s->drm_fd = s->heap_fd = -1;
	logmsg(s, "closed");
}

/* Open the decoder, set up OUTPUT at out_w x out_h, queue the first AUs, STREAMON OUTPUT. */
static int session_start(struct session *s)
{
	s->seq_at_open = s->seq;
	if (session_open(s) || setup_output(s) || subscribe_events(s))
		return -1;
	struct v4l2_format f = { .type = CAP_TYPE };
	if (IOC(s, VIDIOC_G_FMT, &f) == 0)
		log_cap_fmt(s, "G_FMT CAPTURE before SOURCE_CHANGE (fork reports a placeholder)", &f);
	if (queue_input(s) < 0)
		return -1;
	int type = OUT_TYPE;
	if (IOC(s, VIDIOC_STREAMON, &type))
		return -1;
	s->out_streaming = true;
	logmsg(s, "OUTPUT streaming, %u AUs queued; waiting for SOURCE_CHANGE", s->out_in_driver);
	return 0;
}

/*
 * Fallback when the CAPTURE re-setup after a resolution change fails: close the whole session,
 * reopen the device and resume at the AU whose SPS starts the new resolution. Input was paused
 * at SOURCE_CHANGE, so that AU is among the last few AUs queued.
 */
static int session_restart(struct session *s)
{
	const struct stream *st = s->st;
	size_t n = st->n_aus, found = SIZE_MAX, any_sps = SIZE_MAX;
	for (size_t k = 1; k <= 64 && k <= n; k++) {
		size_t i = (size_t)((s->next_au + n - k) % n);
		const struct au *a = &st->aus[i];
		if (!a->sps_w)
			continue;
		if (any_sps == SIZE_MAX)
			any_sps = i;
		if (a->sps_w != s->out_w || a->sps_h != s->out_h) {
			found = i;
			break;
		}
	}
	if (found == SIZE_MAX)
		found = any_sps;
	if (found == SIZE_MAX) {
		logmsg(s, "session restart: no SPS among the last 64 AUs; giving up");
		return -1;
	}
	const struct au *a = &st->aus[found];
	uint64_t refeed = (s->next_au + n - found) % n;
	logmsg(s, "reconfig path: SESSION RESTART. Closing the device and reopening; resuming at AU "
	       "%zu (SPS %ux%u, previous OUTPUT size %ux%u), re-feeding %" PRIu64 " AU(s)", found,
	       a->sps_w, a->sps_h, s->out_w, s->out_h, refeed);
	session_close_device(s, "session restart");
	if (found >= s->next_au && s->loops > 0)
		s->loops--;
	s->next_au = found;
	s->need_setup = s->pending_reconfig = s->got_last = false;
	s->stop_sent = s->stop_failed = false;
	s->input_done = g_stop != 0;
	s->restarts++;
	s->reconfig_restart++;
	usleep(200 * 1000); /* fast close/reopen cycles can crash the firmware */
	if (!o.coded_w) {
		s->out_w = a->sps_w;
		s->out_h = a->sps_h;
	}
	if (session_start(s))
		return -1;
	s->last_progress = mono();
	return 0;
}

static void *session_run(void *arg)
{
	struct session *s = arg;
	s->t_open = mono();
	s->result = RES_OK;
	if (o.cap_mem == MEM_DMABUF) {
		const char *path = o.dmabuf_dev ? o.dmabuf_dev
				 : o.dmabuf_src == SRC_HEAP ? "/dev/dma_heap/system" : "/dev/dri/card0";
		int fd = open(path, O_RDWR | O_CLOEXEC);
		if (fd < 0) {
			logmsg(s, "open %s: %s", path, strerror(errno));
			s->result = RES_ERROR;
			s->t_end = mono();
			return NULL;
		}
		if (o.dmabuf_src == SRC_HEAP)
			s->heap_fd = fd;
		else
			s->drm_fd = fd;
		logmsg(s, "CAPTURE DMABUF source: %s", path);
	}
	s->out_w = o.coded_w ? o.coded_w : s->st->width ? s->st->width : 1920;
	s->out_h = o.coded_h ? o.coded_h : s->st->height ? s->st->height : 1080;
	if (session_start(s)) {
		s->result = RES_ERROR;
		goto out;
	}
	run_loop(s);
out:
	session_cleanup(s);
	s->t_end = mono();
	return NULL;
}

static void print_summary(const struct session *s)
{
	static const char *res[] = { "ok", "error", "HUNG", "aborted" };
	const struct v4l2_pix_format_mplane *pf = &s->cap_fmt.fmt.pix_mp;
	double span = s->t_last_frame - s->t_first_frame;
	double wall = s->t_end - s->t_open;
	printf("\n===== session %d summary =====\n", s->id);
	printf("  result            %s\n", res[s->result]);
	printf("  device            %s (driver '%s', card '%s')\n", o.dev, s->driver, s->card);
	printf("  input             %" PRIu64 " AUs queued, %" PRIu64 " loops, %" PRIu64
	       " skipped (too large), %" PRIu64 " OUTPUT error flags\n",
	       s->seq, s->loops, s->skipped_aus, s->out_errors);
	printf("  OUTPUT            %s %ux%u, %u buffers of %zu bytes (sizeimage %u)\n",
	       fcc(o.codec).s, s->out_w, s->out_h, s->n_out ? s->n_out : o.out_bufs,
	       s->out[0].len, s->out_sizeimage);
	if (pf->pixelformat) {
		printf("  CAPTURE           %s %ux%u, %u plane(s), %s, %u buffers (min %u), "
		       "%u setup(s)\n", fcc(pf->pixelformat).s, pf->width, pf->height, pf->num_planes,
		       mem_name(o.cap_mem), s->cap_count_last, s->cap_min, s->cap_setups);
		for (unsigned p = 0; p < pf->num_planes && p < VIDEO_MAX_PLANES; p++)
			printf("    plane %u         bytesperline %u, sizeimage %u\n", p,
			       pf->plane_fmt[p].bytesperline, pf->plane_fmt[p].sizeimage);
		if (s->visible_ok)
			printf("  visible           %ux%u+%d+%d\n", s->visible.width, s->visible.height,
			       s->visible.left, s->visible.top);
		if (o.cap_mem == MEM_MMAP)
			printf("  VIDIOC_EXPBUF     %u ok, %u failed\n", s->expbuf_ok, s->expbuf_fail);
	} else {
		printf("  CAPTURE           never configured\n");
	}
	printf("  SOURCE_CHANGE     %" PRIu64 " event(s), EOS events %" PRIu64 "\n", s->src_changes,
	       s->eos_events);
	if (s->reconfig_inplace || s->reconfig_restart)
		printf("  resolution change %u in place, %u by session restart\n", s->reconfig_inplace,
		       s->reconfig_restart);
	printf("  frames            %" PRIu64 " decoded, %" PRIu64 " with ERROR flag\n", s->frames,
	       s->error_frames);
	printf("  wall time         %.3f s open->close, %.3f s first->last frame\n", wall, span);
	printf("  decode fps        %.2f (first->last frame), %.2f (open->close)\n",
	       span > 0 && s->frames > 1 ? (double)(s->frames - 1) / span : 0.0,
	       wall > 0 ? (double)s->frames / wall : 0.0);
	printf("  latency           min %.2f / avg %.2f / max %.2f ms (OUTPUT QBUF -> CAPTURE DQBUF, "
	       "%" PRIu64 " matched)\n", s->lat.min, acc_avg(&s->lat), s->lat.max, s->lat.n);
	printf("  frame interval    min %.2f / avg %.2f / max %.2f ms (between CAPTURE DQBUFs)\n",
	       s->ivl.min, acc_avg(&s->ivl), s->ivl.max);
	if (o.realtime)
		printf("  realtime          --fps %.3f, input fell behind schedule by up to %.1f ms\n",
		       o.fps, s->max_input_late * 1e3);
	if (s->n_errs == 0) {
		printf("  ioctl errors      none\n");
	} else {
		for (unsigned i = 0; i < s->n_errs; i++)
			printf("  ioctl error       %s: %s (%s) x%u\n", s->errs[i].name,
			       strerror(s->errs[i].err), errname(s->errs[i].err),
			       s->errs[i].count);
	}
}

/* ------------------------------------------------------------------------------------------ */
/* main */

static void on_signal(int sig)
{
	(void)sig;
	g_stop++;
}

static uint32_t parse_fourcc(const char *s)
{
	if (strlen(s) != 4)
		return 0;
	return v4l2_fourcc(s[0], s[1], s[2], s[3]);
}

static void usage(const char *argv0)
{
	printf(
	"usage: %s [options] INPUT\n"
	"  INPUT is a raw Annex-B .h265/.h264 elementary stream (IVF for VP9).\n"
	"\n"
	"  -d, --device PATH        decoder node (default /dev/video-dec0)\n"
	"  -c, --codec NAME         hevc (default) | h264 | vp9\n"
	"      --allow-vp9          allow VP9 (crashes the Frame firmware on the 2nd session)\n"
	"  -C, --capture FOURCC     NV12 | NV21 | Q08C | Q10C | P010 | any 4cc (default: driver's choice)\n"
	"      --capture-mem M      mmap (default; EXPBUF on every buffer) | dmabuf (imported)\n"
	"      --dmabuf-src S       heap (default, /dev/dma_heap/system) | dumb (/dev/dri/card0)\n"
	"      --dmabuf-dev PATH    override the heap or DRM device for --capture-mem dmabuf\n"
	"      --output-bufs N      OUTPUT buffers (default 8)\n"
	"      --capture-extra N    CAPTURE buffers on top of MIN_BUFFERS_FOR_CAPTURE (default 4)\n"
	"      --capture-bufs N     exact CAPTURE buffer count (overrides --capture-extra)\n"
	"      --coded-size WxH     size for S_FMT(OUTPUT) (default: parsed from the SPS)\n"
	"      --parse-only         split the input, print AU statistics, do not open the device\n"
	"  -n, --max-frames N       stop feeding after N access units, then drain\n"
	"  -w, --write-frame N      dump decoded frame N (output order, from 0) raw to a file\n"
	"      --write-prefix P     dump file prefix (default 'frame')\n"
	"  -l, --loop               replay the file until --max-frames, --duration or Ctrl-C\n"
	"      --duration SEC       stop feeding after SEC seconds\n"
	"  -s, --sessions N         N concurrent decoder sessions on the same file (threads)\n"
	"      --stagger-ms MS      delay between session starts (default 500)\n"
	"  -r, --realtime           pace input at --fps\n"
	"  -f, --fps FPS            nominal stream rate for --realtime and timestamps (default 60)\n"
	"      --reconfig-rate FPS  before a CAPTURE re-setup, pause input until the driver's\n"
	"                           queued-rate estimate is <= FPS (default 25, 0 = off)\n"
	"      --no-restart         if the in-place re-setup fails, stop instead of reopening the\n"
	"                           device and resuming at the new SPS\n"
	"      --dump-twice MS      with -w: hold the buffer MS ms, dump it again, compare MD5s\n"
	"  -i, --stats-interval S   print per-session stats every S seconds\n"
	"  -t, --timeout-ms MS      no-progress timeout before declaring a hang (default 5000)\n"
	"\n"
	"Ctrl-C once: stop feeding and drain. Twice: abort, STREAMOFF and close.\n"
	"Never SIGKILL this process while it is stuck in a decoder ioctl: on the Frame that can oops\n"
	"the kernel. Wait for the --timeout-ms hang detection instead.\n", argv0);
}

int main(int argc, char **argv)
{
	enum { OPT_ALLOW_VP9 = 256, OPT_CAP_MEM, OPT_DMABUF_SRC, OPT_DMABUF_DEV, OPT_OUT_BUFS,
	       OPT_CAP_EXTRA, OPT_CAP_BUFS, OPT_CODED_SIZE, OPT_WRITE_PREFIX, OPT_DURATION,
	       OPT_STAGGER, OPT_PARSE_ONLY, OPT_RECONFIG_RATE, OPT_NO_RESTART,
	       OPT_DUMP_TWICE };
	static const struct option lo[] = {
		{ "device", required_argument, NULL, 'd' },
		{ "codec", required_argument, NULL, 'c' },
		{ "allow-vp9", no_argument, NULL, OPT_ALLOW_VP9 },
		{ "capture", required_argument, NULL, 'C' },
		{ "capture-mem", required_argument, NULL, OPT_CAP_MEM },
		{ "dmabuf-src", required_argument, NULL, OPT_DMABUF_SRC },
		{ "dmabuf-dev", required_argument, NULL, OPT_DMABUF_DEV },
		{ "output-bufs", required_argument, NULL, OPT_OUT_BUFS },
		{ "capture-extra", required_argument, NULL, OPT_CAP_EXTRA },
		{ "capture-bufs", required_argument, NULL, OPT_CAP_BUFS },
		{ "coded-size", required_argument, NULL, OPT_CODED_SIZE },
		{ "parse-only", no_argument, NULL, OPT_PARSE_ONLY },
		{ "reconfig-rate", required_argument, NULL, OPT_RECONFIG_RATE },
		{ "no-restart", no_argument, NULL, OPT_NO_RESTART },
		{ "dump-twice", required_argument, NULL, OPT_DUMP_TWICE },
		{ "max-frames", required_argument, NULL, 'n' },
		{ "write-frame", required_argument, NULL, 'w' },
		{ "write-prefix", required_argument, NULL, OPT_WRITE_PREFIX },
		{ "loop", no_argument, NULL, 'l' },
		{ "duration", required_argument, NULL, OPT_DURATION },
		{ "sessions", required_argument, NULL, 's' },
		{ "stagger-ms", required_argument, NULL, OPT_STAGGER },
		{ "realtime", no_argument, NULL, 'r' },
		{ "fps", required_argument, NULL, 'f' },
		{ "stats-interval", required_argument, NULL, 'i' },
		{ "timeout-ms", required_argument, NULL, 't' },
		{ "help", no_argument, NULL, 'h' },
		{ 0 }
	};
	setvbuf(stdout, NULL, _IOLBF, 0);
	g_t0 = mono();
	int c;
	while ((c = getopt_long(argc, argv, "d:c:C:n:w:ls:rf:i:t:h", lo, NULL)) != -1) {
		switch (c) {
		case 'd': o.dev = optarg; break;
		case 'c':
			o.codec_name = optarg;
			if (!strcmp(optarg, "hevc") || !strcmp(optarg, "h265"))
				o.codec = V4L2_PIX_FMT_HEVC;
			else if (!strcmp(optarg, "h264") || !strcmp(optarg, "avc"))
				o.codec = V4L2_PIX_FMT_H264;
			else if (!strcmp(optarg, "vp9"))
				o.codec = V4L2_PIX_FMT_VP9;
			else {
				fprintf(stderr, "unknown codec %s\n", optarg);
				return 2;
			}
			break;
		case OPT_ALLOW_VP9: o.allow_vp9 = true; break;
		case 'C':
			o.cap_fourcc = parse_fourcc(optarg);
			if (!o.cap_fourcc) {
				fprintf(stderr, "--capture needs a 4-character fourcc\n");
				return 2;
			}
			break;
		case OPT_CAP_MEM:
			if (!strcmp(optarg, "mmap"))
				o.cap_mem = MEM_MMAP;
			else if (!strcmp(optarg, "dmabuf"))
				o.cap_mem = MEM_DMABUF;
			else {
				fprintf(stderr, "--capture-mem mmap|dmabuf\n");
				return 2;
			}
			break;
		case OPT_DMABUF_SRC:
			if (!strcmp(optarg, "heap"))
				o.dmabuf_src = SRC_HEAP;
			else if (!strcmp(optarg, "dumb"))
				o.dmabuf_src = SRC_DUMB;
			else {
				fprintf(stderr, "--dmabuf-src heap|dumb\n");
				return 2;
			}
			break;
		case OPT_DMABUF_DEV: o.dmabuf_dev = optarg; break;
		case OPT_OUT_BUFS: o.out_bufs = (unsigned)atoi(optarg); break;
		case OPT_CAP_EXTRA: o.cap_extra = (unsigned)atoi(optarg); break;
		case OPT_CAP_BUFS: o.cap_count = (unsigned)atoi(optarg); break;
		case OPT_CODED_SIZE:
			if (sscanf(optarg, "%ux%u", &o.coded_w, &o.coded_h) != 2) {
				fprintf(stderr, "--coded-size WxH\n");
				return 2;
			}
			break;
		case 'n': o.max_frames = strtoull(optarg, NULL, 10); break;
		case 'w': o.write_frame = atol(optarg); break;
		case OPT_WRITE_PREFIX: o.write_prefix = optarg; break;
		case OPT_PARSE_ONLY: o.parse_only = true; break;
		case OPT_RECONFIG_RATE: o.reconfig_rate = atof(optarg); break;
		case OPT_NO_RESTART: o.no_restart = true; break;
		case OPT_DUMP_TWICE: o.dump_twice_ms = atoi(optarg); break;
		case 'l': o.loop = true; break;
		case OPT_DURATION: o.duration = atof(optarg); break;
		case 's': o.sessions = atoi(optarg); break;
		case OPT_STAGGER: o.stagger_ms = atoi(optarg); break;
		case 'r': o.realtime = true; break;
		case 'f': o.fps = atof(optarg); break;
		case 'i': o.stats_interval = atof(optarg); break;
		case 't': o.timeout_ms = atoi(optarg); break;
		case 'h': usage(argv[0]); return 0;
		default: usage(argv[0]); return 2;
		}
	}
	if (optind != argc - 1) {
		usage(argv[0]);
		return 2;
	}
	o.input = argv[optind];
	if (o.codec == V4L2_PIX_FMT_VP9 && !o.allow_vp9) {
		fprintf(stderr, "VP9 refused: on the Frame's 6.18 kernel the 2nd VP9 session after boot "
			"crashes the decoder firmware, and killing the hung process can oops the kernel. "
			"Pass --allow-vp9 to run it anyway (preferably right after a reboot, one session).\n");
		return 2;
	}
	if (o.fps <= 0 || o.fps > 1000 || o.sessions < 1 || o.sessions > 16 || o.timeout_ms < 100 ||
	    o.out_bufs < 1 || o.out_bufs > MAX_OUT_BUFS) {
		fprintf(stderr, "bad option value (fps 0..1000, sessions 1..16, timeout >= 100 ms, "
			"output-bufs 1..%d)\n", MAX_OUT_BUFS);
		return 2;
	}

	if (load_stream(&g_st, o.input))
		return 1;
	logmsg(NULL, "%s: %zu bytes, %zu access units, max AU %u bytes, codec %s", o.input, g_st.size,
	       g_st.n_aus, g_st.max_au, o.codec_name);
	if (g_st.width)
		logmsg(NULL, "stream header: coded %ux%u, display %ux%u, %u-bit, chroma_format %u%s",
		       g_st.width, g_st.height, g_st.disp_w, g_st.disp_h, g_st.bit_depth,
		       g_st.chroma_format, g_st.sps_parsed ? "" : " (IVF)");
	else
		logmsg(NULL, "no SPS parsed; S_FMT(OUTPUT) uses %ux%u", o.coded_w ? o.coded_w : 1920,
		       o.coded_h ? o.coded_h : 1080);

	if (o.parse_only) {
		uint64_t sum = 0;
		for (size_t i = 0; i < g_st.n_aus; i++)
			sum += g_st.aus[i].len;
		printf("access_units %zu\nmax_au_bytes %u\navg_au_bytes %.0f\nmbps_at_fps %.2f\n",
		       g_st.n_aus, g_st.max_au, (double)sum / (double)g_st.n_aus,
		       (double)sum * 8.0 / (double)g_st.n_aus * o.fps / 1e6);
		for (size_t i = 0; i < g_st.n_aus && i < 6; i++)
			printf("au[%zu] offset %" PRIu64 " len %u\n", i, g_st.aus[i].off, g_st.aus[i].len);
		unsigned pw = 0, ph = 0;
		for (size_t i = 0; i < g_st.n_aus; i++) {
			const struct au *a = &g_st.aus[i];
			if (a->sps_w && (a->sps_w != pw || a->sps_h != ph)) {
				printf("sps_size_change au %zu: %ux%u\n", i, a->sps_w, a->sps_h);
				pw = a->sps_w;
				ph = a->sps_h;
			}
		}
		return 0;
	}

	struct sigaction sa = { .sa_handler = on_signal }; /* no SA_RESTART: poll returns EINTR */
	sigemptyset(&sa.sa_mask);
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);
	signal(SIGPIPE, SIG_IGN);

	struct session *ss = calloc((size_t)o.sessions, sizeof(*ss));
	if (!ss)
		return 1;
	int started = 0;
	for (int i = 0; i < o.sessions && g_stop == 0; i++) {
		ss[i].id = i;
		ss[i].fd = ss[i].drm_fd = ss[i].heap_fd = -1;
		ss[i].st = &g_st;
		int e = pthread_create(&ss[i].thread, NULL, session_run, &ss[i]);
		if (e) {
			logmsg(NULL, "pthread_create: %s", strerror(e));
			break;
		}
		started++;
		if (i + 1 < o.sessions && o.stagger_ms > 0)
			usleep((useconds_t)o.stagger_ms * 1000);
	}
	for (int i = 0; i < started; i++)
		pthread_join(ss[i].thread, NULL);

	int rc = 0;
	uint64_t total = 0;
	double fps_sum = 0;
	for (int i = 0; i < started; i++) {
		print_summary(&ss[i]);
		double span = ss[i].t_last_frame - ss[i].t_first_frame;
		total += ss[i].frames;
		if (span > 0 && ss[i].frames > 1)
			fps_sum += (double)(ss[i].frames - 1) / span;
		if (ss[i].result == RES_HUNG)
			rc = 3;
		else if (ss[i].result == RES_ERROR && rc == 0)
			rc = 1;
	}
	if (started > 1)
		printf("\n===== all sessions =====\n  sessions %d, frames %" PRIu64
		       ", aggregate decode fps %.2f\n", started, total, fps_sum);
	free(ss);
	free(g_st.aus);
	munmap((void *)g_st.data, g_st.size);
	return rc;
}
