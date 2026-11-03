// Test client for spike 05: an X11 window that animates (so DAMAGE fires) and logs every input event it gets, with the
// send_event flag, so synthetic (SendEvent) and real (XTEST) input can be told apart.
//   cc -O2 -o testwin testwin.c -lxcb
//   ./testwin [--title=NAME] [--size=WxH] [--fps=N] [--static]
// Output lines: "EVENT <type> ... synthetic=<0|1>". --static draws once (an idle window: no damage after the first frame).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <xcb/xcb.h>

static uint64_t now_ms(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(int argc, char **argv) {
	const char *title = "x11window-test";
	int width = 640, height = 360, fps = 30, animate = 1, resize_after = -1, exit_after = -1;
	for (int i = 1; i < argc; i++) {
		if (!strncmp(argv[i], "--title=", 8)) {
			title = argv[i] + 8;
		} else if (!strncmp(argv[i], "--size=", 7)) {
			sscanf(argv[i] + 7, "%dx%d", &width, &height);
		} else if (!strncmp(argv[i], "--fps=", 6)) {
			fps = atoi(argv[i] + 6);
		} else if (!strcmp(argv[i], "--static")) {
			animate = 0;
		} else if (!strncmp(argv[i], "--resize-after=", 15)) {
			resize_after = atoi(argv[i] + 15);
		} else if (!strncmp(argv[i], "--exit-after=", 13)) {
			exit_after = atoi(argv[i] + 13);
		}
	}
	xcb_connection_t *c = xcb_connect(NULL, NULL);
	if (xcb_connection_has_error(c)) {
		fprintf(stderr, "can't connect\n");
		return 1;
	}
	xcb_screen_t *screen = xcb_setup_roots_iterator(xcb_get_setup(c)).data;
	xcb_window_t w = xcb_generate_id(c);
	uint32_t values[2] = { screen->black_pixel,
		XCB_EVENT_MASK_EXPOSURE | XCB_EVENT_MASK_KEY_PRESS | XCB_EVENT_MASK_KEY_RELEASE | XCB_EVENT_MASK_BUTTON_PRESS |
				XCB_EVENT_MASK_BUTTON_RELEASE | XCB_EVENT_MASK_POINTER_MOTION | XCB_EVENT_MASK_ENTER_WINDOW |
				XCB_EVENT_MASK_LEAVE_WINDOW | XCB_EVENT_MASK_FOCUS_CHANGE | XCB_EVENT_MASK_STRUCTURE_NOTIFY };
	xcb_create_window(c, XCB_COPY_FROM_PARENT, w, screen->root, 0, 0, width, height, 0, XCB_WINDOW_CLASS_INPUT_OUTPUT,
			screen->root_visual, XCB_CW_BACK_PIXEL | XCB_CW_EVENT_MASK, values);
	xcb_change_property(c, XCB_PROP_MODE_REPLACE, w, XCB_ATOM_WM_NAME, XCB_ATOM_STRING, 8, strlen(title), title);
	const char wm_class[] = "x11window-test\0X11WindowTest";
	xcb_change_property(c, XCB_PROP_MODE_REPLACE, w, XCB_ATOM_WM_CLASS, XCB_ATOM_STRING, 8, sizeof(wm_class), wm_class);
	xcb_map_window(c, w);
	xcb_gcontext_t gc = xcb_generate_id(c);
	xcb_create_gc(c, gc, w, 0, NULL);
	xcb_flush(c);
	printf("WINDOW 0x%x %dx%d\n", w, width, height);
	fflush(stdout);

	// Content: a horizontal colour ramp; a white bar sweeps across (animation); a red cross marks the last click.
	uint32_t *pixels = malloc((size_t)width * height * 4);
	int frame = 0, click_x = -1, click_y = -1, drawn = 0;
	uint64_t next = now_ms();
	for (;;) {
		xcb_generic_event_t *e;
		while ((e = xcb_poll_for_event(c))) {
			const int synthetic = (e->response_type & 0x80) != 0;
			switch (e->response_type & 0x7f) {
				case XCB_KEY_PRESS:
				case XCB_KEY_RELEASE: {
					xcb_key_press_event_t *k = (xcb_key_press_event_t *)e;
					printf("EVENT %s keycode=%d state=0x%x synthetic=%d\n", (e->response_type & 0x7f) == XCB_KEY_PRESS ? "KeyPress" : "KeyRelease", k->detail, k->state, synthetic);
				} break;
				case XCB_BUTTON_PRESS:
				case XCB_BUTTON_RELEASE: {
					xcb_button_press_event_t *b = (xcb_button_press_event_t *)e;
					printf("EVENT %s button=%d x=%d y=%d state=0x%x synthetic=%d\n", (e->response_type & 0x7f) == XCB_BUTTON_PRESS ? "ButtonPress" : "ButtonRelease", b->detail, b->event_x, b->event_y, b->state, synthetic);
					if ((e->response_type & 0x7f) == XCB_BUTTON_PRESS && b->detail == 1) {
						click_x = b->event_x;
						click_y = b->event_y;
						drawn = 0;
					}
				} break;
				case XCB_MOTION_NOTIFY: {
					xcb_motion_notify_event_t *m = (xcb_motion_notify_event_t *)e;
					printf("EVENT Motion x=%d y=%d synthetic=%d\n", m->event_x, m->event_y, synthetic);
				} break;
				case XCB_ENTER_NOTIFY:
					printf("EVENT Enter synthetic=%d\n", synthetic);
					break;
				case XCB_LEAVE_NOTIFY:
					printf("EVENT Leave synthetic=%d\n", synthetic);
					break;
				case XCB_FOCUS_IN:
					printf("EVENT FocusIn synthetic=%d\n", synthetic);
					break;
				case XCB_FOCUS_OUT:
					printf("EVENT FocusOut synthetic=%d\n", synthetic);
					break;
				case XCB_CONFIGURE_NOTIFY: {
					xcb_configure_notify_event_t *cn = (xcb_configure_notify_event_t *)e;
					if (cn->width != width || cn->height != height) {
						width = cn->width;
						height = cn->height;
						pixels = realloc(pixels, (size_t)width * height * 4);
						drawn = 0;
						printf("EVENT Resize %dx%d\n", width, height);
					}
				} break;
				case XCB_EXPOSE:
					drawn = 0;
					break;
				default:
					break;
			}
			fflush(stdout);
			free(e);
		}
		if (xcb_connection_has_error(c)) {
			break;
		}
		if (now_ms() >= next && (animate || !drawn)) {
			next += 1000 / (fps > 0 ? fps : 30);
			const int bar = animate ? (frame * 8) % width : -100;
			for (int y = 0; y < height; y++) {
				for (int x = 0; x < width; x++) {
					uint32_t r = (uint32_t)(255 * x / (width > 1 ? width - 1 : 1)), g = (uint32_t)(255 * y / (height > 1 ? height - 1 : 1)), b = 128;
					if (x >= bar && x < bar + 16) {
						r = g = b = 255;
					}
					if ((x == click_x && abs(y - click_y) < 20) || (y == click_y && abs(x - click_x) < 20)) {
						r = 255;
						g = b = 0;
					}
					pixels[(size_t)y * width + x] = 0xff000000u | (r << 16) | (g << 8) | b;
				}
			}
			// One PutImage per band, under the request size limit.
			const int rows = 262144 / (width * 4) > 0 ? 262144 / (width * 4) : 1;
			for (int y = 0; y < height; y += rows) {
				const int h = y + rows <= height ? rows : height - y;
				xcb_put_image(c, XCB_IMAGE_FORMAT_Z_PIXMAP, w, gc, width, h, 0, y, 0, 24, (uint32_t)width * h * 4, (const uint8_t *)(pixels + (size_t)y * width));
			}
			xcb_flush(c);
			frame++;
			drawn = 1;
			if (frame == resize_after) {
				const uint32_t new_size[2] = { (uint32_t)width * 3 / 2, (uint32_t)height * 3 / 2 };
				xcb_configure_window(c, w, XCB_CONFIG_WINDOW_WIDTH | XCB_CONFIG_WINDOW_HEIGHT, new_size);
				xcb_flush(c);
				printf("RESIZE requested %ux%u\n", new_size[0], new_size[1]);
				fflush(stdout);
			}
			if (frame == exit_after) {
				printf("EXIT\n");
				fflush(stdout);
				break;
			}
		}
		usleep(2000);
	}
	return 0;
}
