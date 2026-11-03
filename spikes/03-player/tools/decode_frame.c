// Decodes the frame at media time T (pts minus the file's start time, as MediaSource counts) and writes it as raw
// planar yuv420p10le (Y, then U, then V; 16-bit little-endian samples): the reference for q10c_analyze.py.
//   decode_frame IN T OUT.yuv
// Build in WSL against the x86_64 FFmpeg of build/ffmpeg-build.sh (it has the hevc decoder):
//   gcc -O1 -o /tmp/decode_frame decode_frame.c -I$HOME/src/ffmpeg-x86_64/include -L$HOME/src/ffmpeg-x86_64/lib
//     -L$HOME/src/ffmpeg-build-x86_64/zlib -lavformat -lavcodec -lswresample -lavutil -lz -lm -lpthread
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/pixdesc.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
	if (argc < 4) return 2;
	double target = atof(argv[2]);
	AVFormatContext *in = NULL;
	if (avformat_open_input(&in, argv[1], NULL, NULL) < 0 || avformat_find_stream_info(in, NULL) < 0) return 1;
	int vi = av_find_best_stream(in, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
	AVStream *st = in->streams[vi];
	const AVCodec *codec = avcodec_find_decoder(st->codecpar->codec_id);
	AVCodecContext *c = avcodec_alloc_context3(codec);
	avcodec_parameters_to_context(c, st->codecpar);
	c->pkt_timebase = st->time_base;
	c->thread_count = 8;
	if (avcodec_open2(c, codec, NULL) < 0) return 1;
	double start = in->start_time != AV_NOPTS_VALUE ? in->start_time / (double)AV_TIME_BASE : 0.0;
	av_seek_frame(in, -1, (int64_t)((target + start - 3.0) * AV_TIME_BASE), AVSEEK_FLAG_BACKWARD);
	AVPacket *p = av_packet_alloc();
	AVFrame *f = av_frame_alloc();
	while (av_read_frame(in, p) >= 0) {
		if (p->stream_index != vi) { av_packet_unref(p); continue; }
		avcodec_send_packet(c, p);
		av_packet_unref(p);
		while (avcodec_receive_frame(c, f) >= 0) {
			double t = f->best_effort_timestamp * av_q2d(st->time_base) - start;
			if (fabs(t - target) < 0.0015) {
				FILE *out = fopen(argv[3], "wb");
				for (int pl = 0; pl < 3; pl++) {
					int h = pl ? (f->height + 1) / 2 : f->height, w = pl ? (f->width + 1) / 2 : f->width;
					for (int y = 0; y < h; y++) fwrite(f->data[pl] + (size_t)y * f->linesize[pl], 2, w, out);
				}
				fclose(out);
				printf("frame %.4f: %dx%d %s written\n", t, f->width, f->height, av_get_pix_fmt_name(f->format));
				return 0;
			}
			if (t > target + 0.1) { printf("passed %.4f without a match\n", t); return 1; }
		}
	}
	return 1;
}
