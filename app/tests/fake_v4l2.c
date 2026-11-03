// A stand-in for the headset's stateful V4L2 H.264 decoder, for desktop tests of V4L2Decoder's feed: LD_PRELOAD it and
// /dev/video-dec0 exists, takes access units and gives back "pictures" in display order, after a reorder delay.
// Nothing is decoded. Each access unit's picture order count comes from its slice header; a picture leaves the reorder
// buffer when more than FAKE_V4L2_DELAY pictures wait (default 4), or at an IDR, an end-of-sequence NAL unit or a drain.
// FAKE_V4L2_LOG=1 logs each access unit and picture to stderr.
// Build: gcc -shared -fPIC -O1 -o fake_v4l2.so fake_v4l2.c -ldl -lpthread
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <poll.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define DEVICE "/dev/video-dec0"
#define MAX_BUFFERS 64
#define MAX_REORDER 64
#define CAPTURE_MIN 6
#define OUT_OFFSET 0x1000000

typedef struct {
	int poc;
	struct timeval ts;
} Picture;

typedef struct {
	void *map;
	uint32_t length, bytes;
	struct timeval ts;
	int in_driver; // Waiting for the decoder.
	int done; // Ready for DQBUF.
	uint64_t order;
} OutBuf;

typedef struct {
	int in_driver; // Empty, the decoder may fill it.
	int filled;
	uint32_t bytes;
	struct timeval ts;
	int last;
	uint64_t order;
} CapBuf;

typedef struct {
	int fd;
	uint32_t width, height, sizeimage;
	OutBuf out[MAX_BUFFERS];
	CapBuf cap[MAX_BUFFERS];
	uint32_t out_count, cap_count;
	int out_streaming, cap_streaming;
	int source_change_pending, source_change_sent;
	int stop, last_sent;
	Picture reorder[MAX_REORDER];
	int reorder_count;
	Picture due[MAX_REORDER];
	int due_count;
	uint64_t order;
	// H.264 headers.
	int log2_frame_num, log2_poc_lsb, poc_type;
	int poc_msb, prev_lsb;
} Device;

static Device *devices[8];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static int delay_pictures = 4;
static int logging = 0;

static int (*real_open)(const char *, int, ...);
static int (*real_ioctl)(int, unsigned long, ...);
static void *(*real_mmap)(void *, size_t, int, int, int, off_t);
static int (*real_poll)(struct pollfd *, nfds_t, int);
static int (*real_close)(int);
static int (*real_stat)(const char *, struct stat *);

__attribute__((constructor)) static void init_fake(void) {
	real_open = dlsym(RTLD_NEXT, "open");
	real_ioctl = dlsym(RTLD_NEXT, "ioctl");
	real_mmap = dlsym(RTLD_NEXT, "mmap");
	real_poll = dlsym(RTLD_NEXT, "poll");
	real_close = dlsym(RTLD_NEXT, "close");
	real_stat = dlsym(RTLD_NEXT, "stat");
	const char *d = getenv("FAKE_V4L2_DELAY");
	if (d) {
		delay_pictures = atoi(d);
	}
	logging = getenv("FAKE_V4L2_LOG") != NULL;
}

static Device *find_device(int fd) {
	for (int i = 0; i < 8; i++) {
		if (devices[i] && devices[i]->fd == fd) {
			return devices[i];
		}
	}
	return NULL;
}

/* H.264 headers */

typedef struct {
	uint8_t data[256];
	int size, bit;
} Bits;

static void bits_init(Bits *b, const uint8_t *p, int size) {
	b->size = 0;
	b->bit = 0;
	int zeros = 0;
	for (int i = 0; i < size && b->size < (int)sizeof(b->data); i++) {
		if (zeros >= 2 && p[i] == 3) {
			zeros = 0;
			continue;
		}
		zeros = p[i] == 0 ? zeros + 1 : 0;
		b->data[b->size++] = p[i];
	}
}

static uint32_t u(Bits *b, int n) {
	uint32_t v = 0;
	for (int i = 0; i < n; i++) {
		int byte = b->bit >> 3;
		int bit = byte < b->size ? (b->data[byte] >> (7 - (b->bit & 7))) & 1 : 0;
		v = (v << 1) | bit;
		b->bit++;
	}
	return v;
}

static uint32_t ue(Bits *b) {
	int zeros = 0;
	while (zeros < 32 && u(b, 1) == 0) {
		zeros++;
	}
	return (1u << zeros) - 1 + u(b, zeros);
}

static void parse_sps(Device *d, const uint8_t *p, int size) {
	Bits b;
	bits_init(&b, p, size);
	int profile = u(&b, 8);
	u(&b, 16);
	ue(&b);
	if (profile == 100 || profile == 110 || profile == 122 || profile == 244) {
		if (ue(&b) == 3) {
			u(&b, 1);
		}
		ue(&b);
		ue(&b);
		u(&b, 1);
		u(&b, 1); // No scaling matrices in what the tests encode.
	}
	d->log2_frame_num = ue(&b) + 4;
	d->poc_type = ue(&b);
	d->log2_poc_lsb = d->poc_type == 0 ? (int)ue(&b) + 4 : 0;
}

static int parse_poc(Device *d, const uint8_t *p, int size, int idr) {
	Bits b;
	bits_init(&b, p, size);
	ue(&b);
	ue(&b);
	ue(&b);
	u(&b, d->log2_frame_num);
	if (idr) {
		ue(&b);
		d->poc_msb = 0;
		d->prev_lsb = 0;
	}
	int lsb = u(&b, d->log2_poc_lsb);
	int max = 1 << d->log2_poc_lsb;
	if (lsb < d->prev_lsb && d->prev_lsb - lsb >= max / 2) {
		d->poc_msb += max;
	} else if (lsb > d->prev_lsb && lsb - d->prev_lsb > max / 2) {
		d->poc_msb -= max;
	}
	d->prev_lsb = lsb;
	return d->poc_msb + lsb;
}

/* The decoder */

static void take_lowest(Device *d) {
	int best = 0;
	for (int i = 1; i < d->reorder_count; i++) {
		if (d->reorder[i].poc < d->reorder[best].poc) {
			best = i;
		}
	}
	d->due[d->due_count++] = d->reorder[best];
	d->reorder[best] = d->reorder[--d->reorder_count];
}

static void flush_reorder(Device *d) {
	while (d->reorder_count > 0) {
		take_lowest(d);
	}
}

static void take_access_unit(Device *d, OutBuf *o) {
	const uint8_t *p = o->map;
	int size = o->bytes;
	int slice = 0;
	for (int i = 0; i + 4 < size; i++) {
		if (p[i] != 0 || p[i + 1] != 0 || p[i + 2] != 1) {
			continue;
		}
		const int type = p[i + 3] & 31;
		if (type == 7) {
			parse_sps(d, p + i + 4, size - i - 4);
			if (!d->source_change_sent) {
				d->source_change_pending = 1;
			}
		} else if (type == 10) {
			flush_reorder(d);
		} else if ((type == 1 || type == 5) && !slice) {
			slice = 1;
			if (type == 5) {
				flush_reorder(d);
			}
			Picture picture;
			picture.poc = parse_poc(d, p + i + 4, size - i - 4, type == 5);
			picture.ts = o->ts;
			d->reorder[d->reorder_count++] = picture;
			if (logging) {
				fprintf(stderr, "fake_v4l2: AU ts %ld.%06ld poc %d, %d waiting\n", (long)o->ts.tv_sec, (long)o->ts.tv_usec, picture.poc, d->reorder_count);
			}
			while (d->reorder_count > delay_pictures) {
				take_lowest(d);
			}
		}
	}
}

// Moves pictures to free CAPTURE buffers, then takes the next OUTPUT buffer once nothing waits for a CAPTURE buffer.
static void run_decoder(Device *d) {
	for (;;) {
		while (d->due_count > 0) {
			int k = -1;
			for (uint32_t i = 0; i < d->cap_count; i++) {
				if (d->cap[i].in_driver) {
					k = (int)i;
					break;
				}
			}
			if (k < 0) {
				return;
			}
			CapBuf *c = &d->cap[k];
			c->in_driver = 0;
			c->filled = 1;
			c->bytes = d->sizeimage;
			c->ts = d->due[0].ts;
			c->last = 0;
			c->order = d->order++;
			memmove(&d->due[0], &d->due[1], sizeof(Picture) * (--d->due_count));
			if (logging) {
				fprintf(stderr, "fake_v4l2: picture ts %ld.%06ld out\n", (long)c->ts.tv_sec, (long)c->ts.tv_usec);
			}
		}
		if (!d->out_streaming) {
			return;
		}
		int next = -1;
		for (uint32_t i = 0; i < d->out_count; i++) {
			if (d->out[i].in_driver && (next < 0 || d->out[i].order < d->out[next].order)) {
				next = (int)i;
			}
		}
		if (next < 0) {
			break;
		}
		if (d->source_change_pending || (d->source_change_sent && !d->cap_streaming)) {
			return; // A stateful decoder waits for CAPTURE after SOURCE_CHANGE.
		}
		take_access_unit(d, &d->out[next]);
		d->out[next].in_driver = 0;
		d->out[next].done = 1;
	}
	if (d->stop && !d->last_sent && d->cap_streaming) {
		flush_reorder(d);
		if (d->due_count > 0) {
			run_decoder(d);
			return;
		}
		for (uint32_t i = 0; i < d->cap_count; i++) {
			if (d->cap[i].in_driver) {
				CapBuf *c = &d->cap[i];
				c->in_driver = 0;
				c->filled = 1;
				c->bytes = 0;
				c->last = 1;
				c->order = d->order++;
				d->last_sent = 1;
				break;
			}
		}
	}
}

static int device_ioctl(Device *d, unsigned long request, void *arg) {
	switch (request) {
		case VIDIOC_QUERYCAP: {
			struct v4l2_capability *c = arg;
			memset(c, 0, sizeof(*c));
			strcpy((char *)c->driver, "fake");
			strcpy((char *)c->card, "fake stateful decoder");
			c->capabilities = V4L2_CAP_VIDEO_M2M_MPLANE | V4L2_CAP_STREAMING | V4L2_CAP_DEVICE_CAPS;
			c->device_caps = V4L2_CAP_VIDEO_M2M_MPLANE | V4L2_CAP_STREAMING;
			return 0;
		}
		case VIDIOC_ENUM_FMT: {
			struct v4l2_fmtdesc *f = arg;
			if (f->index != 0) {
				errno = EINVAL;
				return -1;
			}
			f->pixelformat = f->type == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE ? V4L2_PIX_FMT_H264 : V4L2_PIX_FMT_NV12;
			return 0;
		}
		case VIDIOC_S_FMT:
		case VIDIOC_G_FMT: {
			struct v4l2_format *f = arg;
			if (f->type == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE) {
				if (request == VIDIOC_S_FMT) {
					d->width = f->fmt.pix_mp.width;
					d->height = f->fmt.pix_mp.height;
					if (!f->fmt.pix_mp.plane_fmt[0].sizeimage) {
						f->fmt.pix_mp.plane_fmt[0].sizeimage = 1 << 20;
					}
					d->sizeimage = f->fmt.pix_mp.plane_fmt[0].sizeimage;
				}
				return 0;
			}
			f->fmt.pix_mp.pixelformat = V4L2_PIX_FMT_NV12;
			f->fmt.pix_mp.width = (d->width + 15) & ~15u;
			f->fmt.pix_mp.height = (d->height + 15) & ~15u;
			f->fmt.pix_mp.num_planes = 1;
			f->fmt.pix_mp.plane_fmt[0].bytesperline = f->fmt.pix_mp.width;
			f->fmt.pix_mp.plane_fmt[0].sizeimage = f->fmt.pix_mp.width * f->fmt.pix_mp.height * 3 / 2;
			return 0;
		}
		case VIDIOC_G_SELECTION: {
			struct v4l2_selection *s = arg;
			s->r.left = s->r.top = 0;
			s->r.width = d->width;
			s->r.height = d->height;
			return 0;
		}
		case VIDIOC_G_CTRL: {
			struct v4l2_control *c = arg;
			c->value = CAPTURE_MIN;
			return 0;
		}
		case VIDIOC_REQBUFS: {
			struct v4l2_requestbuffers *r = arg;
			if (r->count > MAX_BUFFERS) {
				r->count = MAX_BUFFERS;
			}
			if (r->type == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE) {
				d->out_count = r->count;
			} else {
				d->cap_count = r->count;
				memset(d->cap, 0, sizeof(d->cap));
			}
			return 0;
		}
		case VIDIOC_QUERYBUF: {
			struct v4l2_buffer *b = arg;
			b->m.planes[0].length = d->sizeimage;
			b->m.planes[0].m.mem_offset = OUT_OFFSET + b->index * 4096;
			return 0;
		}
		case VIDIOC_EXPBUF: {
			struct v4l2_exportbuffer *e = arg;
			e->fd = memfd_create("fake-capture", MFD_CLOEXEC);
			if (ftruncate(e->fd, 1 << 16) != 0) {
				return -1;
			}
			return 0;
		}
		case VIDIOC_SUBSCRIBE_EVENT:
			return 0;
		case VIDIOC_DQEVENT: {
			struct v4l2_event *e = arg;
			if (!d->source_change_pending) {
				errno = ENOENT;
				return -1;
			}
			memset(e, 0, sizeof(*e));
			e->type = V4L2_EVENT_SOURCE_CHANGE;
			e->u.src_change.changes = V4L2_EVENT_SRC_CH_RESOLUTION;
			d->source_change_pending = 0;
			d->source_change_sent = 1;
			return 0;
		}
		case VIDIOC_STREAMON: {
			int type = *(int *)arg;
			if (type == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE) {
				d->out_streaming = 1;
			} else {
				d->cap_streaming = 1;
			}
			run_decoder(d);
			return 0;
		}
		case VIDIOC_STREAMOFF: {
			int type = *(int *)arg;
			if (type == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE) {
				d->out_streaming = 0;
			} else {
				d->cap_streaming = 0;
			}
			return 0;
		}
		case VIDIOC_DECODER_CMD: {
			d->stop = 1;
			run_decoder(d);
			return 0;
		}
		case VIDIOC_QBUF: {
			struct v4l2_buffer *b = arg;
			if (b->type == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE) {
				OutBuf *o = &d->out[b->index];
				o->bytes = b->m.planes[0].bytesused;
				o->ts = b->timestamp;
				o->in_driver = 1;
				o->done = 0;
				o->order = d->order++;
			} else {
				CapBuf *c = &d->cap[b->index];
				c->in_driver = 1;
				c->filled = 0;
			}
			run_decoder(d);
			return 0;
		}
		case VIDIOC_DQBUF: {
			struct v4l2_buffer *b = arg;
			int best = -1;
			if (b->type == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE) {
				for (uint32_t i = 0; i < d->out_count; i++) {
					if (d->out[i].done) {
						best = (int)i;
						break;
					}
				}
				if (best < 0) {
					errno = EAGAIN;
					return -1;
				}
				d->out[best].done = 0;
				b->index = best;
				return 0;
			}
			for (uint32_t i = 0; i < d->cap_count; i++) {
				if (d->cap[i].filled && (best < 0 || d->cap[i].order < d->cap[best].order)) {
					best = (int)i;
				}
			}
			if (best < 0) {
				errno = d->last_sent ? EPIPE : EAGAIN;
				return -1;
			}
			CapBuf *c = &d->cap[best];
			c->filled = 0;
			b->index = best;
			b->timestamp = c->ts;
			b->flags = c->last ? V4L2_BUF_FLAG_LAST : 0;
			b->m.planes[0].bytesused = c->bytes;
			b->m.planes[0].data_offset = 0;
			return 0;
		}
		default:
			errno = ENOTTY;
			return -1;
	}
}

static int device_events(Device *d) {
	int events = 0;
	if (d->source_change_pending) {
		events |= POLLPRI;
	}
	for (uint32_t i = 0; i < d->out_count; i++) {
		if (d->out[i].done) {
			events |= POLLOUT;
		}
	}
	for (uint32_t i = 0; i < d->cap_count; i++) {
		if (d->cap[i].filled) {
			events |= POLLIN;
		}
	}
	return events;
}

/* Interposed */

static int open_common(const char *path, int flags, mode_t mode) {
	if (strcmp(path, DEVICE) != 0) {
		return real_open(path, flags, mode);
	}
	pthread_mutex_lock(&lock);
	int fd = eventfd(0, EFD_CLOEXEC);
	for (int i = 0; i < 8; i++) {
		if (devices[i] == NULL) {
			devices[i] = calloc(1, sizeof(Device));
			devices[i]->fd = fd;
			break;
		}
	}
	pthread_mutex_unlock(&lock);
	return fd;
}

int open(const char *path, int flags, ...) {
	va_list ap;
	va_start(ap, flags);
	mode_t mode = va_arg(ap, mode_t);
	va_end(ap);
	return open_common(path, flags, mode);
}

int open64(const char *path, int flags, ...) {
	va_list ap;
	va_start(ap, flags);
	mode_t mode = va_arg(ap, mode_t);
	va_end(ap);
	return open_common(path, flags, mode);
}

int stat(const char *path, struct stat *st) {
	return real_stat(strcmp(path, DEVICE) == 0 ? "/dev/null" : path, st);
}

int stat64(const char *path, struct stat64 *st) {
	return ((int (*)(const char *, struct stat64 *))dlsym(RTLD_NEXT, "stat64"))(strcmp(path, DEVICE) == 0 ? "/dev/null" : path, st);
}

int close(int fd) {
	pthread_mutex_lock(&lock);
	for (int i = 0; i < 8; i++) {
		if (devices[i] && devices[i]->fd == fd) {
			free(devices[i]);
			devices[i] = NULL;
		}
	}
	pthread_mutex_unlock(&lock);
	return real_close(fd);
}

int ioctl(int fd, unsigned long request, ...) {
	va_list ap;
	va_start(ap, request);
	void *arg = va_arg(ap, void *);
	va_end(ap);
	pthread_mutex_lock(&lock);
	Device *d = find_device(fd);
	if (d) {
		int r = device_ioctl(d, request, arg);
		int e = errno;
		pthread_mutex_unlock(&lock);
		errno = e;
		return r;
	}
	pthread_mutex_unlock(&lock);
	return real_ioctl(fd, request, arg);
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
	pthread_mutex_lock(&lock);
	Device *d = fd >= 0 ? find_device(fd) : NULL;
	pthread_mutex_unlock(&lock);
	if (d == NULL) {
		return real_mmap(addr, length, prot, flags, fd, offset);
	}
	void *map = real_mmap(addr, length, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	pthread_mutex_lock(&lock);
	d->out[(offset - OUT_OFFSET) / 4096].map = map;
	pthread_mutex_unlock(&lock);
	return map;
}

void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off64_t offset) {
	return mmap(addr, length, prot, flags, fd, offset);
}

int poll(struct pollfd *fds, nfds_t count, int timeout) {
	int any = 0;
	pthread_mutex_lock(&lock);
	for (nfds_t i = 0; i < count; i++) {
		any |= find_device(fds[i].fd) != NULL;
	}
	pthread_mutex_unlock(&lock);
	if (!any) {
		return real_poll(fds, count, timeout);
	}
	// A millisecond at a time: the fake device has no wait queue.
	struct timespec start;
	clock_gettime(CLOCK_MONOTONIC, &start);
	for (;;) {
		int ready = 0;
		struct pollfd real[8];
		int real_index[8];
		nfds_t real_count = 0;
		pthread_mutex_lock(&lock);
		for (nfds_t i = 0; i < count; i++) {
			Device *d = find_device(fds[i].fd);
			if (d) {
				fds[i].revents = device_events(d) & (fds[i].events | POLLPRI);
				ready += fds[i].revents != 0;
			} else {
				real[real_count] = fds[i];
				real_index[real_count++] = (int)i;
			}
		}
		pthread_mutex_unlock(&lock);
		if (real_poll(real, real_count, ready ? 0 : 1) > 0) {
			for (nfds_t k = 0; k < real_count; k++) {
				fds[real_index[k]].revents = real[k].revents;
				ready += real[k].revents != 0;
			}
		}
		if (ready) {
			return ready;
		}
		struct timespec now;
		clock_gettime(CLOCK_MONOTONIC, &now);
		const long ms = (now.tv_sec - start.tv_sec) * 1000 + (now.tv_nsec - start.tv_nsec) / 1000000;
		if (timeout >= 0 && ms >= timeout) {
			return 0;
		}
	}
}
